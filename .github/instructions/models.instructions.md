applyTo:
  - Studio Recall/Models/**

## Data Models Guidelines

### Codable Conformance

All data models MUST conform to `Codable` for JSON persistence:
```swift
struct Device: Identifiable, Codable {
    let id: UUID
    var name: String
    // ...
}
```

### UUID Identity

- Use `UUID` for all model identities
- Make ID properties `let` (immutable after creation)
- Never modify IDs after creation - this breaks session references
- Use `first(where: { $0.id == ... })` for lookups

### Enum Patterns

When defining enums with associated values:
```swift
enum ControlValue: Codable {
    case knob(Double)
    case multiSwitch(Int)
    case button(Bool)
    
    static func initialValue(for type: ControlType) -> ControlValue {
        // Always provide initial values
    }
}
```

Always destructure in switch statements:
```swift
switch value {
case .knob(let val): // ✅ Correct
    return val
case .multiSwitch(let index): // ✅ Correct
    return Double(index)
}
```

### Control State Management

- Controls in `Device`: hold default/template values
- Controls in `DeviceInstance.controlStates`: hold actual instance values
- Use `ControlValue.initialValue(for:)` to initialize new controls
- Store control states as `[UUID: ControlValue]` dictionary

### Rack Grid Logic

For `Rack` model:
- 2D grid: rows × 6 columns (`RackGrid.columnsPerRow`)
- Grid is `[[DeviceInstance?]]` - instances replicated across span
- Device span determined by:
  - Height: `rackUnits` (1U, 2U, 3U, etc.)
  - Width: `RackWidth` enum (full=6, half=3, third=2)
- **Anchor cell**: top-left position of device span
- When placing device, ALL cells in span must reference same instance

### Data Model Changes

When adding new properties:
1. Add property to struct/class
2. Ensure `Codable` conformance still works
3. Test backward compatibility with existing JSON files
4. Provide default values for optional properties
5. Update `SessionManager.migrateControlStatesToMatchLibrary()` if needed

### Critical Rules

1. **Never modify IDs** after model creation
2. **Always reconcile** after device definition updates
3. **Test Codable** with round-trip encoding/decoding
4. **Maintain compatibility** with existing JSON files
5. **Initialize control states** properly for new instances

### Image Data

- Store images as `Data?` (PNG format)
- Be mindful of memory usage with large images
- Use `imageData` property name for consistency
- Handle nil gracefully (devices without images)

### Device Types

Two device types with different placement logic:
- `.rack`: 19" rack gear (2D grid placement)
- `.series500`: 500-series modules (1D slot placement)

Ensure new features work with both types.

### Coordinate Systems

Multiple coordinate systems used:
1. **Normalized (0-1)**: Control positions in `Control` model
2. **Top-left pixel**: `ControlDraft` from auto-detection
3. **Bottom-left CGImage**: Core Image operations
4. **Scaled-space**: Downscaled images for processing

When adding coordinate-dependent code, document which system is used.

### Visual Mappings

`VisualMapping` enum types:
- `.rotate`: rotation angles (degMin, degMax, pivot)
- `.brightness`/`.opacity`: scalar with taper
- `.translate`: position interpolation
- `.flip3D`: perspective transform
- `.sprite`: frame-based animation

Mappings work in normalized region space (0-1 of region bounds).
