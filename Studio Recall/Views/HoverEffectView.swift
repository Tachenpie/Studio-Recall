//
//  HoverEffectView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import SwiftUI

struct HoverEffectView: View {
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(Color.gray)
			.opacity(hovered ? 0.15 : 0)
            .cornerRadius(6)
		#if os(macOS)
			.onHover { inside in
                hovered = inside
            }
		#endif
    }
}

struct HoverHighlight: View {
    @State private var hovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray)
			.opacity(hovered ? 0.15 : 0)
		#if os(macOS)
			.onHover { inside in
                hovered = inside
            }
		#endif
    }
}

// MARK: - Reusable hover highlight (modifier)
struct HoverHighlightModifier: ViewModifier {
	@State private var hovered = false
	var cornerRadius: CGFloat = 8
	var strokeWidth: CGFloat = 1
	var fillOpacity: Double = 0.10
	var useMaterial: Bool = false   // set true if you want material look
	
	func body(content: Content) -> some View {
		content
			.contentShape(Rectangle())
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(
						useMaterial
						? AnyShapeStyle(.ultraThinMaterial) // constant style
						: AnyShapeStyle(Color.accentColor)   // constant Color
					)
					.opacity(hovered ? fillOpacity : 0)       // animate opacity only
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius)
					.stroke(hovered ? Color.accentColor : .clear, lineWidth: strokeWidth)
			)
		#if os(macOS)
			.onHover { inside in
				withAnimation(.easeInOut(duration: 0.12)) { hovered = inside }
			}
		#endif
	}
}

struct HoverTileModifier: ViewModifier {
	@State private var hovered = false
	var cornerRadius: CGFloat = 8
	var baseOpacity: Double = 0.08
	
	func body(content: Content) -> some View {
		content
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color.accentColor)     // single concrete style
					.opacity(hovered ? baseOpacity : 0) // animate opacity only
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius)
					.stroke(hovered ? Color.accentColor : .secondary.opacity(0.25),
							lineWidth: hovered ? 1.5 : 1)
			)
		// HoverEffectView.swift — inside HoverTileModifier.body
#if os(macOS)
			.onHover { inside in
				withAnimation(.easeInOut(duration: 0.12)) { hovered = inside }
			}
#endif

	}
}

extension View {
	func hoverTile(cornerRadius: CGFloat = 8, baseOpacity: Double = 0.08) -> some View {
		modifier(HoverTileModifier(cornerRadius: cornerRadius, baseOpacity: baseOpacity))
	}
}

extension View {
	func hoverHighlight(
		cornerRadius: CGFloat = 8,
		strokeWidth: CGFloat = 1,
		fillOpacity: Double = 0.10,
		useMaterial: Bool = false
	) -> some View {
		modifier(HoverHighlightModifier(
			cornerRadius: cornerRadius,
			strokeWidth: strokeWidth,
			fillOpacity: fillOpacity,
			useMaterial: useMaterial
		))
	}
}
