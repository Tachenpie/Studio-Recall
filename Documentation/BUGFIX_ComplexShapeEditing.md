# Bug Fix: Complex Control Shapes Not Outlined/Editable

## Issue
When a new complex control shape (chickenhead, knurl, dLine, trianglePointer, arrowPointer) was selected in the region editor dropdown, the region was not properly outlined or editable in the FaceplateCanvas.

## Root Cause
The problem was in two locations:

1. **FaceplateCanvas.swift**: When creating `RegionHitLayer` instances, the `maskParams` from the region were not being passed along.
2. **RegionHitLayer.swift**: When creating `RegionClipShape` instances for hit testing, the `maskParams` parameter was not being used, even though it was accepted as a parameter.

This meant that complex shapes requiring parametric configuration (via `maskParams`) would fall back to simpler shapes or fail to render properly in the editor.

## Solution

### Changes Made

#### 1. FaceplateCanvas.swift (Line 153)
Added `maskParams` parameter when creating `RegionHitLayer`:

```swift
RegionHitLayer(
    rect: ...,
    parentSize: parentSize,
    canvasSize: canvasSize,
    zoom: zoom,
    pan: pan,
    isPanMode: isPanMode,
    shape: sel.wrappedValue.regions[idx].shape,
    maskParams: sel.wrappedValue.regions[idx].maskParams,  // ✅ ADDED
    controlType: sel.wrappedValue.type,
    regionIndex: idx,
    regions: sel.wrappedValue.regions,
    isEnabled: activeRegionIndex == idx
)
```

#### 2. RegionHitLayer.swift (Lines 83, 87)
Updated `RegionClipShape` initialization to use `maskParams`:

```swift
RegionClipShape(shape: shape, maskParams: maskParams)  // ✅ ADDED maskParams
    .fill(Color.clear)
    .frame(width: localSize.width, height: localSize.height)
    .position(x: regionFrame.midX, y: regionFrame.midY)
    .contentShape(RegionClipShape(shape: shape, maskParams: maskParams))  // ✅ ADDED maskParams
    .gesture(...)
    .allowsHitTesting(isEnabled && !isPanMode)
```

### Tests Added

#### ControlShapeTests.swift
Added two new tests to verify the fix:

1. **testComplexShapesHaveValidPathsForHitTesting**: Verifies that all complex shapes generate valid paths when `maskParams` are provided
2. **testRegionWithComplexShapeAndMaskParamsIsEditable**: Verifies that regions with complex shapes and maskParams retain all properties through serialization

## Impact

### Before Fix
- Complex shapes (chickenhead, knurl, dLine, trianglePointer, arrowPointer) would not display proper outlines in the region editor
- Hit testing for these shapes would not work correctly, making them uneditable
- Users could not resize or move regions with complex shapes

### After Fix
- All complex shapes are properly outlined in the FaceplateCanvas
- Hit testing works correctly for all complex shapes
- Users can resize, move, and edit regions with complex shapes just like basic shapes
- Full compatibility maintained with existing basic shapes (rect, circle, wedge, line, dot, pointer)

## Compatibility
- ✅ Backward compatible with existing device definitions
- ✅ No changes to data model or serialization format
- ✅ Existing tests continue to pass
- ✅ Works with all existing control types (knob, steppedKnob, multiSwitch, button, light, concentricKnob, litButton)

## Related Files
- `Studio Recall/Views/Controls/FaceplateCanvas.swift`
- `Studio Recall/Views/Controls/RegionHitLayer.swift`
- `Studio Recall/Views/Controls/RegionOverlay.swift` (already correct, used as reference)
- `Studio Recall/Handlers/RegionClipShape.swift` (no changes needed)
- `Studio RecallTests/ControlShapeTests.swift` (tests added)

## Testing
Run the unit tests to verify:
```bash
# In Xcode
Product → Test (Cmd+U)

# Or specifically:
# Test target: Studio RecallTests
# Test suite: ControlShapeTests
```

## Related Documentation
- [ComplexControlShapes.md](ComplexControlShapes.md) - User guide for complex shapes
- [ComplexShapes_VisualGuide.md](ComplexShapes_VisualGuide.md) - Visual reference
- [CHANGELOG_ComplexShapes.md](CHANGELOG_ComplexShapes.md) - Implementation details
