# Shape Instance Direct Manipulation

## Overview

This feature enables direct manipulation of individual shape instances within control regions, eliminating the need for slider-based adjustments in the inspector.

## User Interface

### Visual Feedback

When editing a region with shape instances:

1. **Marching Ants Outline**: Each selected shape instance displays a dashed black/white outline (marching ants effect) that follows the actual shape geometry (circle, rectangle, or triangle).

2. **Resize Handles**: Eight white square handles appear around the selected shape:
   - 4 corner handles (always visible)
   - 4 edge handles (visible for rectangles and triangles, not for circles)

3. **Rotation Handle**: A circular handle appears above the shape, connected by a dashed line, for rotating the shape.

### Interaction

#### Selecting a Shape Instance
- Click on any shape instance in the canvas to select it
- The selected shape displays marching ants outline and manipulation handles
- Only one shape instance can be selected at a time

#### Moving
- Click and drag anywhere inside the shape to move it
- Position is constrained to remain within the region (0-1 normalized coordinates)

#### Resizing
- **Corner handles**: Drag to resize from that corner
  - For circles: maintains square aspect ratio (equal width and height)
  - For rectangles and triangles: independent width/height adjustment
- **Edge handles**: Drag to resize along that axis
  - Only available for rectangles and triangles
  - Adjusts width (left/right handles) or height (top/bottom handles)
- Minimum size is enforced (5% of region size)
- Maximum size is capped at region boundaries

#### Rotating
- Drag the rotation handle (circle above the shape) to rotate
- Rotation angle is calculated from the shape center to cursor position
- 0° points upward
- Rotation range: 0-360°

## Technical Implementation

### Components

1. **ShapeInstanceOverlay.swift**
   - Visual-only overlay rendered in canvas space
   - Shows marching ants outline using dashed strokes with phase offset
   - Renders manipulation handles (corners, edges, rotation)
   - Automatically rotates with the shape instance

2. **ShapeInstanceHitLayer.swift**
   - Interactive layer rendered in parent (viewport) space
   - Handles drag gestures for move, resize, and rotate operations
   - Manages selection state via callback
   - Supports only selected shapes for editing
   - All shapes respond to selection clicks

3. **FaceplateCanvas.swift Integration**
   - Tracks selected shape instance via `selectedShapeInstanceId` state
   - Creates overlay and hit layer for each shape instance in the active region
   - Binds shape instance data for live updates
   - Coordinates between canvas and parent coordinate systems

### Coordinate Systems

Multiple coordinate systems are involved:

1. **Normalized Region Space (0-1)**: Shape instance position and size
2. **Canvas Pixel Space**: Region rect and shape calculations
3. **Parent (Viewport) Space**: Hit testing and gesture handling with zoom/pan

Conversions are handled automatically by each layer.

### Data Model

No changes to the data model were required. The existing `ShapeInstance` struct already supports:
- `position: CGPoint` - center position in region space (0-1)
- `size: CGSize` - dimensions in region space (0-1)  
- `rotation: Double` - angle in degrees (0-360)

## User Workflow

### Basic Usage

1. Select a control and enable "Edit Region" mode
2. Ensure the region has at least one shape instance
3. Click on a shape instance in the canvas to select it
4. Use the handles to adjust position, size, and rotation
5. Click another shape instance to switch selection
6. Changes are saved automatically

### Creating New Shapes

1. In the Control Inspector, click "Add Shape"
2. Select the shape type (circle, rectangle, triangle)
3. The new shape appears centered in the region
4. Click it in the canvas to select and adjust

### Removing Shapes

- Use the "Remove" button in the Control Inspector for each shape
- Cannot manipulate deleted shapes

## Design Decisions

### Why Remove Sliders?

1. **Direct Manipulation is More Intuitive**: Users can see immediate visual feedback while adjusting
2. **Reduces Inspector Clutter**: The inspector was becoming too crowded with sliders for each shape
3. **Better Spatial Understanding**: Working directly in the canvas helps users understand positioning in context
4. **Consistent with Region Editing**: Matches the existing paradigm for region rect manipulation

### Why Marching Ants?

1. **Visual Clarity**: Clearly indicates which shape is selected
2. **Professional Standard**: Common pattern in graphics software (Photoshop, Illustrator, etc.)
3. **Works on Any Background**: The black/white dashed pattern is visible regardless of underlying colors
4. **Follows Shape Geometry**: Accurately represents the clickable area

### Why Selection Before Editing?

1. **Prevents Accidental Edits**: Users must explicitly select a shape before modifying it
2. **Multiple Shapes Support**: Allows working with multiple overlapping shapes without confusion
3. **Clear Feedback**: User always knows which shape will be affected by their actions

## Compatibility

### Backward Compatibility

- No changes to JSON structure or data models
- Existing sessions with shape instances work unchanged
- Slider-based editing approach can be restored if needed (code is commented, not removed)

### Cross-Platform

- Works on macOS (primary target)
- iOS/tvOS support requires touch gesture adaptation (not currently implemented)

## Testing

Tests have been added to verify:
1. Shape instance creation and property persistence
2. JSON encoding/decoding of shape instances
3. Multiple shape instances in a region
4. Shape instance array manipulation

Additional UI testing is recommended for:
- Gesture handling
- Coordinate system conversions
- Handle hit detection
- Rotation angle calculations

## Future Enhancements

Possible improvements:
1. **Keyboard Modifiers**
   - Hold Shift for constrained movement (horizontal/vertical only)
   - Hold Option/Alt for duplicate-drag
   - Hold Command for fine-tuning (slower drag speed)

2. **Snap-to-Grid**
   - Optional snapping to region grid lines
   - Snap rotation to 15° or 45° increments with modifier key

3. **Multi-Selection**
   - Select multiple shape instances at once
   - Group move/resize operations

4. **Alignment Tools**
   - Align selected shapes to center, edges
   - Distribute shapes evenly

5. **Numeric Input**
   - Optional inspector fields for precise numeric values
   - Combine slider-free design with optional precision input

## Known Limitations

1. **Touch Interface**: Not optimized for touch input (iPad)
2. **Very Small Shapes**: Handles may overlap on tiny shapes
3. **High Zoom Levels**: Handle sizing may need adjustment at extreme zoom
4. **Rotation Handle Visibility**: May be off-screen if shape is near top edge

## Migration Notes

### For Users

- No action required! Existing shape instances work as before
- Sliders have been removed from the inspector
- Use direct manipulation in the canvas instead

### For Developers

- Two new view files: `ShapeInstanceOverlay.swift` and `ShapeInstanceHitLayer.swift`
- `FaceplateCanvas.swift` tracks `selectedShapeInstanceId` state
- `ControlInspector.swift` simplified (sliders removed)
- Tests updated in `ControlShapeTests.swift`

---

**Note**: This feature integrates seamlessly with the simplified shapes system. The core shape rendering, color matching, and masking functionality remains unchanged.
