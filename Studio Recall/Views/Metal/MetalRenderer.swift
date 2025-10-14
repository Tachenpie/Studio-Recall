//
//  MetalRenderer.swift
//  Studio Recall
//
//  High-performance Metal renderer for session canvas
//

import Foundation
import Metal
import simd

/// Vertex structure matching shader
struct MetalVertex {
	var position: SIMD2<Float>
	var texCoord: SIMD2<Float>
}

/// Instance data for each device/rack quad
struct MetalInstanceData {
	var modelMatrix: simd_float4x4
	var texCoordRect: SIMD4<Float>  // x, y, width, height in atlas
	var alpha: Float
}

/// Uniform data for camera/projection
struct MetalUniforms {
	var projectionMatrix: simd_float4x4
	var viewMatrix: simd_float4x4
}

/// Manages Metal rendering pipeline and buffers
class MetalRenderer {
	private let device: MTLDevice
	private let commandQueue: MTLCommandQueue

	private var vertexBuffer: MTLBuffer?
	private var indexBuffer: MTLBuffer?
	private var instanceBuffer: MTLBuffer?
	private var uniformBuffer: MTLBuffer?

	private var pipelineState: MTLRenderPipelineState?
	private var depthStencilState: MTLDepthStencilState?
	private var samplerState: MTLSamplerState?

	private let maxInstances = 10000  // Maximum devices we can render at once

	init(device: MTLDevice) {
		self.device = device
		self.commandQueue = device.makeCommandQueue()!
		setupBuffers()
		setupPipeline()
		setupDepthStencil()
		setupSampler()
	}

	private func setupBuffers() {
		// Quad vertices (2 triangles)
		let vertices: [MetalVertex] = [
			MetalVertex(position: SIMD2<Float>(-0.5, -0.5), texCoord: SIMD2<Float>(0, 1)),  // Bottom-left
			MetalVertex(position: SIMD2<Float>(0.5, -0.5), texCoord: SIMD2<Float>(1, 1)),   // Bottom-right
			MetalVertex(position: SIMD2<Float>(0.5, 0.5), texCoord: SIMD2<Float>(1, 0)),    // Top-right
			MetalVertex(position: SIMD2<Float>(-0.5, 0.5), texCoord: SIMD2<Float>(0, 0))    // Top-left
		]

		vertexBuffer = device.makeBuffer(
			bytes: vertices,
			length: MemoryLayout<MetalVertex>.stride * vertices.count,
			options: .storageModeShared
		)

		// Indices for two triangles
		let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
		indexBuffer = device.makeBuffer(
			bytes: indices,
			length: MemoryLayout<UInt16>.stride * indices.count,
			options: .storageModeShared
		)

		// Instance buffer (updated each frame)
		let instanceSize = MemoryLayout<MetalInstanceData>.stride * maxInstances
		instanceBuffer = device.makeBuffer(length: instanceSize, options: .storageModeShared)

		// Uniform buffer
		let uniformSize = MemoryLayout<MetalUniforms>.stride
		uniformBuffer = device.makeBuffer(length: uniformSize, options: .storageModeShared)
	}

	private func setupPipeline() {
		guard let library = device.makeDefaultLibrary() else {
			print("❌ Failed to create shader library")
			return
		}

		let vertexFunction = library.makeFunction(name: "vertexShader")
		let fragmentFunction = library.makeFunction(name: "fragmentShader")

		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

		// Enable blending
		pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
		pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
		pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
		pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
		pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
		pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
		pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

		// Vertex descriptor
		let vertexDescriptor = MTLVertexDescriptor()
		vertexDescriptor.attributes[0].format = .float2
		vertexDescriptor.attributes[0].offset = 0
		vertexDescriptor.attributes[0].bufferIndex = 0

		vertexDescriptor.attributes[1].format = .float2
		vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
		vertexDescriptor.attributes[1].bufferIndex = 0

		vertexDescriptor.layouts[0].stride = MemoryLayout<MetalVertex>.stride
		vertexDescriptor.layouts[0].stepRate = 1
		vertexDescriptor.layouts[0].stepFunction = .perVertex

		pipelineDescriptor.vertexDescriptor = vertexDescriptor

		do {
			pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
		} catch {
			print("❌ Failed to create pipeline state: \(error)")
		}
	}

	private func setupDepthStencil() {
		let depthDescriptor = MTLDepthStencilDescriptor()
		depthDescriptor.depthCompareFunction = .less
		depthDescriptor.isDepthWriteEnabled = true
		depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
	}

	private func setupSampler() {
		let samplerDescriptor = MTLSamplerDescriptor()
		samplerDescriptor.minFilter = .linear
		samplerDescriptor.magFilter = .linear
		samplerDescriptor.mipFilter = .linear
		samplerDescriptor.maxAnisotropy = 16
		samplerDescriptor.sAddressMode = .clampToEdge
		samplerDescriptor.tAddressMode = .clampToEdge
		samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
	}

	/// Render instances with the given data
	func render(
		encoder: MTLRenderCommandEncoder,
		instances: [MetalInstanceData],
		uniforms: MetalUniforms,
		atlasTexture: MTLTexture?
	) {
		guard let pipelineState = pipelineState,
			  let vertexBuffer = vertexBuffer,
			  let indexBuffer = indexBuffer,
			  let instanceBuffer = instanceBuffer,
			  let uniformBuffer = uniformBuffer,
			  let depthStencilState = depthStencilState,
			  let samplerState = samplerState,
			  !instances.isEmpty else {
			return
		}

		// Update uniform buffer
		var mutableUniforms = uniforms
		uniformBuffer.contents().copyMemory(
			from: &mutableUniforms,
			byteCount: MemoryLayout<MetalUniforms>.stride
		)

		// Update instance buffer
		let instanceCount = min(instances.count, maxInstances)
		instanceBuffer.contents().copyMemory(
			from: instances,
			byteCount: MemoryLayout<MetalInstanceData>.stride * instanceCount
		)

		// Set pipeline state
		encoder.setRenderPipelineState(pipelineState)
		encoder.setDepthStencilState(depthStencilState)

		// Bind buffers
		encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
		encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
		encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)

		// Bind texture and sampler
		if let texture = atlasTexture {
			encoder.setFragmentTexture(texture, index: 0)
			encoder.setFragmentSamplerState(samplerState, index: 0)
		}

		// Draw instanced
		encoder.drawIndexedPrimitives(
			type: .triangle,
			indexCount: 6,
			indexType: .uint16,
			indexBuffer: indexBuffer,
			indexBufferOffset: 0,
			instanceCount: instanceCount
		)
	}

	/// Create orthographic projection matrix
	static func makeOrthoMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
		let rl = right - left
		let tb = top - bottom
		let fn = far - near

		return simd_float4x4(
			SIMD4<Float>(2.0 / rl, 0, 0, 0),
			SIMD4<Float>(0, 2.0 / tb, 0, 0),
			SIMD4<Float>(0, 0, -2.0 / fn, 0),
			SIMD4<Float>(-(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn, 1)
		)
	}

	/// Create translation matrix
	static func makeTranslationMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
		return simd_float4x4(
			SIMD4<Float>(1, 0, 0, 0),
			SIMD4<Float>(0, 1, 0, 0),
			SIMD4<Float>(0, 0, 1, 0),
			SIMD4<Float>(x, y, z, 1)
		)
	}

	/// Create scale matrix
	static func makeScaleMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
		return simd_float4x4(
			SIMD4<Float>(x, 0, 0, 0),
			SIMD4<Float>(0, y, 0, 0),
			SIMD4<Float>(0, 0, z, 0),
			SIMD4<Float>(0, 0, 0, 1)
		)
	}
}
