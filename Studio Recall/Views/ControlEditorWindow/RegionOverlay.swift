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
	
	@Environment(\.isPanMode) private var isPanMode
	
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
			// 1) Region-local container positioned at (x,y), sized (w,h)
			ZStack(alignment: .topLeading) {
				// 1a) “marching ants” outline (no fill), drawn in LOCAL space
				let outline = Path { p in
					p.addPath(pathFor(shape: shape, in: CGRect(x: 0, y: 0, width: w, height: h)))
				}
				outline
					.stroke(.black, style: StrokeStyle(lineWidth: hair, dash: dash, dashPhase: 0))
					.overlay(
						outline.stroke(.white, style: StrokeStyle(lineWidth: hair, dash: dash, dashPhase: dashUnit))
					)
					.allowsHitTesting(false)
				
				// 1b) SINGLE hit surface (visual overlay is non-interactive)
				Rectangle()
					.fill(.clear)
					.frame(width: w, height: h)
					.contentShape(Rectangle())
					.zIndex(1)
				
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
			.offset(x: x, y: y) // place the local container once
		}
		.frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
		.zIndex(10)
	}
	
	// MARK: - Helpers
	
	private var effectiveStep: CGFloat { max(0.001, gridStep / max(zoom, 0.0001)) }
	
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
		switch shape {
			case .rect:   return Path(rect)
			case .circle: return Path(ellipseIn: rect)
		}
	}
}
