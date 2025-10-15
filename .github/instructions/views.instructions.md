applyTo:
  - Studio Recall/Views/**

## SwiftUI Views Guidelines

### View Architecture

- Use SwiftUI views for all UI components
- Leverage `@EnvironmentObject` for shared state managers
- Keep views focused and single-purpose
- Extract complex views into separate files

### State Management

#### Property Wrappers
```swift
@State private var isEditing = false        // Local view state
@Binding var selectedDevice: Device?         // Parent-owned state
@EnvironmentObject var sessionManager: SessionManager  // Shared manager
@Published var devices: [Device] = []        // In ObservableObject
```

#### Environment Objects
Key managers injected as environment objects:
- `SessionManager`: session and template management
- `DeviceLibrary`: device library management
- `AppSettings`: app-wide preferences

Access with:
```swift
@EnvironmentObject var sessionManager: SessionManager
```

### Platform-Specific Views

Always use `#if os(macOS)` for platform-specific code:
```swift
#if os(macOS)
// macOS-specific UI (NSImage, NSSavePanel, multi-window)
Text("macOS View")
    .contextMenu { /* macOS menu */ }
#else
// iOS/tvOS alternative (UIImage, sheets, single-window)
Text("iOS View")
    .sheet(isPresented: $showSheet) { /* iOS sheet */ }
#endif
```

### Control Rendering

#### Two Render Modes
- **Photoreal**: actual device images with overlaid controls
- **Representative**: simplified, diagrammatic view with synthetic graphics

When adding control features, support both modes.

#### Complex Control Shapes
Available shapes (via `ControlShape` enum):
- Basic: `.rect`, `.circle`
- Complex: `.chickenhead`, `.knurl`, `.dLine`, `.trianglePointer`, `.arrowPointer`

All shapes must:
1. Generate valid paths for hit testing
2. Support `MaskParameters` for alpha masking
3. Work in both render modes
4. Be editable in control editor

### Hit Testing and Interaction

#### Region Hit Detection
- Use `RegionHitLayer` for detecting taps on control regions
- Use `RegionOverlay` for visual feedback during editing
- Ensure paths match between hit testing and rendering
- Support all control shapes (basic and complex)

#### Drag and Drop
- Use `DragPayload` for device dragging between views
- Implement drop delegates: `ControlDropDelegate`, `ChassisDropDelegate`, `Series500DropDelegate`
- Validate drop targets before accepting drops
- Update session state after successful drops

### Canvas and Coordinate Systems

#### FaceplateCanvas
- Normalized coordinates (0-1) for control positions
- Handle zoom and pan transformations
- Support control selection and editing
- Render device images with control overlays

#### Coordinate Conversion
When working with control positions:
- Store as normalized (0-1) in model
- Convert to view coordinates for rendering
- Use `flipY(_:srcHf:)` helpers for Y-axis flipping
- Document coordinate system in comments

### Metal Rendering

When working with Metal views (in `Views/Metal/`):
- Use instanced rendering for performance
- Batch draw calls to minimize state changes
- Only update buffers when data changes
- Support texture atlas for device images
- Maintain compatibility with SwiftUI fallback

### Accessibility

- Provide `.accessibilityLabel()` for controls
- Use `.accessibilityValue()` for current state
- Support keyboard navigation where appropriate
- Test with VoiceOver on macOS

### Performance

- Minimize view body complexity
- Extract subviews to avoid re-rendering
- Use `@ViewBuilder` for conditional view construction
- Avoid expensive operations in `body`
- Consider lazy loading for lists

### Visual Feedback

- Provide clear selection indicators
- Show hover states (macOS) or press states (iOS)
- Use animations for state transitions
- Maintain consistency with app-wide design

### Common View Patterns

#### Control Editor
- Support real-time preview of control changes
- Show all control parameters in inspector
- Allow drag-to-position and numeric input
- Update model immediately on changes

#### Session Canvas
- Display racks and chassis in scrollable canvas
- Support zoom and pan navigation
- Show device faceplates with current control states
- Allow clicking controls to adjust values

#### Library Editor
- Grid or list view of devices
- Drag devices to session canvas
- Quick preview of device image and details
- Category filtering and search

### SwiftUI Best Practices

1. Keep views declarative and side-effect free
2. Use `onChange(of:)` for observing state changes
3. Prefer composition over inheritance
4. Extract magic numbers to named constants
5. Use `GeometryReader` sparingly (performance impact)
6. Group related modifiers together
7. Use `.task()` for async operations in views

### Conditional Rendering

Prefer `if` over ternary for complex conditions:
```swift
// ✅ Good
if isEditing {
    ControlEditor(control: $control)
} else {
    ControlDisplay(control: control)
}

// ❌ Avoid for complex views
isEditing ? ControlEditor(control: $control) : ControlDisplay(control: control)
```

### Animation

Use `.animation()` modifier for smooth transitions:
```swift
.animation(.easeInOut(duration: 0.3), value: selectedControl)
```

Avoid animating expensive operations (image loading, large layouts).
