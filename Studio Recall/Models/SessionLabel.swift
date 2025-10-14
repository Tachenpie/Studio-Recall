//
//  LabelAnchor.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

enum LabelAnchor: Codable, Equatable {
    case session
    case rack(UUID)                // rack.id
	case pedalboard(UUID)          // pedalboard.id
    case deviceInstance(UUID)      // DeviceInstance.id
}

struct LabelStyleSpec: Codable, Equatable {
    var textColor: ColorData = .init(.black)
    var background: ColorData = .init(.white.opacity(0.9))
    var borderColor: ColorData = .init(.black.opacity(0.25))
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 4
    var fontName: String = ".SFNSRounded"   // fallback to system if missing
    var fontSize: CGFloat = 12
    var paddingH: CGFloat = 8
    var paddingV: CGFloat = 4
    var shadow: CGFloat = 0
    var opacity: Double = 1
    var scalesWithZoom: Bool = true         // turn OFF if you want constant screen size
}

struct SessionLabel: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var anchor: LabelAnchor = .session
    /// Position relative to the *parent's local origin* in points.
    var offset: CGPoint = .zero
    var text: String = "Label"
    var style: LabelStyleSpec = .init()
    var isLocked: Bool = false
    var isNewlyCreated: Bool = false  // Transient flag for glow effect
    var linkedPresetId: UUID? = nil   // Links label to a user preset for updates

    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, anchor, offset, text, style, isLocked, isNewlyCreated, linkedPresetId
    }

    init(id: UUID = UUID(), anchor: LabelAnchor = .session, offset: CGPoint = .zero,
         text: String = "Label", style: LabelStyleSpec = .init(), isLocked: Bool = false,
         isNewlyCreated: Bool = false, linkedPresetId: UUID? = nil) {
        self.id = id
        self.anchor = anchor
        self.offset = offset
        self.text = text
        self.style = style
        self.isLocked = isLocked
        self.isNewlyCreated = isNewlyCreated
        self.linkedPresetId = linkedPresetId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        anchor = try container.decode(LabelAnchor.self, forKey: .anchor)
        offset = try container.decode(CGPoint.self, forKey: .offset)
        text = try container.decode(String.self, forKey: .text)
        style = try container.decode(LabelStyleSpec.self, forKey: .style)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        // New fields with backward compatibility
        isNewlyCreated = try container.decodeIfPresent(Bool.self, forKey: .isNewlyCreated) ?? false
        linkedPresetId = try container.decodeIfPresent(UUID.self, forKey: .linkedPresetId)
    }
}

// Codable helper for Color
struct ColorData: Codable, Equatable {
    var r: CGFloat; var g: CGFloat; var b: CGFloat; var a: CGFloat
    init(_ c: Color) {
        let ui = NSColor(cgColor: c.resolve(in: .init()).cgColor) ?? .black
        r = ui.redComponent; g = ui.greenComponent; b = ui.blueComponent; a = ui.alphaComponent
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - Label default style
enum LabelStyleDefaults {
	private static let key = "LabelDefaultStyle"
	
	static func load() -> LabelStyleSpec {
		guard let data = UserDefaults.standard.data(forKey: key),
			  let spec = try? JSONDecoder().decode(LabelStyleSpec.self, from: data) else {
			return .init()
		}
		return spec
	}
	
	static func save(_ style: LabelStyleSpec) {
		if let data = try? JSONEncoder().encode(style) {
			UserDefaults.standard.set(data, forKey: key)
		}
	}
	
	static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}

extension SessionLabel {
	/// Convenience factory that applies the saved default style.
	static func new(anchor: LabelAnchor, text: String = "Label", at offset: CGPoint = .zero) -> SessionLabel {
		var l = SessionLabel(anchor: anchor, offset: offset, text: text)
		l.style = LabelStyleDefaults.load()
		return l
	}
}
