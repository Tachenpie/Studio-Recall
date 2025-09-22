//
//  Device.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Device Type Enum
enum DeviceType: String, Codable, CaseIterable {
    case rack
    case series500
    
    var displayName: String {
        switch self {
        case .rack:
            return "Rack Gear"
        case .series500:
            return "500 Series Module"
        }
    }
}

enum RackWidth: Int, Codable, CaseIterable, Identifiable {
	case full  = 6
	case half  = 3
	case third = 2
	
	var id: Int { rawValue }
	var label: String {
		switch self {
			case .full: return "Full (19\")"
			case .half: return "Half (½)"
			case .third: return "Third (⅓)"
		}
	}
}

// MARK: - Device Model
struct Device: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String

    var type: DeviceType        // Rack vs 500
    
    var controls: [Control] = []
    
    // Physical sizing
    var rackUnits: Int? = 1       // e.g., 1U, 2U
	var rackWidth: RackWidth = .full
    var slotWidth: Int? = nil       // e.g., 1 slot, 2 slots

	var wingWidthInches: CGFloat = DeviceMetrics.wingWidth
    
    var isFiller: Bool = false  // true = blank panel
    
    var imageData: Data? = nil  // expects a PNG in asset catalog or file system
    
    var categories: [String] = []   // User-defined categories
    
    // Equatable
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
}

final class EditableDevice: ObservableObject, Identifiable {
    @Published var device: Device
    let id = UUID()
    
    init(device: Device) {
        self.device = device
    }
}

enum RackGrid {
	static let columnsPerRow = 6
}

struct DeviceMetrics {
	static let oneUInches: CGFloat = 1.75		//Inches
	static let rackTotalWidth: CGFloat = 19.0	// Inches
	static let wingWidth: CGFloat = 0.75		// Inches
	
    /// Scale in pixels per inch (ppi)
    static func rackSize(units: Int, scale: CGFloat) -> CGSize {
        CGSize(
            width: rackTotalWidth * scale,                   // standard rack width in inches
            height: CGFloat(units) * oneUInches * scale // 1U = 1.75 inches
        )
    }

    static func moduleSize(units: Int, scale: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(units) * oneUInches * scale,                   // module width in inches
            height: 3 * oneUInches * scale              // 3U tall (like Eurorack)
        )
    }
	
	static func slotSize(scale ppi: CGFloat) -> CGSize {
		// A *single column* “slot” width; height is 1U (your current per-U size)
		let oneU = rackSize(units: 1, scale: ppi)              // you already have this
		let columnW = oneU.width / CGFloat(RackGrid.columnsPerRow)
		return CGSize(width: columnW, height: oneU.height)     // 1 column × 1U
	}
	
	static func deviceFrame(rackWidth: RackWidth,
							rackUnits: Int,
							scale ppi: CGFloat,
							rowSpacing: CGFloat) -> CGSize
	{
		let base = slotSize(scale: ppi) // 1 column × 1U (no gaps)
		let cols = CGFloat(rackWidth.rawValue)
		let rows = CGFloat(max(1, rackUnits))
		
		let width  = base.width * cols
		let height = base.height * rows + rowSpacing * max(0, rows - 1)
		
		return CGSize(width: width, height: height)
	}
}

// MARK: - Physical widths (inches) and conversions
extension DeviceMetrics {
	/// Total width (inches) occupied by a span of a given rack width.
	/// Full spans the entire 19" rack width; half spans 9.5"; third spans 19/3.
	static func spanInches(for rackWidth: RackWidth) -> CGFloat {
		switch rackWidth {
			case .full:    return 19.0
			case .half:    return 19.0 / 2.0           // 9.5"
			case .third:   return 19.0 / 3.0           // ≈6.3333"
		}
	}
	
	/// Faceplate **body** widths (inches) for devices that ship without ears.
	/// (Full-width gear art usually already includes ears.)
	static func bodyInches(for rackWidth: RackWidth) -> CGFloat {
		switch rackWidth {
			case .full:  return 19.0            // treat as full already
			case .half:  return 8.5             // per your studio gear
			case .third: return 5.5
		}
	}
	
	/// Convert inches → points using your scale (ppi).
	static func points(fromInches inches: CGFloat, ppi: CGFloat) -> CGFloat {
		inches * ppi
	}
	
	/// Target face size (points) for a rack device: body width × U height.
	static func rackFaceSizePoints(rackWidth: RackWidth, rackUnits: Int, ppi: CGFloat) -> CGSize {
		let wIn = bodyInches(for: rackWidth)         // 19, 8.5, 5.5
		let hIn = 1.75 * CGFloat(max(1, rackUnits))  // U → inches
		return CGSize(width: points(fromInches: wIn, ppi: ppi),
					  height: points(fromInches: hIn, ppi: ppi))
	}
	
	/// Resample an uploaded faceplate so its WIDTH is exact (19/8.5/5.5 in),
	/// and HEIGHT is scaled proportionally to preserve aspect.
	static func normalizedRackFaceplateKeepAspect(
		data: Data,
		rackWidth: RackWidth,
		ppi: CGFloat
	) -> Data? {
		let targetW = points(fromInches: bodyInches(for: rackWidth), ppi: ppi)
		
#if os(macOS)
		guard let src = NSImage(data: data), src.size.width > 0 else { return nil }
		let scale = targetW / src.size.width
		let target = CGSize(width: targetW, height: src.size.height * scale)
		
		let out = NSImage(size: target)
		out.lockFocus()
		NSColor.clear.set()
		NSBezierPath(rect: CGRect(origin: .zero, size: target)).fill()
		src.draw(in: CGRect(origin: .zero, size: target),
				 from: .zero, operation: .sourceOver, fraction: 1.0)
		out.unlockFocus()
		return out.pngData()
#else
		guard let src = UIImage(data: data), src.size.width > 0 else { return nil }
		let scale = targetW / src.size.width
		let target = CGSize(width: targetW, height: src.size.height * scale)
		
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let renderer = UIGraphicsImageRenderer(size: target, format: format)
		let img = renderer.image { _ in
			UIColor.clear.setFill()
			UIBezierPath(rect: CGRect(origin: .zero, size: target)).fill()
			src.draw(in: CGRect(origin: .zero, size: target))
		}
		return img.pngData()
#endif
	}
	
	/// Compute the rendered face size and vertical centering offset when the face is
	/// drawn with width=faceWidthPts and aspect preserved; height never exceeds slotHeightPts.
	static func renderedFaceSize(
		faceWidthPts: CGFloat,
		slotHeightPts: CGFloat,
		imageData: Data?
	) -> (size: CGSize, vOffset: CGFloat) {
#if os(macOS)
		if let data = imageData, let nsimg = NSImage(data: data), nsimg.size.width > 0 {
			let h = min(slotHeightPts, faceWidthPts * (nsimg.size.height / nsimg.size.width))
			let v = max(0, (slotHeightPts - h) / 2)
			return (CGSize(width: faceWidthPts, height: h), v)
		}
#endif
		// Fallback: fill slot height (e.g., no custom image)
		return (CGSize(width: faceWidthPts, height: slotHeightPts), 0)
	}
}

// MARK: - Shared prelayout struct
/// Precomputed, inch-accurate layout for a single device span on a row.
/// Used by RackChassisView (producer) and RackChassisSlotView (consumer).
struct SlotPrelayout {
	let faceWidthPts: CGFloat      // body-only width in points (19, 8.5, 5.5 inches * ppi)
	let totalWidthPts: CGFloat     // span: body + external wings + half-seam rails
	let leftWingPts: CGFloat
	let rightWingPts: CGFloat
	let leftRailPts: CGFloat
	let rightRailPts: CGFloat
	let heightPts: CGFloat
	let externalLeft: Bool
	let externalRight: Bool
}

/// Render-time metrics for a device face: width-fit, aspect-preserving.
struct FaceRenderMetrics {
	let size: CGSize     // rendered face size (width = faceWidthPts; height <= slotHeightPts)
	let vOffset: CGFloat // vertical centering offset inside the slot
}

extension DeviceMetrics {
	/// Compute rendered face size and vertical offset. Width is fixed to `faceWidthPts`,
	/// height preserves the image’s aspect and is clamped to `slotHeightPts`.
	static func faceRenderMetrics(
		faceWidthPts: CGFloat,
		slotHeightPts: CGFloat,
		imageData: Data?
	) -> FaceRenderMetrics {
#if os(macOS)
		if let data = imageData, let nsimg = NSImage(data: data), nsimg.size.width > 0 {
			let h = min(slotHeightPts, faceWidthPts * (nsimg.size.height / nsimg.size.width))
			let v = max(0, (slotHeightPts - h) / 2)
			return FaceRenderMetrics(size: CGSize(width: faceWidthPts, height: h), vOffset: v)
		}
#endif
		return FaceRenderMetrics(size: CGSize(width: faceWidthPts, height: slotHeightPts), vOffset: 0)
	}
}
