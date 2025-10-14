//
//  MetalTextureAtlas.swift
//  Studio Recall
//
//  Texture atlas for efficiently rendering many device faceplates
//

import Foundation
import Metal
import AppKit

/// Manages a texture atlas containing all device faceplate images
class MetalTextureAtlas {
	private let device: MTLDevice
	private let library: DeviceLibrary

	private(set) var atlasTexture: MTLTexture?
	private(set) var textureCoords: [UUID: CGRect] = [:]  // Device ID -> normalized coords in atlas

	// Atlas configuration
	private let maxAtlasSize: Int = 8192
	private let padding: Int = 4

	init(device: MTLDevice, library: DeviceLibrary) {
		self.device = device
		self.library = library
		Task { @MainActor in
			buildAtlas()
		}
	}

	/// Builds the texture atlas from all device images
	@MainActor
	private func buildAtlas() {
		print("🎨 Building Metal texture atlas...")

		// Collect all device images
		var deviceImages: [(UUID, NSImage)] = []
		for device in library.devices {
			if let data = device.imageData, let image = NSImage(data: data) {
				deviceImages.append((device.id, image))
			}
		}

		guard !deviceImages.isEmpty else {
			print("⚠️ No device images to pack into atlas")
			return
		}

		// Sort by height (descending) for better packing
		deviceImages.sort { $0.1.size.height > $1.1.size.height }

		// Pack images using simple row packing algorithm
		var currentX = padding
		var currentY = padding
		var rowHeight = 0
		var atlasWidth = 0
		var atlasHeight = 0

		var placements: [(UUID, CGRect, NSImage)] = []

		for (deviceID, image) in deviceImages {
			let imgWidth = Int(image.size.width)
			let imgHeight = Int(image.size.height)

			// Check if we need to start a new row
			if currentX + imgWidth + padding > maxAtlasSize {
				currentX = padding
				currentY += rowHeight + padding
				rowHeight = 0
			}

			// Place image
			let rect = CGRect(x: currentX, y: currentY, width: imgWidth, height: imgHeight)
			placements.append((deviceID, rect, image))

			// Update tracking
			currentX += imgWidth + padding
			rowHeight = max(rowHeight, imgHeight)
			atlasWidth = max(atlasWidth, currentX)
			atlasHeight = max(atlasHeight, currentY + imgHeight + padding)
		}

		// Round up to power of 2 for better GPU performance
		atlasWidth = nextPowerOfTwo(atlasWidth)
		atlasHeight = nextPowerOfTwo(atlasHeight)

		print("📐 Atlas size: \(atlasWidth)×\(atlasHeight) with \(placements.count) images")

		// Create texture
		let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .rgba8Unorm,
			width: atlasWidth,
			height: atlasHeight,
			mipmapped: true
		)
		textureDescriptor.usage = [.shaderRead, .renderTarget]
		textureDescriptor.storageMode = .shared

		guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
			print("❌ Failed to create atlas texture")
			return
		}

		self.atlasTexture = texture

		// Render images into atlas
		renderImagesToAtlas(placements: placements, atlasWidth: atlasWidth, atlasHeight: atlasHeight)

		// Store normalized texture coordinates
		for (deviceID, rect, _) in placements {
			let normalizedRect = CGRect(
				x: rect.origin.x / CGFloat(atlasWidth),
				y: rect.origin.y / CGFloat(atlasHeight),
				width: rect.size.width / CGFloat(atlasWidth),
				height: rect.size.height / CGFloat(atlasHeight)
			)
			textureCoords[deviceID] = normalizedRect
		}

		print("✅ Atlas built successfully")
	}

	private func renderImagesToAtlas(placements: [(UUID, CGRect, NSImage)], atlasWidth: Int, atlasHeight: Int) {
		guard let texture = atlasTexture else { return }

		// Create bitmap context
		let bytesPerPixel = 4
		let bytesPerRow = bytesPerPixel * atlasWidth
		let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

		guard let context = CGContext(
			data: nil,
			width: atlasWidth,
			height: atlasHeight,
			bitsPerComponent: 8,
			bytesPerRow: bytesPerRow,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: bitmapInfo
		) else {
			print("❌ Failed to create bitmap context")
			return
		}

		// Clear to transparent
		context.clear(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

		// Draw each image
		for (_, rect, image) in placements {
			// Don't flip Y - we'll handle it in the shader
			if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
				context.draw(cgImage, in: CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height))
			}
		}

		// Copy to texture
		if let data = context.data {
			let region = MTLRegionMake2D(0, 0, atlasWidth, atlasHeight)
			texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
		}

		// Generate mipmaps
		if let commandQueue = device.makeCommandQueue(),
		   let commandBuffer = commandQueue.makeCommandBuffer(),
		   let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
			blitEncoder.generateMipmaps(for: texture)
			blitEncoder.endEncoding()
			commandBuffer.commit()
			commandBuffer.waitUntilCompleted()
		}
	}

	private func nextPowerOfTwo(_ n: Int) -> Int {
		var power = 1
		while power < n {
			power *= 2
		}
		return power
	}

	/// Get texture coordinates for a device
	func getTextureCoords(for deviceID: UUID) -> CGRect? {
		return textureCoords[deviceID]
	}
}
