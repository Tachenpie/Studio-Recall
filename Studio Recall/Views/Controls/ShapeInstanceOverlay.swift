//
//  ShapeInstanceOverlay.swift
//  Studio Recall
//
//  Visual overlay for individual shape instances with marching ants outline
//

import SwiftUI

struct ShapeInstanceOverlay: View {
	let shapeInstance: ShapeInstance
	let regionRect: CGRect  // normalized (0-1) canvas coordinates
	let canvasSize: CGSize
	let zoom: CGFloat
	
	// Animation state for marching ants
	@State private var dashPhase: CGFloat = 0
	
	var body: some View {
		let instanceFrame = calculateInstanceFrame()
		let localSize = instanceFrame.size
		
		// Screen-constant metrics
		let z = max(zoom, 0.0001)
		let hair: CGFloat = 1.0 / z
		let dashUnit: CGFloat = 6.0 / z
		let dash: [CGFloat] = [dashUnit, dashUnit]
		let handleSize: CGFloat = 8.0 / z
		
		ZStack(alignment: .topLeading) {
			// Shape outline with marching ants
			let shapePath = createShapePath(in: CGRect(origin: .zero, size: localSize))
			
			Path { _ in shapePath }
				.stroke(.black, style: StrokeStyle(lineWidth: hair, dash: dash))
				.overlay(
					Path { _ in shapePath }
						.stroke(.white, style: StrokeStyle(lineWidth: hair, dash: dash, dashPhase: dashPhase))
				)
			
			// Corner handles
			Group {
				// Top-left
				handleSquare(size: handleSize, hair: hair)
					.position(x: handleSize/2, y: handleSize/2)
				
				// Top-right
				handleSquare(size: handleSize, hair: hair)
					.position(x: localSize.width - handleSize/2, y: handleSize/2)
				
				// Bottom-left
				handleSquare(size: handleSize, hair: hair)
					.position(x: handleSize/2, y: localSize.height - handleSize/2)
				
				// Bottom-right
				handleSquare(size: handleSize, hair: hair)
					.position(x: localSize.width - handleSize/2, y: localSize.height - handleSize/2)
			}
			
			// Edge handles (for rectangles and triangles)
			if shapeInstance.shape != .circle {
				Group {
					// Top
					handleSquare(size: handleSize, hair: hair)
						.position(x: localSize.width/2, y: handleSize/2)
					
					// Bottom
					handleSquare(size: handleSize, hair: hair)
						.position(x: localSize.width/2, y: localSize.height - handleSize/2)
					
					// Left
					handleSquare(size: handleSize, hair: hair)
						.position(x: handleSize/2, y: localSize.height/2)
					
					// Right
					handleSquare(size: handleSize, hair: hair)
						.position(x: localSize.width - handleSize/2, y: localSize.height/2)
				}
			}
			
			// Rotation handle (small circle above the shape)
			let rotHandleOffset: CGFloat = 20.0 / z
			Circle()
				.fill(.white)
				.frame(width: handleSize, height: handleSize)
				.overlay(Circle().stroke(.black, lineWidth: hair))
				.position(x: localSize.width/2, y: -rotHandleOffset)
			
			// Line connecting rotation handle to shape
			Path { path in
				path.move(to: CGPoint(x: localSize.width/2, y: 0))
				path.addLine(to: CGPoint(x: localSize.width/2, y: -rotHandleOffset + handleSize/2))
			}
			.stroke(.black, style: StrokeStyle(lineWidth: hair, dash: [4.0/z, 2.0/z]))
		}
		.frame(width: localSize.width, height: localSize.height)
		.rotationEffect(.degrees(shapeInstance.rotation), anchor: .center)
		.position(x: instanceFrame.midX, y: instanceFrame.midY)
		.frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
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
	
	private func handleSquare(size: CGFloat, hair: CGFloat) -> some View {
		Rectangle()
			.fill(.white)
			.frame(width: size, height: size)
			.overlay(Rectangle().stroke(.black, lineWidth: hair))
			.allowsHitTesting(false)
	}
	
	private func calculateInstanceFrame() -> CGRect {
		// Convert region rect from normalized canvas coords to pixel coords
		let regionPixels = CGRect(
			x: regionRect.origin.x * canvasSize.width,
			y: regionRect.origin.y * canvasSize.height,
			width: regionRect.size.width * canvasSize.width,
			height: regionRect.size.height * canvasSize.height
		)
		
		// Shape instance position/size are relative to region (0-1)
		// Convert to canvas pixel coordinates
		let x = regionPixels.minX + shapeInstance.position.x * regionPixels.width
		let y = regionPixels.minY + shapeInstance.position.y * regionPixels.height
		let w = shapeInstance.size.width * regionPixels.width
		let h = shapeInstance.size.height * regionPixels.height
		
		// Center the frame at the position point
		return CGRect(
			x: x - w/2,
			y: y - h/2,
			width: w,
			height: h
		)
	}
	
	private func createShapePath(in rect: CGRect) -> CGPath {
		let path = CGMutablePath()
		
		switch shapeInstance.shape {
		case .circle:
			path.addEllipse(in: rect)
			
		case .rectangle:
			path.addRect(rect)
			
		case .triangle:
			// Equilateral triangle pointing up
			let topPoint = CGPoint(x: rect.midX, y: rect.minY)
			let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
			let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
			
			path.move(to: topPoint)
			path.addLine(to: bottomRight)
			path.addLine(to: bottomLeft)
			path.closeSubpath()
			
		default:
			// For any legacy shape types, use rectangle
			path.addRect(rect)
		}
		
		return path
	}
}
