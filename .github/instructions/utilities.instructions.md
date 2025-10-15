applyTo:
  - Studio Recall/Utilities/**
  - Studio Recall/Extensions/**

## Utilities and Extensions Guidelines

### Extension Organization

Place extensions in the `Extensions/` directory, grouped by type:
- `Array+Extensions.swift`: Array utility methods
- `NSImage+Extensions.swift`: Image manipulation helpers
- `CGPoint+Extensions.swift`: Geometry helpers
- etc.

### Extension Best Practices

#### Focused Extensions
Keep extensions focused on a single concern:
```swift
// ✅ Good - focused on CGImage conversion
extension NSImage {
    func forceCGImage() -> CGImage? {
        // Robust conversion handling PDF/TIFF-backed images
    }
}
```

#### Descriptive Naming
Use clear, descriptive method names:
```swift
extension Array where Element == DeviceInstance {
    func findByID(_ id: UUID) -> DeviceInstance? {
        first { $0.id == id }
    }
}
```

#### Document Complex Extensions
Add documentation comments for non-obvious extensions:
```swift
extension CGPoint {
    /// Converts point from top-left to bottom-left coordinate system
    /// - Parameter height: Source image/view height for Y-axis flip
    func flipY(sourceHeight height: CGFloat) -> CGPoint {
        CGPoint(x: x, y: height - y)
    }
}
```

### Utility File Organization

Utilities should be:
1. **Stateless**: Pure functions when possible
2. **Focused**: Single responsibility per file
3. **Tested**: Unit tested for correctness
4. **Documented**: Clear purpose and usage

### Common Utility Categories

#### Image Utilities
```swift
struct ImageUtilities {
    /// Converts NSImage to PNG data
    static func toPNGData(_ image: NSImage) -> Data? {
        guard let cgImage = image.forceCGImage() else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
    
    /// Downscales image for processing
    static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        // Implementation
    }
}
```

#### Geometry Utilities
```swift
struct GeometryUtilities {
    /// Calculates bounding rect for array of points
    static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        // Implementation
    }
    
    /// Normalizes point to 0-1 range within rect
    static func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }
}
```

#### Color Utilities
```swift
struct ColorUtilities {
    /// Converts brightness value (0-1) to color
    static func color(forBrightness brightness: Double) -> NSColor {
        NSColor(white: brightness, alpha: 1.0)
    }
    
    /// Interpolates between two colors
    static func lerp(from: NSColor, to: NSColor, t: Double) -> NSColor {
        // Implementation
    }
}
```

### Coordinate System Helpers

Studio Recall uses multiple coordinate systems. Provide clear conversion utilities:

```swift
// Top-left <-> Bottom-left conversion
func flipY(_ y: CGFloat, sourceHeight: CGFloat) -> CGFloat {
    sourceHeight - y
}

// Pixel space -> Normalized space
func normalize(point: CGPoint, imageSize: CGSize) -> CGPoint {
    CGPoint(
        x: point.x / imageSize.width,
        y: point.y / imageSize.height
    )
}

// Normalized space -> Pixel space
func denormalize(point: CGPoint, imageSize: CGSize) -> CGPoint {
    CGPoint(
        x: point.x * imageSize.width,
        y: point.y * imageSize.height
    )
}
```

### Mask Generation Utilities

For alpha mask generation:
```swift
struct MaskGenerator {
    /// Generates alpha mask for control pointer
    static func generateMask(
        for shape: ControlShape,
        parameters: MaskParameters,
        size: CGSize
    ) -> CGImage? {
        // Create context
        let context = CGContext(/* ... */)
        
        // Draw shape based on type
        switch shape {
        case .chickenhead:
            drawChickenhead(in: context, params: parameters)
        case .knurl:
            drawKnurl(in: context, params: parameters)
        // etc.
        }
        
        return context.makeImage()
    }
}
```

### File Management Utilities

For JSON persistence:
```swift
struct FileUtilities {
    /// Get URL for file in Documents directory
    static func documentsURL(for filename: String) -> URL {
        let paths = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        return paths[0].appendingPathComponent(filename)
    }
    
    /// Get URL for file in Application Support
    static func appSupportURL(for filename: String) -> URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        
        let paths = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        let appDir = paths[0].appendingPathComponent(bundleID)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true
        )
        
        return appDir.appendingPathComponent(filename)
    }
}
```

### Platform-Specific Utilities

Wrap platform differences:
```swift
#if os(macOS)
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#else
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#endif

extension PlatformImage {
    func toCGImage() -> CGImage? {
        #if os(macOS)
        return forceCGImage()
        #else
        return cgImage
        #endif
    }
}
```

### Value Mapping Utilities

For control value interpolation:
```swift
struct MappingUtilities {
    /// Linear interpolation
    static func lerp(from: Double, to: Double, t: Double) -> Double {
        from + (to - from) * t
    }
    
    /// Inverse lerp (get t from value)
    static func inverseLerp(value: Double, from: Double, to: Double) -> Double {
        guard from != to else { return 0 }
        return (value - from) / (to - from)
    }
    
    /// Clamp value to range
    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
    
    /// Map value from one range to another
    static func map(value: Double, 
                   fromRange: (Double, Double),
                   toRange: (Double, Double)) -> Double {
        let t = inverseLerp(value: value, from: fromRange.0, to: fromRange.1)
        return lerp(from: toRange.0, to: toRange.1, t: t)
    }
}
```

### Decibel Conversion

For audio controls with dB scales:
```swift
struct DecibelUtilities {
    /// Convert linear (0-1) to decibels
    static func linearToDecibels(_ linear: Double, 
                                 minDB: Double = -60) -> Double {
        guard linear > 0 else { return minDB }
        return 20 * log10(linear)
    }
    
    /// Convert decibels to linear (0-1)
    static func decibelsToLinear(_ db: Double) -> Double {
        pow(10, db / 20)
    }
}
```

### Path Generation Utilities

For control shapes:
```swift
struct PathUtilities {
    /// Generates circular arc path
    static func arc(center: CGPoint, radius: CGFloat,
                   startAngle: CGFloat, endAngle: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: endAngle,
                   clockwise: false)
        return path
    }
    
    /// Generates rectangle with rounded corners
    static func roundedRect(_ rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerRadiusWidth: cornerRadius,
               cornerRadiusHeight: cornerRadius, transform: nil)
    }
}
```

### Validation Utilities

For data validation:
```swift
struct ValidationUtilities {
    /// Validates UUID string
    static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }
    
    /// Validates normalized coordinate (0-1)
    static func isNormalized(_ value: Double) -> Bool {
        value >= 0 && value <= 1
    }
    
    /// Validates rack placement
    static func canPlace(
        device: Device,
        at row: Int, col: Int,
        in rack: Rack
    ) -> Bool {
        let width = device.rackWidth.columns
        let height = device.rackUnits
        
        // Check bounds
        guard row + height <= rack.rows,
              col + width <= RackGrid.columnsPerRow else {
            return false
        }
        
        // Check if cells are empty
        for r in row..<(row + height) {
            for c in col..<(col + width) {
                if rack.grid[r][c] != nil {
                    return false
                }
            }
        }
        
        return true
    }
}
```

### Performance Utilities

For profiling and optimization:
```swift
struct PerformanceUtilities {
    /// Measure execution time of block
    static func measure<T>(label: String = "", _ block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        #if DEBUG
        print("⏱ \(label): \(String(format: "%.3f", elapsed * 1000))ms")
        #endif
        
        return result
    }
}
```

### Testing Utilities

For test helpers:
```swift
// In test target
extension Device {
    static func makeTest(
        name: String = "Test Device",
        type: DeviceType = .rack,
        rackUnits: Int = 1,
        rackWidth: RackWidth = .full
    ) -> Device {
        Device(
            id: UUID(),
            name: name,
            type: type,
            rackUnits: rackUnits,
            rackWidth: rackWidth,
            controls: []
        )
    }
}
```

### Documentation Standards

Document all public utility functions:
```swift
/// Converts a point from normalized (0-1) coordinates to pixel coordinates
///
/// - Parameters:
///   - point: Point in normalized space (0-1)
///   - size: Target size in pixels
/// - Returns: Point in pixel coordinates
static func denormalize(point: CGPoint, size: CGSize) -> CGPoint {
    // Implementation
}
```

### Naming Conventions

- Utilities: `XxxUtilities` (e.g., `ImageUtilities`)
- Extensions: `Type+Extensions.swift` (e.g., `Array+Extensions.swift`)
- Methods: Use verbs for actions, nouns for queries
- Parameters: Clear, descriptive names

### Common Pitfalls

1. **Don't add utilities prematurely**: Only create when needed by multiple places
2. **Avoid stateful utilities**: Keep utilities pure and stateless
3. **Test thoroughly**: Utilities are used widely, bugs affect many features
4. **Document coordinate systems**: Always document which system is used
5. **Handle edge cases**: Nil, empty, zero, infinity, NaN, etc.
