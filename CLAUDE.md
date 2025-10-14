# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Studio Recall** is a macOS/multiplatform SwiftUI application for creating virtual recall sheets of studio hardware. Users build sessions containing racks and 500-series chassis, populate them with devices from a library, and capture control positions (knobs, switches, buttons, lights) for each device instance.

## Build and Development

### Building
- Open `Studio Recall.xcodeproj` in Xcode
- Build and run the project directly from Xcode (Product → Run or Cmd+R)
- No external package managers or build scripts are used

### Testing
- Test targets are available in Xcode:
  - `Studio RecallTests` - unit tests
  - `Studio RecallUITests` - UI tests
- Run tests via Product → Test (Cmd+U)

### Project Structure
- Platform: macOS (primary), with cross-platform support via `#if os(macOS)` conditionals
- Framework: SwiftUI with AppKit interop
- Persistence: JSON files in Documents directory (`sessions.json`, `DeviceLibrary.json`)
- Templates stored in Application Support directory (`templates.json`)

## Architecture

### Core Data Models

**Device** (`Models/Device.swift`)
- Represents a hardware device definition in the library
- Types: `.rack` (19" rack gear) or `.series500` (500-series modules)
- Contains: metadata (name, categories, image), physical sizing (rack units, slot width), and a collection of `Control` objects
- Devices are templates; actual instances are `DeviceInstance`

**DeviceInstance** (`Models/DeviceInstance.swift`)
- A placed occurrence of a Device within a session
- Stores per-instance control states via `controlStates: [UUID: ControlValue]`
- Each instance has unique ID but references library Device by `deviceID`

**Control** (`Models/Controls.swift`)
- Defines interactive elements on device faceplates
- Types: `.knob`, `.steppedKnob`, `.multiSwitch`, `.button`, `.light`, `.concentricKnob`, `.litButton`
- Stores position (`x`, `y` normalized 0-1), visual regions (`ImageRegion`), and mappings (`VisualMapping`)
- Visual mappings control rendering: rotation, brightness, opacity, translation, 3D flip, sprite frames

**Session** (`Models/Session.swift`)
- Top-level container for a recall sheet
- Contains arrays of `Rack` and `Series500Chassis` objects
- Each session stores canvas state (zoom, pan) and labels

**Rack** (`Models/Rack.swift`)
- 2D grid structure: rows × 6 columns (using `RackGrid.columnsPerRow`)
- Devices span multiple cells based on `rackUnits` (height) and `rackWidth` enum (full=6, half=3, third=2)
- Grid uses `[[DeviceInstance?]]` — instances are replicated across their span

**Series500Chassis** (`Models/Series500Chassis.swift`)
- 1D array of slots for 500-series modules
- Simpler than racks: `slots: [DeviceInstance?]`

### Manager Classes

**SessionManager** (`Managers/SessionManager.swift`)
- `@MainActor` `ObservableObject` managing all sessions and templates
- Responsibilities:
  - Load/save sessions to JSON
  - Create/switch/delete sessions
  - Place devices into racks/chassis (2D and 1D placement logic)
  - Update control values on instances (`setControlValue`, `updateValueAndSave`)
  - Reconcile device library changes with existing sessions (`reconcileDevices`, `migrateControlStatesToMatchLibrary`)
  - Template management (save/load/apply)
- Requires `DeviceLibrary` reference (unowned) to resolve device definitions
- Important methods:
  - `placeDevice(_:intoRack:row:col:)` for 2D rack placement (uses span logic)
  - `placeDevice(_:intoChassis:slot:)` for 500-series placement
  - `writeSpan(_:device:inSession:rackIndex:r0:c0:)` fills multi-cell device spans
  - `anchor(of:in:)` finds the top-left cell of a device in a rack

**DeviceLibrary** (`Models/DeviceLibrary.swift`)
- `@MainActor` `ObservableObject` for device library management
- Persists to `DeviceLibrary.json` in Documents
- Methods: `add`, `update`, `delete`, `device(for:)`, `createInstance`
- When updating a device, optionally calls `sessionManager.reconcileDevices(with:)` to sync sessions

### Control Auto-Detection

**ControlAutoDetect** (`Handlers/ControlAutoDetect.swift`)
- Image analysis pipeline for detecting knobs, buttons, and lights on device faceplates
- Entry point: `ControlAutoDetect.detect(on: NSImage, config: Config) -> [ControlDraft]`
- Pipeline stages:
  1. Preprocess: downscale, edge detection (CILineOverlay), percentile masking
  2. Band detection: identifies horizontal rows of controls via edge density histogram
  3. Blob pass: connected components for buttons, switches, rough circles
  4. Circle finder pass: Hough-like circle detection per band
  5. Promotions: concentric knobs, lit buttons (structural pattern matching)
  6. Post-filters: size clamping, column clustering, artifact removal
  7. NMS + deduplication
  8. Column reconciliation across bands
- Returns `ControlDraft` objects (pixel-space rects + centers) which are converted to normalized `Control` objects
- Config tuning: `Config.fromSensitivity(_:)` creates preset from 0-1 slider (higher = more recall, looser thresholds)

### Coordinate Systems

**Critical:** Multiple coordinate systems are used throughout:

1. **Normalized (0-1) device space**: Control positions stored as `x`, `y` in `Control` model
2. **Top-left pixel space**: Used for `ControlDraft.rect` and `ControlDraft.center` from auto-detection
3. **Bottom-left CGImage space**: Core Image and some CoreGraphics operations
4. **Scaled-space**: Downscaled images for edge detection and band computation

When working with control positioning or auto-detection:
- `flipY(_:srcHf:)` helpers convert between top-left and bottom-left Y coordinates
- Auto-detection returns top-left pixel coordinates which must be normalized to device space
- Visual mappings (`VisualMapping`) work in normalized region space (0-1 of region bounds)

### Visual Mapping System

Controls render dynamically based on their values via `VisualMapping`:
- **Rotate**: maps value to rotation angle (degMin, degMax, pivot point)
- **Brightness/Opacity**: scalar mapping with optional taper (linear, decibel)
- **Translate**: moves region from transStart to transEnd
- **Flip3D**: 3D tilt effect with perspective transform
- **Sprite**: frame-based animation (atlas grid or individual frames)

Each control can have multiple `ImageRegion` objects (for concentric knobs: outer and inner rings). Each region has its own mapping.

Tapers (`.linear`, `.decibel`) affect how normalized values map to semantic ranges (e.g., dB scales with `-∞` support via `Bound.negInfinity`).

### Drag & Drop

**DragPayload** (`Models/DragPayload.swift`) - codable payload for device dragging
**Drop Delegates**:
- `ControlDropDelegate`: handles control placement on faceplates
- `ChassisDropDelegate`, `Series500DropDelegate`: handle device drops into racks/chassis
- `RackPlacement`: utility for finding valid rack placement positions

### Render Modes

**RenderStyle** enum (in `Handlers/RenderStyle.swift` or inline):
- `.photoreal`: renders actual device images with overlaid controls
- `.representative`: simplified, diagrammatic view using control glyphs

Representative mode uses synthetic control graphics (drawn circles, arcs, gizmos) instead of image patches.

## Data Flow

1. **Device Creation**: User creates `Device` in library editor, adds image, defines controls (manually or via auto-detect)
2. **Control Detection**: User uploads faceplate image → `ControlAutoDetect.detect()` → drafts → user reviews/edits → converts to `Control` objects
3. **Session Building**: User creates `Session`, adds `Rack`/`Series500Chassis`, drags devices from library into slots
4. **Instance Creation**: `SessionManager.placeDevice()` creates `DeviceInstance` with initialized `controlStates` from device defaults
5. **Control Updates**: User interacts with controls in session view → `SessionManager.setControlValue()` → updates instance state → persists to JSON
6. **Library Sync**: If device definition changes (controls added/removed), `SessionManager.migrateControlStatesToMatchLibrary()` reconciles all instances

## Key Conventions

### Control State Management

- Controls in `Device` hold *default* values (template definition)
- Controls in `DeviceInstance.controlStates` hold *actual* values per instance
- `ControlValue` enum wraps type-specific values (`.knob(Double)`, `.multiSwitch(Int)`, etc.)
- Always initialize new controls via `ControlValue.initialValue(for:)` to ensure type safety

### Rack Grid Logic

Racks are 2D grids where devices can span multiple cells:
- Width: determined by `RackWidth` enum (6 columns for full-width, 3 for half, 2 for third)
- Height: determined by `rackUnits` (1U, 2U, etc.)
- **Anchor cell**: top-left position of device's span
- When updating an instance in a rack, must update ALL cells in its span via `writeSpan()`
- Use `isAnchor()` and `anchor(of:in:)` helpers to avoid processing duplicates

### JSON Persistence

- Sessions: `Documents/sessions.json` (entire sessions array)
- Library: `Documents/DeviceLibrary.json` (devices + instances)
- Templates: `Application Support/{bundleID}/templates.json`
- Always use `JSONEncoder`/`JSONDecoder` with Swift `Codable`
- File I/O errors are printed but not fatal (app continues with empty state)

### Image Handling

- Device images stored as `Data?` (PNG) in `Device.imageData`
- NSImage/CGImage conversions via `NSImage.forceCGImage()` for robust loading
- Auto-detection requires CGImage; use `forceCGImage()` to handle PDF-backed or TIFF-only NSImages
- Sprite frames in visual mappings can be embedded PNG data or references to `SpriteLibrary`

## Common Tasks

### Adding a New Control Type

1. Add case to `ControlType` enum in `Controls.swift`
2. Add corresponding case to `ControlValue` enum
3. Update `ControlValue.initialValue(for:)` with default value
4. Add rendering logic in control view components
5. Update auto-detection classifier (if detectable) in `ControlAutoDetect.blobPass()` or classification logic

### Modifying Auto-Detection Sensitivity

- Tune `ControlAutoDetect.Config` parameters
- Use `Config.fromSensitivity(_:)` factory for user-facing slider (0-1 range)
- Key params: `covBase`, `aliBase`, `contrastFloor` (radial agreement), `bandPadFrac`, `bandMaxRFrac` (band sizing)
- Debug by enabling `#if DEBUG` blocks and reviewing console output for band/circle counts

### Adding Device Categories

- Categories are simple `[String]` arrays on `Device`
- Managed via `CategoryEditor` view
- Library maintains `categories: Set<String>` derived from all devices
- No predefined list; purely user-defined tags

### Working with Templates

- Templates are `SessionTemplate` wrapping a `Session` snapshot
- `Session.skeletonizedForTemplate()` optionally strips transient data
- `Session.snapshotWithNewIDs()` generates fresh UUIDs for racks/chassis/labels when instantiating
- Default template ID stored in UserDefaults as `"DefaultTemplateID"`

## Platform Differences

Code uses `#if os(macOS)` conditionals for platform-specific features:
- macOS: multi-window support (`WindowGroup(id:)`), `NSImage`, `NSSavePanel`, keyboard shortcuts
- iOS/tvOS: single-window, `UIImage`, sheet-based library editor
- Cross-platform: Core SwiftUI views, models, and managers

When adding platform-specific code, always provide iOS/tvOS alternative or graceful degradation.

## Debugging Tips

- Enable `DEBUG` blocks in `ControlAutoDetect.swift` for verbose detection logging
- Check console for JSON encoding/decoding errors on load/save
- Use `print()` statements with descriptive prefixes (e.g., `"AutoDetect:"`, `"SessionManager:"`)
- Inspect `DeviceInstance.controlStates` dictionary to verify state persistence
- For rack placement issues, verify anchor calculation and span writes with debug output

## Known Patterns

- **EditableDevice**: wrapper around `Device` for real-time editing with revision tracking (`bumpRevision()`)
- **ControlValue pattern matching**: always destructure enum in switch statements rather than accessing properties
- **Unowned references**: `SessionManager` holds unowned ref to `DeviceLibrary` (avoid retain cycles)
- **EnvironmentObject injection**: `SessionManager`, `DeviceLibrary`, `AppSettings` injected at root level
- **UUID-based lookups**: all models use `UUID` for identity; use `first(where: { $0.id == ... })` pattern

## Important Notes

- **Never modify device IDs or instance IDs** after creation (breaks session references)
- **Always reconcile after device updates** to sync control states across instances
- **Span writes are critical** for rack grid integrity (missing a cell breaks rendering)
- **Image data can be large** — consider memory impact when loading many devices
- **Auto-detection is CPU-intensive** — runs on main thread; consider async wrapper for large images
