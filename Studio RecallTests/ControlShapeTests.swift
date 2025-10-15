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
			.circle, .rectangle, .triangle,
			// Deprecated but still supported for backward compatibility
			.rect, .wedge, .line, .dot, .pointer,
			.chickenhead, .knurl, .dLine, .trianglePointer, .arrowPointer
		]
		
		for shape in shapes {
			let encoded = try JSONEncoder().encode(shape)
			let decoded = try JSONDecoder().decode(ImageRegionShape.self, from: encoded)
			#expect(decoded == shape, "Shape \(shape) should encode and decode correctly")
		}
	}
	
	@Test func testSimplifiedShapeMapping() async throws {
		// Test that deprecated shapes map to simplified equivalents
		#expect(ImageRegionShape.circle.simplified == .circle)
		#expect(ImageRegionShape.rectangle.simplified == .rectangle)
		#expect(ImageRegionShape.triangle.simplified == .triangle)
		
		// Deprecated shapes should map to simplified equivalents
		#expect(ImageRegionShape.rect.simplified == .rectangle)
		#expect(ImageRegionShape.line.simplified == .rectangle)
		#expect(ImageRegionShape.chickenhead.simplified == .rectangle)
		#expect(ImageRegionShape.wedge.simplified == .triangle)
		#expect(ImageRegionShape.trianglePointer.simplified == .triangle)
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
	
	@Test func testImageRegionWithSimplifiedShapes() async throws {
		let shapes: [ImageRegionShape] = [
			.circle, .rectangle, .triangle
		]
		
		for shape in shapes {
			let region = ImageRegion(
				rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
				mapping: nil,
				shape: shape
			)
			
			let encoded = try JSONEncoder().encode(region)
			let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
			
			#expect(decoded.shape == shape, "Region shape should persist through encoding")
		}
	}
	
	@Test func testImageRegionWithShapeInstances() async throws {
		let instance1 = ShapeInstance(
			shape: .circle,
			position: CGPoint(x: 0.3, y: 0.3),
			size: CGSize(width: 0.2, height: 0.2),
			rotation: 0
		)
		let instance2 = ShapeInstance(
			shape: .rectangle,
			position: CGPoint(x: 0.7, y: 0.7),
			size: CGSize(width: 0.15, height: 0.15),
			rotation: 45
		)
		
		let region = ImageRegion(
			rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
			mapping: nil,
			shape: .circle,
			shapeInstances: [instance1, instance2]
		)
		
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shapeInstances.count == 2, "Should have two shape instances")
		#expect(decoded.shapeInstances[0].shape == .circle, "First instance should be circle")
		#expect(decoded.shapeInstances[1].shape == .rectangle, "Second instance should be rectangle")
		#expect(decoded.shapeInstances[1].rotation == 45, "Second instance rotation should persist")
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
			.circle, .rectangle, .triangle
		]
		
		let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
		
		for shape in shapes {
			let clipShape = RegionClipShape(shape: shape)
			let path = clipShape.path(in: testRect)
			
			// Path should not be empty for valid shapes
			#expect(!path.isEmpty, "Path for \(shape) should not be empty")
		}
	}
	
	@Test func testRegionClipShapeWithMultipleInstances() async throws {
		let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
		let instances = [
			ShapeInstance(shape: .circle, position: CGPoint(x: 0.3, y: 0.3), size: CGSize(width: 0.2, height: 0.2)),
			ShapeInstance(shape: .rectangle, position: CGPoint(x: 0.7, y: 0.7), size: CGSize(width: 0.15, height: 0.15)),
			ShapeInstance(shape: .triangle, position: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.25, height: 0.25))
		]
		
		let clipShape = RegionClipShape(shape: .circle, shapeInstances: instances)
		let path = clipShape.path(in: testRect)
		
		#expect(!path.isEmpty, "Path with multiple instances should not be empty")
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
	
	// MARK: - RegionHitLayer and RegionOverlay Tests
	
	// MARK: - ShapeInstance Tests
	
	@Test func testShapeInstanceCreation() async throws {
		let instance = ShapeInstance(
			shape: .circle,
			position: CGPoint(x: 0.5, y: 0.5),
			size: CGSize(width: 0.3, height: 0.3),
			rotation: 45
		)
		
		#expect(instance.shape == .circle, "Shape should be circle")
		#expect(instance.position.x == 0.5, "Position X should be 0.5")
		#expect(instance.position.y == 0.5, "Position Y should be 0.5")
		#expect(instance.size.width == 0.3, "Width should be 0.3")
		#expect(instance.size.height == 0.3, "Height should be 0.3")
		#expect(instance.rotation == 45, "Rotation should be 45")
	}
	
	@Test func testShapeInstanceCodable() async throws {
		let instance = ShapeInstance(
			shape: .rectangle,
			position: CGPoint(x: 0.6, y: 0.4),
			size: CGSize(width: 0.2, height: 0.4),
			rotation: 90
		)
		
		let encoded = try JSONEncoder().encode(instance)
		let decoded = try JSONDecoder().decode(ShapeInstance.self, from: encoded)
		
		#expect(decoded.shape == .rectangle, "Shape should persist")
		#expect(decoded.position.x == 0.6, "Position X should persist")
		#expect(decoded.position.y == 0.4, "Position Y should persist")
		#expect(decoded.size.width == 0.2, "Width should persist")
		#expect(decoded.size.height == 0.4, "Height should persist")
		#expect(decoded.rotation == 90, "Rotation should persist")
	}
	
	@Test func testShapeInstancesInRegion() async throws {
		let instance1 = ShapeInstance(shape: .circle, position: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.3, height: 0.3))
		let instance2 = ShapeInstance(shape: .rectangle, position: CGPoint(x: 0.3, y: 0.7), size: CGSize(width: 0.2, height: 0.1))
		
		var region = ImageRegion(
			rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
			shape: .circle
		)
		region.shapeInstances = [instance1, instance2]
		
		#expect(region.shapeInstances.count == 2, "Should have 2 shape instances")
		#expect(region.shapeInstances[0].shape == .circle, "First instance should be circle")
		#expect(region.shapeInstances[1].shape == .rectangle, "Second instance should be rectangle")
		
		// Test encoding
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shapeInstances.count == 2, "Shape instances should persist")
		#expect(decoded.shapeInstances[0].shape == .circle, "First shape should persist")
		#expect(decoded.shapeInstances[1].shape == .rectangle, "Second shape should persist")
	}
	
	@Test func testSimplifiedShapesHaveValidPathsForHitTesting() async throws {
		// Test that all simplified shapes generate valid paths for hit testing and outlining
		let shapes: [ImageRegionShape] = [
			.circle, .rectangle, .triangle
		]
		
		let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
		
		for shape in shapes {
			// Test path generation
			let clipShape = RegionClipShape(shape: shape)
			let path = clipShape.path(in: testRect)
			
			#expect(!path.isEmpty, "Path for \(shape) should not be empty")
			
			// Test that the path can be used for content shape (hit testing)
			let contentShape = RegionClipShape(shape: shape)
			let contentPath = contentShape.path(in: testRect)
			#expect(!contentPath.isEmpty, "Content path for \(shape) should not be empty")
		}
	}
	
	@Test func testDeprecatedShapesStillGenerateValidPaths() async throws {
		// Test backward compatibility with deprecated shapes
		let deprecatedShapes: [ImageRegionShape] = [
			.rect, .wedge, .line, .dot, .pointer,
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
		
		for shape in deprecatedShapes {
			let clipShape = RegionClipShape(shape: shape, maskParams: maskParams)
			let path = clipShape.path(in: testRect)
			
			#expect(!path.isEmpty, "Path for deprecated shape \(shape) should not be empty for backward compatibility")
		}
	}
	
	@Test func testRegionWithShapeInstancesIsEditable() async throws {
		// Test that a region with multiple shape instances
		// has all the necessary properties to be properly rendered and edited
		let instance1 = ShapeInstance(
			shape: .circle,
			position: CGPoint(x: 0.3, y: 0.3),
			size: CGSize(width: 0.2, height: 0.2),
			rotation: 0
		)
		let instance2 = ShapeInstance(
			shape: .triangle,
			position: CGPoint(x: 0.7, y: 0.7),
			size: CGSize(width: 0.15, height: 0.15),
			rotation: 45
		)
		
		let region = ImageRegion(
			rect: CGRect(x: 0.4, y: 0.4, width: 0.6, height: 0.6),
			mapping: .rotate(min: -135, max: 135),
			shape: .circle,
			shapeInstances: [instance1, instance2]
		)
		
		// Verify all properties are set correctly
		#expect(region.shape == .circle, "Region shape should be circle")
		#expect(region.shapeInstances.count == 2, "Region should have 2 shape instances")
		#expect(region.shapeInstances[0].shape == .circle, "First instance should be circle")
		#expect(region.shapeInstances[1].shape == .triangle, "Second instance should be triangle")
		#expect(region.shapeInstances[1].rotation == 45, "Second instance rotation should be 45")
		
		// Verify that the region can be serialized (important for editing persistence)
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shape == .circle, "Decoded shape should match")
		#expect(decoded.shapeInstances.count == 2, "Decoded region should retain shape instances")
		#expect(decoded.shapeInstances[0].shape == .circle, "Decoded first instance should be circle")
		#expect(decoded.shapeInstances[1].rotation == 45, "Decoded rotation should persist")
	}
	
	// MARK: - Shape Parameters Editability Tests
	
	@Test func testShapeInstancesAreEditable() async throws {
		// Verify that shape instances can be edited
		var region = ImageRegion(
			rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
			mapping: .rotate(min: -135, max: 135),
			shape: .circle,
			shapeInstances: [
				ShapeInstance(
					shape: .circle,
					position: CGPoint(x: 0.5, y: 0.5),
					size: CGSize(width: 0.2, height: 0.2),
					rotation: 0
				)
			]
		)
		
		// Simulate editing the instance
		region.shapeInstances[0].position = CGPoint(x: 0.6, y: 0.6)
		region.shapeInstances[0].size = CGSize(width: 0.3, height: 0.3)
		region.shapeInstances[0].rotation = 90
		region.shapeInstances[0].shape = .rectangle
		
		// Verify the changes persisted
		#expect(region.shapeInstances[0].position.x == 0.6, "Position X should be updated")
		#expect(region.shapeInstances[0].size.width == 0.3, "Size width should be updated")
		#expect(region.shapeInstances[0].rotation == 90, "Rotation should be updated")
		#expect(region.shapeInstances[0].shape == .rectangle, "Shape should be updated")
		
		// Verify the changes persist through serialization
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shapeInstances[0].position.x == 0.6, "Decoded position X should match")
		#expect(decoded.shapeInstances[0].size.width == 0.3, "Decoded size should match")
		#expect(decoded.shapeInstances[0].rotation == 90, "Decoded rotation should match")
		#expect(decoded.shapeInstances[0].shape == .rectangle, "Decoded shape should match")
	}
	
	@Test func testShapeInstancesWorkIndependentlyFromLegacySystem() async throws {
		// Verify that shape instances work independently of deprecated useAlphaMask and maskParams
		let region = ImageRegion(
			rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
			mapping: .rotate(min: -135, max: 135),
			shape: .circle,
			shapeInstances: [
				ShapeInstance(
					shape: .circle,
					position: CGPoint(x: 0.5, y: 0.5),
					size: CGSize(width: 0.2, height: 0.2),
					rotation: 0
				)
			],
			useAlphaMask: false
		)
		
		// Verify that shape instances work even when useAlphaMask is false
		#expect(region.shapeInstances.count == 1, "Shape instances should exist independent of useAlphaMask")
		#expect(region.shapeInstances[0].shape == .circle, "Shape instance type should be preserved")
		
		// Verify serialization
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.shapeInstances.count == 1, "Decoded shape instances should exist")
		#expect(decoded.shapeInstances[0].shape == .circle, "Decoded shape should match")
		#expect(decoded.useAlphaMask == false, "Deprecated useAlphaMask should be false")
	}
	
	@Test func testBackwardCompatibilityWithLegacyMaskParams() async throws {
		// Verify that old sessions with maskParams still work
		let region = ImageRegion(
			rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
			mapping: .rotate(min: -135, max: 135),
			shape: .chickenhead,
			useAlphaMask: false,
			maskParams: MaskParameters(
				style: .chickenhead,
				angleOffset: -90,
				width: 0.15,
				innerRadius: 0.1,
				outerRadius: 0.9
			)
		)
		
		// Verify that maskParams are still available for backward compatibility
		#expect(region.maskParams != nil, "Legacy maskParams should be preserved")
		#expect(region.maskParams?.style == .chickenhead, "Legacy maskParams style should be preserved")
		
		// Verify serialization for backward compatibility
		let encoded = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(ImageRegion.self, from: encoded)
		
		#expect(decoded.maskParams != nil, "Decoded legacy maskParams should exist")
		#expect(decoded.maskParams?.style == .chickenhead, "Decoded legacy style should match")
	}
}
