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
    /// Position relative to the *parent’s local origin* in points.
    var offset: CGPoint = .zero
    var text: String = "Label"
    var style: LabelStyleSpec = .init()
    var isLocked: Bool = false
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
