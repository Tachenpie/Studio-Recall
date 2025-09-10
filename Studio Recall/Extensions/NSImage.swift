//
//  NSImage.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//

import AppKit

extension NSImage {
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
