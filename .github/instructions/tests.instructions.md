applyTo:
  - Studio RecallTests/**
  - Studio RecallUITests/**

## Testing Guidelines

### Test Structure

#### Unit Tests (`Studio RecallTests`)
- Test data models, managers, and business logic
- Test `Codable` conformance for all data models
- Test state management and mutations
- Test edge cases and boundary conditions
- Test backward compatibility

#### UI Tests (`Studio RecallUITests`)
- Test user interactions and workflows
- Test navigation and view transitions
- Test drag and drop operations
- Test control interactions

### Naming Conventions

Use descriptive test method names that explain what is being tested:
```swift
func testComplexShapesHaveValidPathsForHitTesting() { }
func testRegionWithComplexShapeAndMaskParamsIsEditable() { }
func testDeviceInstanceInitializesControlStatesWithDefaults() { }
func testRackPlacementUpdatesAllCellsInDeviceSpan() { }
```

Format: `test<WhatIsBeingTested><ExpectedBehavior>`

### Test Organization

Group related tests in the same file:
- `ControlShapeTests.swift`: tests for control shapes and rendering
- `DeviceTests.swift`: tests for Device model
- `SessionManagerTests.swift`: tests for SessionManager
- `CodableTests.swift`: tests for JSON encoding/decoding

### Critical Test Categories

#### 1. Codable Conformance Tests

Always test JSON round-trip encoding/decoding:
```swift
func testDeviceEncodeDecode() throws {
    let device = Device(/* ... */)
    let encoder = JSONEncoder()
    let data = try encoder.encode(device)
    
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Device.self, from: data)
    
    XCTAssertEqual(device.id, decoded.id)
    XCTAssertEqual(device.name, decoded.name)
    // Test all properties
}
```

#### 2. Backward Compatibility Tests

Test that old JSON files load correctly:
```swift
func testBackwardCompatibilityWithV1Format() throws {
    let jsonString = """
    {
        "id": "...",
        "name": "Test Device"
        // Old format without new properties
    }
    """
    let data = jsonString.data(using: .utf8)!
    let device = try JSONDecoder().decode(Device.self, from: data)
    
    // Verify defaults for missing properties
    XCTAssertNotNil(device)
}
```

#### 3. State Management Tests

Test that state updates propagate correctly:
```swift
func testSetControlValueUpdatesInstanceState() {
    let control = Control(type: .knob, /* ... */)
    let device = Device(/* ... */)
    let instance = deviceLibrary.createInstance(from: device)
    
    sessionManager.setControlValue(control.id, value: .knob(0.75), 
                                   in: instance.id, session: session)
    
    let updated = session.findInstance(instance.id)
    XCTAssertEqual(updated?.controlStates[control.id], .knob(0.75))
}
```

#### 4. Edge Case Tests

Test boundary conditions and edge cases:
```swift
func testRackPlacementAtGridBoundary() {
    // Test placing device at edge of rack grid
}

func testControlValueClampingToValidRange() {
    // Test values outside valid range are clamped
}

func testEmptyDeviceLibraryHandling() {
    // Test behavior with no devices
}
```

### XCTest Assertions

Use appropriate assertions:
- `XCTAssertEqual`: for equality checks
- `XCTAssertNotNil`: for nil checks
- `XCTAssertTrue/False`: for boolean conditions
- `XCTAssertThrowsError`: for error cases
- `XCTAssertNoThrow`: for success cases

### Test Data Setup

#### setUp() and tearDown()
```swift
class DeviceTests: XCTestCase {
    var deviceLibrary: DeviceLibrary!
    var sessionManager: SessionManager!
    
    override func setUp() {
        super.setUp()
        deviceLibrary = DeviceLibrary()
        sessionManager = SessionManager(library: deviceLibrary)
    }
    
    override func tearDown() {
        deviceLibrary = nil
        sessionManager = nil
        super.tearDown()
    }
}
```

#### Test Fixtures
Create reusable test data:
```swift
extension Device {
    static func makeTestDevice() -> Device {
        Device(
            id: UUID(),
            name: "Test Device",
            type: .rack,
            rackUnits: 1,
            rackWidth: .full,
            controls: []
        )
    }
}
```

### Testing Complex Features

#### Control Auto-Detection
```swift
func testAutoDetectFindsKnobsInImage() {
    let image = NSImage(/* test image */)
    let config = ControlAutoDetect.Config.fromSensitivity(0.5)
    
    let drafts = ControlAutoDetect.detect(on: image, config: config)
    
    XCTAssertGreaterThan(drafts.count, 0)
    XCTAssertTrue(drafts.contains { $0.type == .knob })
}
```

#### Rack Placement
```swift
func testDeviceSpansCorrectNumberOfCells() {
    let device = Device.makeTestDevice(rackUnits: 2, rackWidth: .half)
    let rack = Rack(rows: 10)
    
    sessionManager.placeDevice(device, intoRack: rack, row: 0, col: 0)
    
    // Verify 2 rows × 3 columns are occupied
    for r in 0..<2 {
        for c in 0..<3 {
            XCTAssertNotNil(rack.grid[r][c])
        }
    }
}
```

#### Visual Mappings
```swift
func testRotateMappingInterpolatesCorrectly() {
    let mapping = VisualMapping.rotate(
        degMin: -135,
        degMax: 135,
        pivot: CGPoint(x: 0.5, y: 0.5)
    )
    
    let angle = mapping.rotation(for: 0.5) // Mid-point
    XCTAssertEqual(angle, 0, accuracy: 0.01)
}
```

### Performance Tests

Use `measure()` for performance-critical operations:
```swift
func testAutoDetectionPerformance() {
    let image = NSImage(/* large test image */)
    
    measure {
        _ = ControlAutoDetect.detect(on: image, config: .default)
    }
}
```

### Asynchronous Tests

Use expectations for async operations:
```swift
func testAsyncImageLoading() {
    let expectation = expectation(description: "Image loads")
    
    imageLoader.loadImage(url: testURL) { result in
        XCTAssertNotNil(result)
        expectation.fulfill()
    }
    
    waitForExpectations(timeout: 5)
}
```

### Test Coverage Goals

Aim for comprehensive coverage:
- **Models**: 95%+ (critical for data integrity)
- **Managers**: 90%+ (business logic)
- **Utilities**: 85%+ (helper functions)
- **Views**: 70%+ (UI logic)

Focus on:
1. All Codable conformance
2. All state mutations
3. All validation logic
4. All error handling paths
5. All platform-specific branches

### Testing Best Practices

1. **Test one thing per test**: Each test should verify a single behavior
2. **Independent tests**: Tests should not depend on each other
3. **Fast tests**: Keep tests fast (mock heavy operations)
4. **Descriptive failures**: Use clear assertion messages
5. **Avoid test interdependence**: Don't rely on test execution order
6. **Clean up resources**: Use tearDown() to clean up
7. **Test edge cases**: Empty arrays, nil values, boundary conditions

### Mocking and Stubbing

For unit tests, mock external dependencies:
```swift
class MockDeviceLibrary: DeviceLibrary {
    var mockDevices: [Device] = []
    
    override func device(for id: UUID) -> Device? {
        mockDevices.first { $0.id == id }
    }
}
```

### Continuous Testing

- Run tests frequently during development
- Fix failing tests immediately
- Don't commit failing tests
- Add tests for bug fixes to prevent regression

### Documentation in Tests

Add comments for complex test setups:
```swift
func testComplexScenario() {
    // Given: A device with multiple concentric knobs
    let device = Device(/* ... */)
    
    // When: User rotates outer knob
    let newValue = ControlValue.knob(0.75)
    
    // Then: Only outer region should rotate
    // (inner region should remain unchanged)
    XCTAssertEqual(/* ... */)
}
```
