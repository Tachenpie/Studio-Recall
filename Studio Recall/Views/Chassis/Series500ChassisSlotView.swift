//
//  Series500ChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI
import AppKit

struct Series500ChassisSlotView: View {
    let index: Int
    let instance: DeviceInstance?
    @Binding var slots: [DeviceInstance?]
    
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var sessionManager: SessionManager
    
	@Environment(\.isInteracting) private var isInteracting
	@Environment(\.displayScale) private var displayScale
	@Environment(\.renderStyle) private var renderStyle
	@Environment(\.canvasZoom) private var canvasZoom
	
    @Binding var hoveredIndex: Int?
    @Binding var hoveredRange: Range<Int>?
    @Binding var hoveredValid: Bool
	
	@State private var slotHover = false
	@State private var editingDevice: Device?
	@State private var isPresentingEditor = false

    var body: some View {
        Group {
            if let instance, let device = library.device(for: instance.deviceID) {
                deviceView(device, instance: instance)
            } else {
                emptySlotView()
            }
        }
    }

	private func deviceView(_ device: Device, instance: DeviceInstance) -> some View {
		let units = device.slotWidth ?? 1
		let rawSlot = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)
		
		let slotW = (rawSlot.width  * displayScale).rounded() / displayScale
		let slotH = (rawSlot.height * displayScale).rounded() / displayScale
		let slotSize = CGSize(width: slotW, height: slotH)
		
		guard let topIndex = indexOfInstance(instance) else {
			return AnyView(EmptyView())
		}
		
		let instanceBinding = Binding<DeviceInstance>(
			get: { slots[topIndex]! },
			set: { newVal in
				let span = topIndex ..< min(topIndex + max(1, units), slots.count)
				for i in span { slots[i] = newVal }
			}
		)
		
		let fm = DeviceMetrics.faceRenderMetrics(
			faceWidthPts: slotSize.width,
			slotHeightPts: slotSize.height,
			imageData: device.imageData
		)
		
		let faceW = (fm.size.width  * displayScale).rounded() / displayScale
		let faceH = (fm.size.height * displayScale).rounded() / displayScale
		let vOffset = ((slotSize.height - faceH) * 0.5 * displayScale).rounded() / displayScale
		let snappedFM = FaceRenderMetrics(size: CGSize(width: faceW, height: faceH), vOffset: vOffset)
		
		let faceGroup = ZStack(alignment: .topLeading) {
			// Face bitmap
			DeviceView(device: device, metrics: snappedFM)
				.frame(width: snappedFM.size.width, height: snappedFM.size.height)
				.allowsHitTesting(false)
				.modifier(ConditionalDrawingGroup(active: renderStyle == .photoreal && isInteracting))
			
			// Runtime overlay - use the same metrics
			RuntimeControlsOverlay(
				device: device,
				instance: instanceBinding,
				prelayout: nil,
				faceMetrics: snappedFM
			)
			.frame(width: snappedFM.size.width, height: snappedFM.size.height)
			.zIndex(1)
			.allowsHitTesting(true)
			
			// Labels anchored to the device
			if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
				let session = $sessionManager.sessions[i]
				LabelCanvas(
					labels: session.labels,
					anchor: .deviceInstance(instance.id),
					parentOrigin: .zero
				)
				.allowsHitTesting(true)
			}
		}
		.offset(y: snappedFM.vOffset)
			
		let body = ZStack(alignment: .topLeading) {
			faceGroup
			
			// ✅ Draggable rails with screws (500-series: top & bottom)
			.overlay(alignment: .top) {
				RailH(height: 3)
//					.compositingGroup()
					.contentShape(Rectangle())
					.onDrag {
						deviceDragProvider(instance: instance, device: device) // top rail drag
					} preview: {
						devicePreviewView(device: device, metrics: snappedFM, slotSize: slotSize)
					}
					.contextMenu {
						Button("Edit Device...") {
							editingDevice = device
							isPresentingEditor = true
						}
						Button("Remove from rack", role: .destructive) {
							removeInstance(instance, of: device)
						}
					}
			}

			.overlay(alignment: .bottom) {
				RailH(height: 3)
//					.compositingGroup()
					.contentShape(Rectangle())
					.onDrag {
						deviceDragProvider(instance: instance, device: device) // bottom rail drag
					} preview: {
						devicePreviewView(device: device, metrics: snappedFM, slotSize: slotSize)
					}
					.contextMenu {
						Button("Edit Device...") {
							editingDevice = device
							isPresentingEditor = true
						}
						Button("Remove from rack", role: .destructive) {
							removeInstance(instance, of: device)
						}
					}
			}
		}
		.frame(width: slotSize.width, height: slotSize.height, alignment: .topLeading)
		.clipShape(Rectangle())
		.padding(.vertical, 4)
		.overlay(
			Rectangle()
				.stroke(highlightColor(), lineWidth: 3)
				.allowsHitTesting(false)
		)
		.sheet(item: $editingDevice) { device in
			DeviceEditorView(
				editableDevice: EditableDevice(device: device),
				onCommit: { updated in
					// Save updated device back into your devices array / library
					library.update(updated)
					editingDevice = nil
				},
				onCancel: {
					editingDevice = nil
				}
			)
		}

		return AnyView(body)
	}

	private func emptySlotView(units: Int = 1) -> some View {
		let moduleSize = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)
		
		return Rectangle()
		// tiny alpha keeps it in the hit-testing tree but is visually identical
			.fill(Color.white.opacity(0.06))
			.frame(width: moduleSize.width, height: moduleSize.height)
			.overlay(
				Group {
					if !isInteracting {
						Rectangle()
							.stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
					}
				}
			)
			.contentShape(Rectangle()) // <- important for drops
	}

    private func highlightColor() -> Color {
        if let range = hoveredRange, range.contains(index) {
            return hoveredValid ? .green : .red
        }
        return .clear
    }
	
	private func indexOfInstance(_ instance: DeviceInstance) -> Int? {
		slots.firstIndex(where: { $0?.id == instance.id })
	}
	
	private func removeInstance(_ instance: DeviceInstance, of device: Device) {
		guard let start = slots.firstIndex(where: { $0?.id == instance.id }) else { return }
		let count = max(1, device.slotWidth ?? 1)
		let end = min(start + count, slots.count)
		for i in start..<end { slots[i] = nil }
		sessionManager.saveSessions()
	}

	private func deviceDragProvider(instance: DeviceInstance, device: Device) -> NSItemProvider {
		let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
		DragContext.shared.beginDrag(payload: payload)

		let provider = NSItemProvider()
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.deviceDragPayload.identifier,
			visibility: .all
		) { completion in
			completion(try? JSONEncoder().encode(payload), nil)
			return nil
		}
		return provider
	}

	@ViewBuilder
	private func devicePreviewView(device: Device, metrics: FaceRenderMetrics, slotSize: CGSize) -> some View {
		let scaledMetrics = FaceRenderMetrics(
			size: CGSize(width: metrics.size.width * canvasZoom, height: metrics.size.height * canvasZoom),
			vOffset: metrics.vOffset * canvasZoom
		)
		let scaledSlotSize = CGSize(width: slotSize.width * canvasZoom, height: slotSize.height * canvasZoom)

		ZStack(alignment: .topLeading) {
			if renderStyle == .representative {
				// Use vector representation
				DeviceView(device: device, metrics: scaledMetrics)
					.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
			} else {
#if os(macOS)
				if let data = device.imageData, let nsimg = NSImage(data: data) {
					Image(nsImage: nsimg)
						.resizable()
						.interpolation(.high)
						.antialiased(true)
						.aspectRatio(nsimg.size, contentMode: .fit)
						.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
				} else {
					DeviceView(device: device, metrics: scaledMetrics)
						.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
				}
#else
				DeviceView(device: device, metrics: scaledMetrics)
					.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
#endif
			}
		}
		.offset(y: scaledMetrics.vOffset)
		.frame(width: scaledSlotSize.width, height: scaledSlotSize.height, alignment: .topLeading)
		.clipped()
		.shadow(radius: 8, y: 2)
	}
	
	private struct RailH: View {
		var height: CGFloat = 3
		
		var body: some View {
			Rectangle()
				.fill(LinearGradient(
					colors: [
						Color.black.opacity(0.22),
						Color.black.opacity(0.06),
						Color.black.opacity(0.22)
					],
					startPoint: .top, endPoint: .bottom
				))
				.overlay(
					Rectangle()
						.stroke(Color.black.opacity(0.35), lineWidth: 0.5)
				)
				.frame(height: height)
				.overlay(RailScrewsH())
				.opacity(0.95)
				.help("Drag to move this module")
		}
	}
	
	private struct RailScrewsH: View {
		var body: some View {
			Circle()
				.fill(.secondary)
				.frame(width: 3, height: 3)
				.padding(.horizontal, 6)
		}
	}
}
