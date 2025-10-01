//
//  NSImage.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//

import AppKit
import ImageIO

extension NSImage {
	/// Returns the pixel dimensions of the image (backing CGImage).
	var pixelSize: CGSize {
		if let cg = self.cgImage(forProposedRect: nil, context: nil, hints: nil) {
			return CGSize(width: cg.width, height: cg.height)
		}
		// Fallback: use points * scale
		let rep = self.representations.first
		let w = rep?.pixelsWide ?? Int(self.size.width)
		let h = rep?.pixelsHigh ?? Int(self.size.height)
		return CGSize(width: w, height: h)
	}
	
    /// Returns a resized copy of this NSImage, constrained to a max width/height
    func resized(maxDimension: CGFloat) -> NSImage? {
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    /// Returns PNG data for this NSImage
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }
	
	// MARK: - Crop helper for faceplate patches
	func cropped(to rect: CGRect, in renderedSize: CGSize? = nil) -> NSImage? {
		// Render self to a CGImage at 1x
		guard let tiff = self.tiffRepresentation,
			  let srcRep = NSBitmapImageRep(data: tiff),
			  let cg = srcRep.cgImage else { return nil }
		
		// If the image is being shown scaled to 'renderedSize' in the UI,
		// convert the view-space rect back into source-image space.
		let scaleX = CGFloat(cg.width)  / (renderedSize?.width  ?? self.size.width)
		let scaleY = CGFloat(cg.height) / (renderedSize?.height ?? self.size.height)
		
		let srcRect = CGRect(
			x: rect.origin.x * scaleX,
			y: (renderedSize != nil ? (renderedSize!.height - rect.maxY) : (self.size.height - rect.maxY)) * scaleY, // flip Y
			width: rect.width * scaleX,
			height: rect.height * scaleY
		)
		
		guard let cropped = cg.cropping(to: srcRect.integral) else { return nil }
		let out = NSImage(size: NSSize(width: cropped.width, height: cropped.height))
		out.lockFocus()
		NSGraphicsContext.current?.cgContext.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
		out.unlockFocus()
		return out
	}

}

private final class LODCache {
	static let shared = NSCache<NSString, NSImage>()
}

extension NSImage {
	/// Create or fetch a downsampled variant suitable for zoomed-out rendering.
	/// Pass a stable cacheKey (e.g. device.id + imageData.count) to avoid pointer reuse collisions.
	func lodImage(maxPixel: CGFloat, cacheKey: String? = nil) -> NSImage? {
		// Prefer a stable key; fall back to the (unsafe) pointer key for legacy call sites.
		let baseKey: String
		if let cacheKey { baseKey = cacheKey }
		else { baseKey = String(format: "ptr:%p", unsafeBitCast(self, to: Int.self)) }
		let key = "\(baseKey)-px:\(Int(maxPixel.rounded()))" as NSString
		
		if let cached = LODCache.shared.object(forKey: key) { return cached }
		
		if let tiff = self.tiffRepresentation,
		   let src  = CGImageSourceCreateWithData(tiff as CFData, nil) {
			let options: [CFString: Any] = [
				kCGImageSourceCreateThumbnailFromImageAlways: true,
				kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded()),
				kCGImageSourceCreateThumbnailWithTransform: true
			]
			if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
				// Give SwiftUI a real intrinsic size so aspectRatio is stable
				let pxSize = NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
				let img = NSImage(cgImage: cg, size: pxSize)
				LODCache.shared.setObject(img, forKey: key)
				return img
			}
		}
		
		// (fallback path unchanged)
		let ratio = max(size.width, size.height) == 0 ? 1 : (maxPixel / max(size.width, size.height))
		let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
		let rep = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
			isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		)
		rep?.size = newSize
		
		guard let rep else { return nil }
		NSGraphicsContext.saveGraphicsState()
		if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
			NSGraphicsContext.current = ctx
			ctx.imageInterpolation = .low
			self.draw(in: NSRect(origin: .zero, size: newSize),
					  from: .zero, operation: .copy, fraction: 1.0)
			NSGraphicsContext.restoreGraphicsState()
			let img = NSImage(size: newSize)
			img.addRepresentation(rep)
			LODCache.shared.setObject(img, forKey: key)
			return img
		}
		NSGraphicsContext.restoreGraphicsState()
		return nil
	}
}
