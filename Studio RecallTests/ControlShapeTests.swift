//
//  ControlShapeTests.swift
//  Studio RecallTests
//
//  Tests for complex control shape implementations
//

import Testing
import Foundation
import CoreGraphics

@testable import Studio_Recall

struct ControlShapeTests {
	
	// MARK: - ImageRegionShape Enum Tests
	
	@Test func testAllShapesCodable() async throws {
		// Test that all shape types can be encoded and decoded
		let shapes: [ImageRegionShape] = [
			.rect, .circle, .wedge, .line, .dot, .pointer,
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		for shape in shapes {
			let encoded = try JSONEncoder().encode(shape)
			let decoded = try JSONDecoder().decode(ImageRegionShape.self, from: encoded)
			#expect(decoded == shape, "Shape \(shape) should encode and decode correctly")
		}
	}
	
	// MARK: - MaskPointerStyle Tests
	
	@Test func testAllMaskStylesCodable() async throws {
		// Test that all mask pointer styles can be encoded and decoded
		let styles: [MaskPointerStyle] = [
			.wedge, .line, .dot, .rectangle,
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		for style in styles {
			let encoded = try JSONEncoder().encode(style)
			let decoded = try JSONDecoder().decode(MaskPointerStyle.self, from: encoded)
			#expect(decoded == style, "Style \(style) should encode and decode correctly")
		}
	}
	
	// MARK: - MaskParameters Tests
	
	@Test func testMaskParametersWithNewStyles() async throws {
		let styles: [MaskPointerStyle] = [
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		for style in styles {
			let params = MaskParameters(
				style: style,
				angleOffset: -90,
				width: 0.1,
				innerRadius: 0.0,
				outerRadius: 1.0
			)
			
			let encoded = try JSONEncoder().encode(params)
			let decoded = try JSONDecoder().decode(MaskParameters.self, from: encoded)
			
			#expect(decoded.style == style, "MaskParameters style should persist")
			#expect(decoded.angleOffset == -90, "Angle offset should persist")
			#expect(decoded.width == 0.1, "Width should persist")
		}
	}
	
	// MARK: - ImageRegion Tests
	
	@Test func testImageRegionWithComplexShapes() async throws {
		let shapes: [ImageRegionShape] = [
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		for shape in shapes {
			let region = ImageRegion(
				rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
				mapping: nil,
				shape: shape,
				useAlphaMask: false
			)
			
			let encoded = try JSONEncoder().encode(region)
			let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
			
			#expect(decoded.shape == shape, "Region shape should persist through encoding")
		}
	}
	
	@Test func testImageRegionWithMaskParameters() async throws {
		let maskParams = MaskParameters(
			style: .chickenhead,
			angleOffset: -45,
			width: 0.15,
			innerRadius: 0.1,
			outerRadius: 0.9
		)
		
		let region = ImageRegion(
			rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
			mapping: nil,
			shape: .chickenhead,
			useAlphaMask: true,
			alphaMaskImage: nil,
			maskParams: maskParams
		)
		
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shape == .chickenhead, "Shape should be chickenhead")
		#expect(decoded.useAlphaMask == true, "Alpha mask flag should persist")
		#expect(decoded.maskParams?.style == .chickenhead, "Mask params style should persist")
		#expect(decoded.maskParams?.angleOffset == -45, "Mask params angle should persist")
	}
	
	// MARK: - Control Tests
	
	@Test func testControlWithComplexShape() async throws {
		var control = Control(name: "Test Knob", type: .knob, x: 0.5, y: 0.5)
		
		let region = ImageRegion(
			rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
			mapping: .rotate(min: -135, max: 135),
			shape: .chickenhead,
			useAlphaMask: true,
			maskParams: MaskParameters(style: .chickenhead)
		)
		
		control.regions = [region]
		
		let encoded = try JSONEncoder().encode(control)
		let decoded = try JSONDecoder().decode(Control.self, from: encoded)
		
		#expect(decoded.regions.count == 1, "Control should have one region")
		#expect(decoded.regions[0].shape == .chickenhead, "Region shape should be chickenhead")
		#expect(decoded.regions[0].useAlphaMask == true, "Alpha mask should be enabled")
	}
	
	// MARK: - RegionClipShape Path Generation Tests
	
	@Test func testRegionClipShapeGeneratesValidPaths() async throws {
		let shapes: [ImageRegionShape] = [
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
		let maskParams = MaskParameters(
			style: .line,
			angleOffset: -90,
			width: 0.1,
			innerRadius: 0.0,
			outerRadius: 1.0
		)
		
		for shape in shapes {
			let clipShape = RegionClipShape(shape: shape, maskParams: maskParams)
			let path = clipShape.path(in: testRect)
			
			// Path should not be empty for valid shapes
			#expect(!path.isEmpty, "Path for \(shape) should not be empty")
		}
	}
	
	// MARK: - Backward Compatibility Tests
	
	@Test func testBackwardCompatibilityWithExistingShapes() async throws {
		// Ensure new shapes don't break existing shape functionality
		let existingShapes: [ImageRegionShape] = [.rect, .circle, .wedge, .line, .dot, .pointer]
		
		for shape in existingShapes {
			let region = ImageRegion(
				rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
				mapping: nil,
				shape: shape
			)
			
			let encoded = try JSONEncoder().encode(region)
			let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
			
			#expect(decoded.shape == shape, "Existing shape \(shape) should still work correctly")
		}
	}
	
	// MARK: - Edge Case Tests
	
	@Test func testMaskParametersWithExtremeValues() async throws {
		let params = MaskParameters(
			style: .chickenhead,
			angleOffset: 180,  // Max positive angle
			width: 0.5,        // Large width
			innerRadius: 0.0,  // Minimum inner radius
			outerRadius: 1.0   // Maximum outer radius
		)
		
		let encoded = try JSONEncoder().encode(params)
		let decoded = try JSONDecoder().decode(MaskParameters.self, from: encoded)
		
		#expect(decoded.angleOffset == 180, "Extreme angle should persist")
		#expect(decoded.width == 0.5, "Large width should persist")
	}
	
	@Test func testMultipleRegionsWithDifferentComplexShapes() async throws {
		var control = Control(name: "Multi-Shape Control", type: .knob, x: 0.5, y: 0.5)
		
		let region1 = ImageRegion(rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), shape: .chickenhead)
		let region2 = ImageRegion(rect: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), shape: .knurl)
		
		control.regions = [region1, region2]
		
		let encoded = try JSONEncoder().encode(control)
		let decoded = try JSONDecoder().decode(Control.self, from: encoded)
		
		#expect(decoded.regions.count == 2, "Control should have two regions")
		#expect(decoded.regions[0].shape == .chickenhead, "First region should be chickenhead")
		#expect(decoded.regions[1].shape == .knurl, "Second region should be knurl")
	}
}
