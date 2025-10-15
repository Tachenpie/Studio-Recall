# Marching Ants and Shape Manipulation Features

## Overview

This document describes the marching ants overlay and direct manipulation features for control regions and shape instances in Studio Recall.

## Features

### 1. Animated Marching Ants

The marching ants provide visual feedback for selected regions and shape instances, similar to professional graphics software like Photoshop and Illustrator.

#### Implementation Details

- **Animation Duration**: 0.5 seconds per cycle
- **Animation Style**: Linear, repeating indefinitely
- **Visual Pattern**: Alternating black and white dashes that "march" around the selected shape
- **Zoom Adaptive**: Dash size and spacing scale with zoom level for consistent appearance

#### Affected Components

- `RegionOverlay.swift`: Shows marching ants around selected regions
- `ShapeInstanceOverlay.swift`: Shows marching ants around selected shape instances

### 2. Direct Shape Manipulation

Users can directly manipulate regions and shape instances in the canvas without using sliders.

#### Available Operations

##### Movement
- **Action**: Click and drag anywhere inside the shape
- **Behavior**: Moves the entire shape
- **Constraints**: Position constrained to valid bounds (0-1 normalized coordinates)
- **Visual Feedback**: Real-time preview while dragging

##### Resizing - Corner Handles
- **Action**: Click and drag any of the 4 corner handles
- **Behavior**: 
  - **Circles**: Maintains aspect ratio (square bounds)
  - **Rectangles/Triangles**: Independent width and height adjustment
- **Anchor Point**: Opposite corner remains fixed
- **Minimum Size**: 5% of region to prevent collapse

##### Resizing - Edge Handles
- **Action**: Click and drag any of the 4 edge handles (top, bottom, left, right)
- **Availability**: Only for rectangles and triangles (not circles)
- **Behavior**: Adjusts size along one axis only
- **Anchor Point**: Opposite edge remains fixed

##### Rotation
- **Action**: Click and drag the circular rotation handle above the shape
- **Behavior**: Rotates shape around its center
- **Angle Calculation**: Based on cursor position relative to shape center
- **Range**: 0-360 degrees (wraps around)
- **Reference**: 0° points upward

### 3. Dynamic Updates

All overlays and handles update in real-time as shapes are moved or resized.

#### Update Mechanism

- **SwiftUI Bindings**: All shape data is bound to the UI using `@Binding`
- **Automatic Refresh**: Changes to position, size, or rotation immediately update the overlay
- **Zoom/Pan Compatibility**: Overlays and hit areas adjust correctly at all zoom levels and pan positions

#### Coordinate Systems

The implementation handles three coordinate systems seamlessly:

1. **Normalized Space (0-1)**: Shape data storage in the model
2. **Canvas Pixel Space**: Visual rendering and overlay positioning
3. **Parent (Viewport) Space**: Hit testing with zoom and pan transformations

### 4. Visual Handles

Selected shapes display visual handles for manipulation:

#### Corner Handles
- **Count**: 4 (top-left, top-right, bottom-left, bottom-right)
- **Appearance**: Small white squares with black border
- **Size**: 8 pixels (screen space), scales with zoom
- **Availability**: All shape types

#### Edge Handles
- **Count**: 4 (top, bottom, left, right)
- **Appearance**: Same as corner handles
- **Size**: 8 pixels (screen space), scales with zoom
- **Availability**: Rectangles and triangles only (not circles)

#### Rotation Handle
- **Appearance**: Small white circle with black border
- **Position**: 20 pixels above the shape (screen space)
- **Connection**: Dashed line connects to shape
- **Availability**: All shape types

### 5. Shape-Specific Behavior

#### Circles
- **Corner Resizing**: Maintains square aspect ratio
- **Edge Resizing**: Available, adjusts single axis while keeping other axis fixed
- **Edge Handles**: Hidden in overlay, but edge resizing still functional via hit layer
- **Rotation**: Supported (useful for positioning visual elements)

#### Rectangles
- **Corner Resizing**: Independent width and height adjustment
- **Edge Resizing**: Single axis adjustment
- **Edge Handles**: Visible in overlay
- **Rotation**: Supported

#### Triangles
- **Corner Resizing**: Independent width and height adjustment
- **Edge Resizing**: Single axis adjustment
- **Edge Handles**: Visible in overlay
- **Rotation**: Supported (changes triangle orientation)

## Usage Guide

### Selecting a Shape

1. Enter edit mode for a control
2. Click on any shape instance or region
3. Marching ants and handles appear immediately

### Moving a Shape

1. Select the shape
2. Click and drag anywhere inside the shape (avoiding handles)
3. Release to complete the move

### Resizing with Corners

1. Select the shape
2. Click and drag any corner handle
3. For circles: maintains square aspect ratio
4. For rectangles/triangles: adjusts both width and height
5. Release to complete the resize

### Resizing with Edges

1. Select a rectangle or triangle (not available for circles)
2. Click and drag any edge handle (top, bottom, left, right)
3. Adjusts only the dimension perpendicular to the edge
4. Release to complete the resize

### Rotating a Shape

1. Select the shape
2. Click and drag the rotation handle (circle above the shape)
3. Rotate around the shape center
4. Release to complete the rotation

## Testing

### Manual Testing Checklist

**Note**: This is a template checklist for QA testing. Record results in your test tracking system.

**Visual Appearance**:
- [ ] Marching ants animate smoothly at default zoom
- [ ] Marching ants remain visible at 50% zoom
- [ ] Marching ants remain visible at 200% zoom
- [ ] Corner handles appear for all shape types
- [ ] Edge handles appear only for rectangles and triangles
- [ ] Edge handles hidden for circles
- [ ] Rotation handle appears for all shape types

**Interaction**:
- [ ] Movement works smoothly
- [ ] Corner resize works for all shapes
- [ ] Edge resize works for rectangles and triangles
- [ ] Edge resize not available for circles
- [ ] Rotation works smoothly
- [ ] Handles scale correctly with zoom

**Dynamic Updates**:
- [ ] Overlay updates during movement
- [ ] Overlay updates during resize
- [ ] Overlay updates during rotation

### Automated Tests

See `Studio RecallTests/ControlShapeTests.swift`:

- `testShapeInstanceHasCorrectProperties`: Verifies shape instance creation
- `testShapeInstanceCodableRoundTrip`: Tests JSON encoding/decoding
- `testRegionWithMultipleShapeInstances`: Tests multiple instances
- `testAllShapesHaveValidBoundsForHitTesting`: Validates bounds for all shapes

## Technical Implementation

### Animation Architecture

```swift
@State private var dashPhase: CGFloat = 0

// In body:
.onAppear {
    let dashUnit: CGFloat = 6.0 / zoom  // Match the dash pattern unit (defined as 6.0 / zoom in body)
    // Duration: 0.5s chosen for smooth, perceptible motion (not too fast, not too slow)
    // dashUnit * 2: Complete cycle through one black dash + one white dash
    withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
        dashPhase = dashUnit * 2
    }
}

// In stroke:
.stroke(.white, style: StrokeStyle(
    lineWidth: hair, 
    dash: dash, 
    dashPhase: dashPhase  // Animated value (oscillates between 0 and dashUnit*2)
))
```

### Binding Updates

```swift
// Overlay binding
RegionOverlay(
    rect: Binding(
        get: { sel.wrappedValue.regions[idx].rect },
        set: { updateRegionRect(of: sel, to: $0, idx: idx) }
    ),
    ...
)

// Hit layer binding
RegionHitLayer(
    rect: Binding(
        get: { sel.wrappedValue.regions[idx].rect },
        set: { updateRegionRect(of: sel, to: $0, idx: idx) }
    ),
    ...
)
```

## Performance

- **Animation Overhead**: Minimal - simple linear interpolation
- **Rendering**: Efficient - uses native SwiftUI Path and stroke
- **Hit Testing**: Optimized - uses contentShape for precise hit areas
- **Zoom Scaling**: Consistent performance at all zoom levels

## Compatibility

- **Platform**: macOS (primary target)
- **iOS/tvOS**: Requires touch gesture adaptation (not currently implemented)
- **Backward Compatibility**: 100% - no changes to data models
- **Existing Sessions**: All existing sessions work without modification

## Future Enhancements

1. **Keyboard Modifiers**
   - Shift: Constrain movement/rotation
   - Option/Alt: Duplicate while dragging
   - Command: Fine control mode

2. **Snap-to-Grid**
   - Optional grid snapping
   - Angle snapping (15°, 45°, etc.)

3. **Multi-Selection**
   - Select multiple shapes
   - Group operations

4. **Visual Feedback**
   - Distance indicators
   - Alignment guides
   - Dimension tooltips

## Conclusion

The marching ants and direct manipulation features provide a professional, intuitive editing experience for control regions and shape instances. The implementation is robust, performant, and maintains full backward compatibility with existing sessions.
