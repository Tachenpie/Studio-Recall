applyTo:
  - Studio Recall/Managers/**
  - Studio Recall/Handlers/**

## Managers and Handlers Guidelines

### Manager Architecture

Managers are `@MainActor` `ObservableObject` classes that coordinate business logic and state:
```swift
@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var currentSession: Session?
    
    unowned let library: DeviceLibrary
    
    init(library: DeviceLibrary) {
        self.library = library
        // Load state from disk
    }
}
```

### Key Managers

#### SessionManager
Responsibilities:
- Load/save sessions to JSON
- Create/switch/delete sessions
- Place devices into racks/chassis (2D and 1D placement logic)
- Update control values on instances
- Reconcile device library changes with sessions
- Template management (save/load/apply)

Critical methods:
- `placeDevice(_:intoRack:row:col:)`: 2D rack placement
- `placeDevice(_:intoChassis:slot:)`: 500-series placement
- `setControlValue(_:value:in:session:)`: update control state
- `reconcileDevices(with:)`: sync after library updates
- `writeSpan(_:device:inSession:rackIndex:r0:c0:)`: fill device span cells

#### DeviceLibrary
Responsibilities:
- Manage device definitions
- Create device instances
- Persist library to JSON
- Track categories and metadata

Critical methods:
- `add(_:)`: add new device
- `update(_:)`: update existing device (triggers reconciliation)
- `delete(_:)`: remove device
- `device(for:)`: lookup by ID
- `createInstance(from:)`: create DeviceInstance

#### AppSettings
Responsibilities:
- Manage user preferences
- Persist settings to UserDefaults
- Provide app-wide configuration

### Main Actor Requirements

Always mark managers with `@MainActor`:
```swift
@MainActor
class MyManager: ObservableObject {
    // All methods run on main thread
}
```

This ensures:
1. UI updates happen on main thread
2. Thread-safe access to published properties
3. Consistent state management

### Unowned References

Use `unowned` to break retain cycles:
```swift
class SessionManager {
    unowned let library: DeviceLibrary  // ✅ Breaks retain cycle
}
```

**Warning**: Only use `unowned` when lifetime is guaranteed. If manager could outlive reference, use `weak` instead.

### JSON Persistence

#### Saving
```swift
func save() {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted  // For readability
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL)
    } catch {
        print("SessionManager: Failed to save - \(error)")
        // Don't throw - app continues with in-memory state
    }
}
```

#### Loading
```swift
func load() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        print("SessionManager: No saved data found")
        return
    }
    
    do {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        sessions = try decoder.decode([Session].self, from: data)
    } catch {
        print("SessionManager: Failed to load - \(error)")
        // Continue with empty state
    }
}
```

### Device Placement Logic

#### Rack Placement (2D)
```swift
func placeDevice(_ device: Device, intoRack rack: Rack, 
                 row: Int, col: Int, in session: Session) -> Bool {
    // 1. Validate placement bounds
    guard canPlace(device, at: row, col, in: rack) else {
        return false
    }
    
    // 2. Create instance
    let instance = library.createInstance(from: device)
    
    // 3. Write to all cells in span
    writeSpan(instance, device: device, 
             inSession: session, rackIndex: rackIndex,
             r0: row, c0: col)
    
    // 4. Save changes
    save()
    return true
}
```

Important: Device spans multiple cells based on `rackUnits` (height) and `rackWidth` (columns). ALL cells in span must reference the same instance.

#### Series500 Chassis Placement (1D)
```swift
func placeDevice(_ device: Device, intoChassis chassis: Series500Chassis,
                 slot: Int) -> Bool {
    // 1. Validate device type
    guard device.type == .series500 else { return false }
    
    // 2. Check slot availability
    guard chassis.slots[slot] == nil else { return false }
    
    // 3. Create and place instance
    let instance = library.createInstance(from: device)
    chassis.slots[slot] = instance
    
    // 4. Save changes
    save()
    return true
}
```

### Control Value Updates

```swift
func setControlValue(_ controlID: UUID, value: ControlValue,
                    in instanceID: UUID, session: Session) {
    // 1. Find instance
    guard let instance = session.findInstance(instanceID) else { return }
    
    // 2. Update control state
    instance.controlStates[controlID] = value
    
    // 3. Persist immediately
    save()
    
    // 4. Notify observers
    objectWillChange.send()
}
```

### Device Reconciliation

When device definition changes, reconcile all instances:
```swift
func reconcileDevices(with updatedDevice: Device) {
    for session in sessions {
        for instance in session.allInstances where instance.deviceID == updatedDevice.id {
            // Migrate control states to match new definition
            migrateControlStates(instance, to: updatedDevice)
        }
    }
    save()
}

func migrateControlStates(_ instance: DeviceInstance, to device: Device) {
    var newStates: [UUID: ControlValue] = [:]
    
    // Keep existing states for controls that still exist
    for control in device.controls {
        if let existing = instance.controlStates[control.id] {
            newStates[control.id] = existing
        } else {
            // Initialize new controls with defaults
            newStates[control.id] = ControlValue.initialValue(for: control.type)
        }
    }
    
    instance.controlStates = newStates
}
```

### Handler Patterns

Handlers encapsulate specific operations or algorithms:

#### ControlAutoDetect Handler
```swift
struct ControlAutoDetect {
    static func detect(on image: NSImage, 
                      config: Config) -> [ControlDraft] {
        // 1. Preprocess image
        let processed = preprocess(image, config: config)
        
        // 2. Detect bands (horizontal rows of controls)
        let bands = detectBands(in: processed, config: config)
        
        // 3. Find controls in each band
        let drafts = bands.flatMap { findControls(in: $0, config: config) }
        
        // 4. Post-process and deduplicate
        return postProcess(drafts, config: config)
    }
}
```

Handler functions should be:
- Pure when possible (no side effects)
- Well-documented with clear inputs/outputs
- Testable in isolation
- Efficient (especially for CPU-intensive operations)

### Error Handling

#### Graceful Degradation
```swift
func loadSession(at url: URL) {
    do {
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(Session.self, from: data)
        sessions.append(session)
    } catch {
        print("SessionManager: Failed to load session - \(error)")
        // App continues without this session
        // User can be notified via alert
    }
}
```

#### Critical Errors
For errors that prevent operation, use `assertionFailure` in debug:
```swift
func updateInstance(_ id: UUID) {
    guard let instance = findInstance(id) else {
        assertionFailure("Instance not found: \(id)")
        return
    }
    // ...
}
```

### State Updates

#### Publishing Changes
```swift
@Published var sessions: [Session] = [] {
    didSet {
        save()  // Auto-save on changes
    }
}
```

#### Explicit Notifications
```swift
func updateControlValue() {
    // Make changes
    instance.controlStates[id] = value
    
    // Explicitly notify observers
    objectWillChange.send()
}
```

### Performance Considerations

#### Batch Operations
```swift
func updateMultipleDevices(_ devices: [Device]) {
    // Disable auto-save during batch
    for device in devices {
        library.update(device, notifyChanges: false)
    }
    
    // Save once at end
    save()
    objectWillChange.send()
}
```

#### Lazy Initialization
```swift
lazy var templateManager: TemplateManager = {
    TemplateManager(fileURL: templateFileURL)
}()
```

### Testing Managers

Create test doubles for integration tests:
```swift
class TestSessionManager: SessionManager {
    var saveCalled = false
    
    override func save() {
        saveCalled = true
        // Don't actually write to disk in tests
    }
}
```

### Debug Logging

Use consistent prefixes for debug output:
```swift
func placeDevice() {
    print("SessionManager: Placing device \(device.name) at \(row), \(col)")
    // ...
}
```

Enable verbose logging with `#if DEBUG` blocks:
```swift
#if DEBUG
print("SessionManager: Grid state after placement:")
print(rack.grid)
#endif
```

### Common Pitfalls

1. **Forgetting to save**: Always call `save()` after state changes
2. **Not reconciling**: Call `reconcileDevices()` after device updates
3. **Incomplete spans**: Update ALL cells when placing rack devices
4. **Thread safety**: Always use `@MainActor` for UI-related managers
5. **Retain cycles**: Use `unowned`/`weak` for cross-references
