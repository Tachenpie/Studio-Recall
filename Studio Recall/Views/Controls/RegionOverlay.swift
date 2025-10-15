//
//  RegionOverlay.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RegionOverlay: View {
	@Binding var rect: CGRect          // normalized (0…1)
	let canvasSize: CGSize
	let gridStep: CGFloat
	let minRegion: CGFloat
	let shape: ImageRegionShape
	let zoom: CGFloat

	let controlType: ControlType
	let regionIndex: Int
	let regions: [ImageRegion]
	let maskParams: MaskParameters?    // For live preview

	@Environment(\.isPanMode) private var isPanMode
	
	// Animation state for marching ants
	@State private var dashPhase: CGFloat = 0
	
	var body: some View {
		// Canvas-pixel geometry
		let z = max(zoom, 0.0001)
		let x = rect.origin.x * canvasSize.width
		let y = rect.origin.y * canvasSize.height
		let w = max(minRegion, rect.size.width)  * canvasSize.width
		let h = max(minRegion, rect.size.height) * canvasSize.height
		
		// Screen-constant metrics
		let minSide = max(1, min(w, h))
		let hair: CGFloat = 1.0 / z           // ≈ 1pt on screen
		let dashUnit: CGFloat = 6.0 / z       // alternating black/white segments
		let dash: [CGFloat] = [dashUnit, dashUnit]
		let handleSize: CGFloat = (minSide < 24 ? 4.0 : (minSide < 48 ? 6.0 : 8.0)) / z
		let showEdgeHandles = minSide >= 44   // hide edge handles when very small
		
		ZStack(alignment: .topLeading) {
			ZStack(alignment: .topLeading) {
				// 1) Region-local container positioned at (x,y), sized (w,h)
				let pair = concentricPairIndices(regions)
				if isConcentricOuterRegion {
					let outerLocal = CGRect(x: 0, y: 0, width: w, height: h)
					let innerNorm = regions[pair!.inner].rect.denormalized(to: canvasSize)
					let innerLocal = CGRect(
						x: (innerNorm.minX - x),
						y: (innerNorm.minY - y),
						width: innerNorm.width,
						height: innerNorm.height
					)
					let donut = DonutShape(
						outerRect: outerLocal,
						innerRect: innerLocal
					)

					donut
						.stroke(.black, style: StrokeStyle(lineWidth: hair, dash: dash))
						.overlay(donut.stroke(.white, style: StrokeStyle(lineWidth: hair, dash: dash, dashPhase: dashPhase)))
						.contentShape(donut) // ✅ hit test only in the ring
						.zIndex(1)
				} else {
					// Inner or non-concentric case
					let localRect = CGRect(x: 0, y: 0, width: w, height: h)
					let clipShape = RegionClipShape(
						shape: shape,
						shapeInstances: regions[regionIndex].shapeInstances.isEmpty ? nil : regions[regionIndex].shapeInstances,
						maskParams: maskParams
					)
					let outline = clipShape.path(in: localRect)
					
					Path(outline)
						.stroke(.black, style: StrokeStyle(lineWidth: hair, dash: dash))
						.overlay(
							Path(outline)
								.stroke(.white, style: StrokeStyle(lineWidth: hair, dash: dash, dashPhase: dashPhase))
						)
						.contentShape(outline)
						.zIndex(1)
				}

				// 1c) Handles — tiny white squares with black hairline stroke
				Group {
					// corners
					Rectangle().fill(.white)
						.frame(width: handleSize, height: handleSize)
						.overlay(Rectangle().stroke(.black, lineWidth: hair))
						.position(x: handleSize/2, y: handleSize/2) // TL
						.allowsHitTesting(false)

					Rectangle().fill(.white)
						.frame(width: handleSize, height: handleSize)
						.overlay(Rectangle().stroke(.black, lineWidth: hair))
						.position(x: w - handleSize/2, y: handleSize/2) // TR
						.allowsHitTesting(false)

					Rectangle().fill(.white)
						.frame(width: handleSize, height: handleSize)
						.overlay(Rectangle().stroke(.black, lineWidth: hair))
						.position(x: handleSize/2, y: h - handleSize/2) // BL
						.allowsHitTesting(false)

					Rectangle().fill(.white)
						.frame(width: handleSize, height: handleSize)
						.overlay(Rectangle().stroke(.black, lineWidth: hair))
						.position(x: w - handleSize/2, y: h - handleSize/2) // BR
						.allowsHitTesting(false)
				}

				if showEdgeHandles {
					Group {
						Rectangle().fill(.white)
							.frame(width: handleSize, height: handleSize)
							.overlay(Rectangle().stroke(.black, lineWidth: hair))
							.position(x: w/2, y: handleSize/2) // top
							.allowsHitTesting(false)

						Rectangle().fill(.white)
							.frame(width: handleSize, height: handleSize)
							.overlay(Rectangle().stroke(.black, lineWidth: hair))
							.position(x: w/2, y: h - handleSize/2) // bottom
							.allowsHitTesting(false)

						Rectangle().fill(.white)
							.frame(width: handleSize, height: handleSize)
							.overlay(Rectangle().stroke(.black, lineWidth: hair))
							.position(x: handleSize/2, y: h/2) // left
							.allowsHitTesting(false)

						Rectangle().fill(.white)
							.frame(width: handleSize, height: handleSize)
							.overlay(Rectangle().stroke(.black, lineWidth: hair))
							.position(x: w - handleSize/2, y: h/2) // right
							.allowsHitTesting(false)
					}
				}
			}
			.frame(width: w, height: h, alignment: .topLeading)
			.position(x: x + w/2, y: y + h/2)
		}
		.frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
		.zIndex(10)
		.allowsHitTesting(false)
		.onAppear {
			// Start marching ants animation
			let z = max(zoom, 0.0001)
			let dashUnit: CGFloat = 6.0 / z
			withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
				dashPhase = dashUnit * 2 // Full cycle of the dash pattern
			}
		}
	}
	
	// MARK: - Helpers
	
//	private var effectiveStep: CGFloat { max(0.001, gridStep / max(zoom, 0.0001)) }
	private var effectiveStep: CGFloat { max(0.001, gridStep * (1 / zoom)) }

	
	private func rectToPixels(_ r: CGRect) -> CGRect {
		CGRect(x: r.origin.x * canvasSize.width,
			   y: r.origin.y * canvasSize.height,
			   width: r.size.width * canvasSize.width,
			   height: r.size.height * canvasSize.height)
	}
	
	private func snap(_ v: CGFloat) -> CGFloat {
		(v.clamped(to: 0...1) / effectiveStep).rounded() * effectiveStep
	}
	
	private func pathFor(shape: ImageRegionShape, in rect: CGRect) -> Path {
		// Use RegionClipShape for all shapes to ensure consistency
		let instances = regions[regionIndex].shapeInstances.isEmpty ? nil : regions[regionIndex].shapeInstances
		return RegionClipShape(shape: shape, shapeInstances: instances, maskParams: maskParams).path(in: rect)
	}
	
	private var isConcentricOuterRegion: Bool {
		let pair = concentricPairIndices(regions)
		return (controlType == .concentricKnob && pair?.outer == regionIndex)
	}
	
	private var innerRect: CGRect? {
		guard isConcentricOuterRegion else { return nil }
		return regions[1].rect.denormalized(to: canvasSize)
	}
	
	// Pick outer/inner by area so order in the array can’t break us.
	private func concentricPairIndices(_ regions: [ImageRegion]) -> (outer: Int, inner: Int)? {
		guard regions.count >= 2 else { return nil }
		let areas = regions.enumerated().map { (i, r) in (i, r.rect.width * r.rect.height) }
		let outer = areas.max(by: { $0.1 < $1.1 })!.0
		let inner = areas.min(by: { $0.1 < $1.1 })!.0
		return (outer, inner)
	}
	
	// Convert the inner rect into the local coords of the outer patch (used by the mask).
	private func innerRectInOuterLocal(outer: CGRect, inner: CGRect, regionSize: CGSize) -> CGRect {
		// 'outer' & 'inner' are normalized (0…1) rects in canvas space.
		let ox = outer.minX, oy = outer.minY
		let ow = max(outer.width,  .leastNonzeroMagnitude)
		let oh = max(outer.height, .leastNonzeroMagnitude)
		return CGRect(
			x: (inner.minX - ox) / ow * regionSize.width,
			y: (inner.minY - oy) / oh * regionSize.height,
			width:  inner.width  / ow * regionSize.width,
			height: inner.height / oh * regionSize.height
		)
	}
}

extension CGRect {
	func denormalized(to canvasSize: CGSize) -> CGRect {
		CGRect(
			x: origin.x * canvasSize.width,
			y: origin.y * canvasSize.height,
			width: size.width * canvasSize.width,
			height: size.height * canvasSize.height
		)
	}
}
