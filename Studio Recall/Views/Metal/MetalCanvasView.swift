//
//  MetalCanvasView.swift
//  Studio Recall
//
//  Metal-accelerated canvas renderer for high-performance session view
//

import SwiftUI
import MetalKit

/// SwiftUI wrapper for MTKView
struct MetalCanvasView: NSViewRepresentable {
	@Binding var session: Session
	let settings: AppSettings
	let library: DeviceLibrary

	func makeCoordinator() -> Coordinator {
		Coordinator(session: $session, settings: settings, library: library)
	}

	func makeNSView(context: Context) -> MTKView {
		let mtkView = MTKView()
		mtkView.device = MTLCreateSystemDefaultDevice()
		mtkView.delegate = context.coordinator
		mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
		mtkView.colorPixelFormat = .bgra8Unorm
		mtkView.depthStencilPixelFormat = .depth32Float
		mtkView.framebufferOnly = false
		mtkView.enableSetNeedsDisplay = false
		mtkView.isPaused = false
		mtkView.preferredFramesPerSecond = 120

		context.coordinator.mtkView = mtkView
		context.coordinator.setupMetal()

		return mtkView
	}

	func updateNSView(_ nsView: MTKView, context: Context) {
		// Update coordinator's session binding
		context.coordinator.session = $session
		nsView.setNeedsDisplay(nsView.bounds)
	}

	// MARK: - Coordinator

	class Coordinator: NSObject, MTKViewDelegate {
		var session: Binding<Session>
		let settings: AppSettings
		let library: DeviceLibrary

		weak var mtkView: MTKView?
		var device: MTLDevice!
		var commandQueue: MTLCommandQueue!
		var pipelineState: MTLRenderPipelineState!

		// Texture atlas for device faceplates
		var textureAtlas: MetalTextureAtlas?
		var renderer: MetalRenderer?

		init(session: Binding<Session>, settings: AppSettings, library: DeviceLibrary) {
			self.session = session
			self.settings = settings
			self.library = library
			super.init()
		}

		func setupMetal() {
			guard let mtkView = mtkView,
				  let device = mtkView.device else {
				print("❌ Metal device not available")
				return
			}

			self.device = device
			self.commandQueue = device.makeCommandQueue()

			// Create texture atlas
			self.textureAtlas = MetalTextureAtlas(device: device, library: library)

			// Create renderer
			self.renderer = MetalRenderer(device: device)
		}

		// MARK: - MTKViewDelegate

		func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
			// Handle resize if needed
		}

		func draw(in view: MTKView) {
			guard let commandBuffer = commandQueue.makeCommandBuffer(),
				  let renderPassDescriptor = view.currentRenderPassDescriptor,
				  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
				  let renderer = renderer,
				  let textureAtlas = textureAtlas else {
				return
			}

			// Render session (synchronously access MainActor data)
			Task { @MainActor in
				self.renderSession(encoder: renderEncoder, view: view, renderer: renderer, textureAtlas: textureAtlas)

				renderEncoder.endEncoding()

				if let drawable = view.currentDrawable {
					commandBuffer.present(drawable)
				}

				commandBuffer.commit()
			}
		}

		@MainActor
		func renderSession(encoder: MTLRenderCommandEncoder, view: MTKView, renderer: MetalRenderer, textureAtlas: MetalTextureAtlas) {
			let sess = session.wrappedValue
			let zoom = Float(sess.canvasZoom)
			let pan = sess.canvasPan
			let viewSize = view.drawableSize

			// Create projection matrix (orthographic, origin at top-left, matches SwiftUI coordinate system)
			let projectionMatrix = MetalRenderer.makeOrthoMatrix(
				left: 0,
				right: Float(viewSize.width),
				bottom: Float(viewSize.height),
				top: 0,
				near: -100,
				far: 100
			)

			// Create view matrix matching SwiftUI's .scaleEffect then .offset
			// SwiftUI does: content -> scale -> offset
			// So view matrix = offset × scale (applied right-to-left)
			let scaleMatrix = MetalRenderer.makeScaleMatrix(x: zoom, y: zoom, z: 1)
			let translateMatrix = MetalRenderer.makeTranslationMatrix(x: Float(pan.x), y: Float(pan.y), z: 0)
			let viewMatrix = simd_mul(translateMatrix, scaleMatrix)

			let uniforms = MetalUniforms(
				projectionMatrix: projectionMatrix,
				viewMatrix: viewMatrix
			)

			// Build instance data for all visible devices
			var instances: [MetalInstanceData] = []

			// Debug: log once per second (at 120fps, every ~120 frames)
			let shouldLog = (Int(Date().timeIntervalSince1970) % 2 == 0)

			// Render all racks
			for (rackIdx, rack) in sess.racks.enumerated() {
				// Constants matching RackChassisView (lines 34-36, 80-88)
				let ppi = settings.pointsPerInch
				let oneU = DeviceMetrics.rackSize(units: 1, scale: ppi)
				let rowH = oneU.height
				let rowSpacing: CGFloat = 1  // RackChassisView.rowSpacing (line 34)
				let facePadding: CGFloat = 16  // RackChassisView.facePadding (line 35)
				let innerW = oneU.width
				let faceW = innerW + facePadding * 2
				let faceH = facePadding * 2 + CGFloat(rack.rows) * rowH + rowSpacing * CGFloat(max(0, rack.rows - 1))

				// rack.position is CENTER of the rack view (DragStrip + face)
				// Calculate top-left corner
				let dragStripHeight: CGFloat = 32
				let totalHeight = dragStripHeight + faceH
				let rackTopLeft = CGPoint(
					x: rack.position.x - faceW / 2,
					y: rack.position.y - totalHeight / 2
				)

				// Content area origin (inside facePadding, below dragStrip)
				let contentOrigin = CGPoint(
					x: rackTopLeft.x + facePadding,
					y: rackTopLeft.y + dragStripHeight + facePadding
				)

				for (rowIdx, row) in rack.slots.enumerated() {
					for (colIdx, maybeInstance) in row.enumerated() {
						guard let instance = maybeInstance,
							  let device = library.device(for: instance.deviceID),
							  let texCoords = textureAtlas.getTextureCoords(for: device.id) else {
							continue
						}

						let deviceRows = device.rackUnits ?? 1
						let deviceCols = device.rackWidth.rawValue

						// Only render anchor (top-left) instance
						let isAnchor = (rowIdx == 0 || rack.slots[rowIdx - 1][colIdx]?.id != instance.id) &&
									   (colIdx == 0 || rack.slots[rowIdx][colIdx - 1]?.id != instance.id)

						guard isAnchor else { continue }

						// Calculate device slot dimensions
						// innerW is FULL rack width (19"), divide by 6 columns
						let singleColWidth = innerW / 6.0
						let deviceSlotWidth = singleColWidth * CGFloat(deviceCols)
						let deviceSlotHeight = rowH * CGFloat(deviceRows) + rowSpacing * CGFloat(deviceRows - 1)

						// Get actual rendered face size (respects aspect ratio)
						let faceMetrics = DeviceMetrics.faceRenderMetrics(
							faceWidthPts: deviceSlotWidth,
							slotHeightPts: deviceSlotHeight,
							imageData: device.imageData
						)

						// Position: top-left of device slot + vertical offset for centering
						let deviceLeft = contentOrigin.x + CGFloat(colIdx) * singleColWidth
						let deviceTop = contentOrigin.y + CGFloat(rowIdx) * (rowH + rowSpacing) + faceMetrics.vOffset

						// Center point of the rendered face (Metal quads are centered at origin)
						let deviceCenterX = deviceLeft + faceMetrics.size.width / 2
						let deviceCenterY = deviceTop + faceMetrics.size.height / 2


						// Create model matrix: translate to center, then scale to rendered size
						let modelMatrix = simd_mul(
							MetalRenderer.makeTranslationMatrix(
								x: Float(deviceCenterX),
								y: Float(deviceCenterY),
								z: 0
							),
							MetalRenderer.makeScaleMatrix(
								x: Float(faceMetrics.size.width),
								y: Float(faceMetrics.size.height),
								z: 1
							)
						)

						let instanceData = MetalInstanceData(
							modelMatrix: modelMatrix,
							texCoordRect: SIMD4<Float>(
								Float(texCoords.origin.x),
								Float(texCoords.origin.y),
								Float(texCoords.size.width),
								Float(texCoords.size.height)
							),
							alpha: 1.0
						)

						instances.append(instanceData)
					}
				}
			}

			// Render all instances
			renderer.render(
				encoder: encoder,
				instances: instances,
				uniforms: uniforms,
				atlasTexture: textureAtlas.atlasTexture
			)
		}
	}
}
