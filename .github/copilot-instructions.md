# GitHub Copilot Instructions for Studio Recall

## Project Overview

Studio Recall is a macOS/multiplatform SwiftUI application for creating virtual recall sheets of studio hardware. Users build sessions containing racks and 500-series chassis, populate them with devices from a library, and capture control positions (knobs, switches, buttons, lights) for each device instance.

## Core Technologies

- **Language**: Swift 5.x
- **Framework**: SwiftUI with AppKit interop
- **Platform**: macOS (primary), with iOS/tvOS support via `#if os(macOS)` conditionals
- **Build System**: Xcode project (no external package managers)
- **Persistence**: JSON files (`Codable`)

## Build and Test

### Building
- Open `Studio Recall.xcodeproj` in Xcode
- Build: Product → Run (Cmd+R)
- No external package managers or build scripts required

### Testing
- Unit tests: `Studio RecallTests` target
- UI tests: `Studio RecallUITests` target
- Run tests: Product → Test (Cmd+U)

## Code Style Guidelines

### Swift Style
- Follow Swift API Design Guidelines
- Use clear, descriptive names for types, properties, and methods
- Prefer `let` over `var` when values don't change
- Use `guard` for early exits and validation
- Use `@MainActor` for types that manage UI state

### Comments
- Don't add comments unless they match the style of other comments in the file
- Only add comments when necessary to explain complex logic or algorithms
- Prefer self-documenting code with clear naming

### Property Wrappers
- Use `@Published` for properties in `ObservableObject` classes
- Use `@State` for local view state
- Use `@EnvironmentObject` for shared managers (`SessionManager`, `DeviceLibrary`, `AppSettings`)

### Enums and Pattern Matching
- Always destructure enums in switch statements rather than accessing properties
- Provide exhaustive switch cases (no `default` when covering all cases)
- Example: `case .knob(let value):` not accessing via associated values

## Architecture Patterns

### ObservableObject Classes
Key managers are `@MainActor` `ObservableObject` types:
- `SessionManager`: manages sessions, templates, device placement
- `DeviceLibrary`: manages device definitions
- `AppSettings`: manages application preferences

### Unowned References
- `SessionManager` holds unowned reference to `DeviceLibrary` to avoid retain cycles
- Be careful with retain cycles when creating closures

### UUID-Based Lookups
- All models use `UUID` for identity
- Use `first(where: { $0.id == ... })` pattern for lookups
- Never modify IDs after creation (breaks session references)

## Data Models

### Critical Data Types
- `Device`: hardware device template with controls
- `DeviceInstance`: placed device occurrence in a session
- `Control`: interactive element (knob, button, switch, light)
- `Session`: top-level container with racks and chassis
- `Rack`: 2D grid for rack-mounted devices
- `Series500Chassis`: 1D array for 500-series modules

### Control State Management
- Controls in `Device` hold default values (template)
- Controls in `DeviceInstance.controlStates` hold actual values per instance
- Use `ControlValue.initialValue(for:)` to initialize new controls
- `ControlValue` enum wraps type-specific values: `.knob(Double)`, `.multiSwitch(Int)`, etc.

## JSON Persistence

### File Locations
- Sessions: `Documents/sessions.json`
- Library: `Documents/DeviceLibrary.json`
- Templates: `Application Support/{bundleID}/templates.json`

### Codable Requirements
- All data models must conform to `Codable`
- Always use `JSONEncoder`/`JSONDecoder`
- File I/O errors are printed but not fatal (app continues with empty state)

## Platform-Specific Code

### Conditional Compilation
Use `#if os(macOS)` for platform-specific features:
```swift
#if os(macOS)
// macOS-specific code (NSImage, NSSavePanel, etc.)
#else
// iOS/tvOS alternative (UIImage, sheets, etc.)
#endif
```

### Platform Features
- **macOS**: multi-window support, `NSImage`, `NSSavePanel`, keyboard shortcuts
- **iOS/tvOS**: single-window, `UIImage`, sheet-based library editor
- Always provide iOS/tvOS alternatives or graceful degradation

## Image Handling

### Image Storage
- Device images stored as `Data?` (PNG) in `Device.imageData`
- Use `NSImage.forceCGImage()` for robust loading (handles PDF-backed or TIFF-only NSImages)
- Consider memory impact with large images

### Auto-Detection
- `ControlAutoDetect` requires `CGImage`
- Use `forceCGImage()` to convert NSImage when needed
- Auto-detection is CPU-intensive and runs on main thread

## Testing Requirements

### Unit Tests
- Always write unit tests for new functionality
- Test `Codable` conformance for new data models
- Test state management and mutations
- Minimum coverage: comprehensive for core models and managers

### Test Patterns
- Use descriptive test method names: `testComplexShapesHaveValidPathsForHitTesting`
- Test edge cases and boundary conditions
- Verify backward compatibility for data model changes

## Security and Best Practices

### Secrets
- Never commit passwords, API keys, or secrets in code
- Use environment variables or secure storage for sensitive data

### Validation
- Validate external input and user data
- Handle file I/O errors gracefully
- Check for nil/empty values before processing

### Performance
- Consider memory impact of large image data
- Use lazy loading where appropriate
- Profile with Instruments for bottlenecks

## Common Pitfalls to Avoid

1. **Never modify device or instance IDs** after creation (breaks references)
2. **Always reconcile after device updates** to sync control states across instances
3. **Rack span writes are critical** - when updating rack instances, update ALL cells in span
4. **Coordinate systems matter** - multiple coordinate systems used (normalized, pixel, CGImage)
5. **Image data can be large** - consider memory impact when loading many devices

## Documentation

### When to Document
- Create user guides for new features
- Add technical documentation for complex implementations
- Update CLAUDE.md for significant architectural changes
- Include examples and use cases

### Documentation Guidelines
- User docs: focus on "how to use" with examples
- Technical docs: cover implementation details and design decisions
- Include visual guides (ASCII art, diagrams) where helpful

## Library Dependencies

### Approved Libraries
- Only use built-in Swift/SwiftUI/AppKit frameworks
- No external dependencies without approval
- Prefer existing functionality over adding new libraries

## Debugging

### Debug Logging
- Use `print()` with descriptive prefixes: `"AutoDetect:"`, `"SessionManager:"`
- Enable `#if DEBUG` blocks for verbose logging
- Check console for JSON encoding/decoding errors

### Common Debug Points
- `DeviceInstance.controlStates` dictionary for state persistence
- Rack placement: verify anchor calculation and span writes
- Control auto-detection: band/circle counts in console

## Other Guidelines

### Code Changes
- Make minimal, surgical modifications
- Only change what's necessary to fix the issue
- Don't refactor unrelated code
- Maintain backward compatibility for data formats

### Pull Requests
- Write clear commit messages
- Test all changes thoroughly
- Update documentation for user-facing changes
- Run full test suite before submitting
