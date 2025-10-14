//
//  LabelPreset.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//

import Foundation
import SwiftUI

enum LabelPreset: String, CaseIterable, Identifiable {
    case plasticLabelMaker
	case maskingTapeSharpie
	case whiteOnBlack
	case blackOnWhite
	
    var id: String { rawValue }
	
	var displayName: String {
		switch self {
			case .plasticLabelMaker:  return "Plastic Label Maker"
			case .maskingTapeSharpie: return "Masking Tape Sharpie"
			case .whiteOnBlack:       return "White on Black"
			case .blackOnWhite:       return "Black on White"
		}
	}
	
	var icon: String {
		switch self {
			case .plasticLabelMaker:   return "▭"
			case .maskingTapeSharpie:  return "✎"
			case .whiteOnBlack:        return "⬛"
			case .blackOnWhite:        return "⬜"
		}
	}
}

struct UserLabelPreset: Identifiable, Codable, Equatable {
	var id = UUID()
	var name: String
	var style: LabelStyleSpec
}

enum LabelPresetStore {
	private static let key = "label.user.presets.v1"
	
	static func load() -> [UserLabelPreset] {
		guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
		return (try? JSONDecoder().decode([UserLabelPreset].self, from: data)) ?? []
	}
	
	static func save(_ presets: [UserLabelPreset]) {
		if let data = try? JSONEncoder().encode(presets) {
			UserDefaults.standard.set(data, forKey: key)
		}
	}
	
	static func add(name: String, style: LabelStyleSpec) {
		var list = load()
		list.insert(UserLabelPreset(name: name, style: style), at: 0) // newest first
		save(list)
	}
	
	static func delete(id: UUID) {
		var list = load()
		list.removeAll { $0.id == id }
		save(list)
	}

	static func update(id: UUID, style: LabelStyleSpec) {
		var list = load()
		if let idx = list.firstIndex(where: { $0.id == id }) {
			list[idx].style = style
			save(list)
		}
	}
}

extension LabelStyleSpec {
    static func preset(_ p: LabelPreset) -> LabelStyleSpec {
        var s = LabelStyleSpec()
        switch p {
        case .plasticLabelMaker:
            s.background = .init(Color(.sRGB, red: 0.10, green: 0.10, blue: 0.12, opacity: 1))
            s.textColor  = .init(.white)
            s.borderColor = .init(.black.opacity(0.6))
            s.borderWidth = 0.5
            s.cornerRadius = 2
            s.fontName = "DIN Alternate"
            s.fontSize = 12
            s.shadow = 0.5
        case .maskingTapeSharpie:
            s.background = .init(Color(red: 0.96, green: 0.92, blue: 0.78))
            s.textColor  = .init(.black)
            s.borderColor = .init(.black.opacity(0.15))
            s.borderWidth = 1
            s.cornerRadius = 3
            s.fontName = "MarkerFelt-Wide"
            s.fontSize = 13
            s.shadow = 0
        case .whiteOnBlack:
            s.background = .init(.black)
            s.textColor  = .init(.white)
            s.borderColor = .init(.white.opacity(0.2))
            s.borderWidth = 1
            s.cornerRadius = 4
        case .blackOnWhite:
            s.background = .init(.white)
            s.textColor  = .init(.black)
            s.borderColor = .init(.black.opacity(0.2))
            s.borderWidth = 1
            s.cornerRadius = 4
        }
        return s
    }
}
