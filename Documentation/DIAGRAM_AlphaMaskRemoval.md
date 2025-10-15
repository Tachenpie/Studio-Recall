# Visual Diagram: Alpha Mask System Removal

## Before: Confusing Two-Path System

```
┌─────────────────────────────────────────────────────────────────┐
│ ControlInspector UI                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Shape Picker:                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ○ Rectangle  ○ Circle  ○ Chickenhead  ○ Knurl ...       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  [✓] Use Alpha Mask (Carved Pointer)  ← CONFUSING!            │
│                                                                 │
│  IF alpha mask enabled:                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Mask Parameters                                          │  │
│  │                                                          │  │
│  │ Pointer Style: [Line▼] ← REDUNDANT with Shape Picker!  │  │
│  │ Angle Offset: [-90°]                                    │  │
│  │ Width: [0.1]                                            │  │
│  │ Inner Radius: [0.0]                                     │  │
│  │ Outer Radius: [1.0]                                     │  │
│  │                                                          │  │
│  │ [Apply Mask to Control] ← Generates PNG with           │  │
│  │                           MaskGenerator                  │  │
│  │ [Load Custom Mask from File...]                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  RESULT: User must enable toggle to edit parameters! ❌        │
└─────────────────────────────────────────────────────────────────┘

Data Flow (Before):
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ User selects│────▶│ Shape stored │────▶│ No params!   │
│ Chickenhead │     │ in region    │     │ Not editable │
└─────────────┘     └──────────────┘     └──────────────┘

┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ User enables│────▶│ MaskGenerator│────▶│ PNG image    │
│ Alpha Mask  │     │ creates PNG  │     │ embedded in  │
└─────────────┘     └──────────────┘     │ region       │
                                          └──────────────┘

Problem: Two separate systems for the same goal!
```

## After: Simplified Single-Path System

```
┌─────────────────────────────────────────────────────────────────┐
│ ControlInspector UI                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Shape Picker:                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ○ Rectangle  ○ Circle  ○ Chickenhead  ○ Knurl ...       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  IF parametric shape selected:                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Shape Parameters                                         │  │
│  │                                                          │  │
│  │ Angle Offset: [-90°]         ← Direct editing!          │  │
│  │ Width: [0.1]                                            │  │
│  │ Inner Radius: [0.0]                                     │  │
│  │ Outer Radius: [1.0]                                     │  │
│  │                                                          │  │
│  │ Changes apply immediately to shape outline ✅           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  RESULT: Parameters always editable when shape is selected! ✅  │
└─────────────────────────────────────────────────────────────────┘

Data Flow (After):
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ User selects│────▶│ Shape + auto │────▶│ Parameters   │
│ Chickenhead │     │ init params  │     │ editable! ✅ │
└─────────────┘     └──────────────┘     └──────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ RegionClip   │
                    │ Shape uses   │
                    │ maskParams   │
                    │ to render ✅ │
                    └──────────────┘

Result: One simple system!
```

## Code Changes: Rendering Pipeline

### Before: Conditional maskParams

```
FaceplateCanvas.swift
├─ RegionOverlay
│  └─ maskParams: useAlphaMask ? region.maskParams : nil  ❌ Conditional
│
└─ RegionHitLayer
   └─ maskParams: region.maskParams  ✅ Already correct (from previous fix)

ControlImageRenderer.swift
├─ Normal rendering (useAlphaMask = false)
│  └─ RegionClipShape(shape: shape)  ❌ Missing maskParams!
│
└─ Alpha mask rendering (useAlphaMask = true)
   ├─ Show background faceplate
   └─ Apply alphaMaskImage to rotating patch
```

### After: Unconditional maskParams

```
FaceplateCanvas.swift
├─ RegionOverlay
│  └─ maskParams: region.maskParams  ✅ Always pass
│
└─ RegionHitLayer
   └─ maskParams: region.maskParams  ✅ Already correct

ControlImageRenderer.swift
├─ Normal rendering (useAlphaMask = false)
│  └─ RegionClipShape(shape: shape, maskParams: maskParams)  ✅ Fixed!
│
└─ Alpha mask rendering (useAlphaMask = true)
   ├─ Show background faceplate
   └─ Apply alphaMaskImage to rotating patch  ✅ Still works
```

## MaskGenerator Role

### Before

```
┌────────────────────────────────────────────────────────────┐
│ MaskGenerator.swift                                        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ Used in TWO places:                                        │
│                                                            │
│ 1. ControlInspector                                        │
│    └─ "Apply Mask" button generates PNG from maskParams   │
│                                                            │
│ 2. RegionOverlay                                           │
│    └─ Green preview overlay during editing                │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### After

```
┌────────────────────────────────────────────────────────────┐
│ MaskGenerator.swift                                        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ NOT used in UI anymore!                                    │
│                                                            │
│ Only used for:                                             │
│ • Backward compatibility with old sessions                 │
│ • Rendering existing alphaMaskImage data                   │
│                                                            │
│ NOTE: File kept but no new UI generates PNGs with it      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Shape Types: Before vs After

### Basic Shapes (unchanged)

```
rect, circle
├─ No maskParams needed
└─ Work the same in both systems ✅
```

### Parametric Shapes (IMPROVED!)

```
wedge, line, dot, pointer
├─ BEFORE: Only editable via alpha mask UI ❌
└─ AFTER: Directly editable via Shape Parameters ✅

chickenhead, knurl, dLine, trianglePointer, arrowPointer
├─ BEFORE: Only editable via alpha mask UI ❌
└─ AFTER: Directly editable via Shape Parameters ✅
```

## User Experience Comparison

### Before: Confusing Workflow

```
Step 1: User selects "Chickenhead" shape
        ↓
        "Shape is selected but nothing happens..."
        ↓
Step 2: User searches for how to configure it
        ↓
        "I need to enable 'Use Alpha Mask'? Why?"
        ↓
Step 3: Enable alpha mask toggle
        ↓
Step 4: Sees "Pointer Style" picker
        ↓
        "Wasn't I already picking a shape? Confusing!"
        ↓
Step 5: Adjust parameters
        ↓
Step 6: Click "Apply Mask to Control" button
        ↓
Step 7: Finally see the shape (maybe...)

Result: 7 steps, confusion, frustration ❌
```

### After: Clear Workflow

```
Step 1: User selects "Chickenhead" shape
        ↓
        "Shape Parameters" section appears automatically
        ↓
Step 2: Adjust parameters with sliders
        ↓
        Shape outline updates in real-time ✅

Result: 2 steps, instant feedback, clarity ✅
```

## Summary of Improvements

```
┌────────────────────────┬─────────┬──────────┐
│ Aspect                 │ Before  │ After    │
├────────────────────────┼─────────┼──────────┤
│ UI sections            │ 2 paths │ 1 path   │
│ Toggle required        │ Yes ❌  │ No ✅    │
│ Parameter access       │ Hidden  │ Direct   │
│ Shape picker redundant │ Yes ❌  │ No ✅    │
│ Real-time feedback     │ No ❌   │ Yes ✅   │
│ Lines of UI code       │ 150+    │ 60       │
│ Backward compatible    │ N/A     │ Yes ✅   │
│ User confusion         │ High ❌ │ Low ✅   │
└────────────────────────┴─────────┴──────────┘
```

## Backward Compatibility

```
Old Session File:
{
  "shape": "chickenhead",
  "useAlphaMask": true,          ← Deprecated but still works
  "alphaMaskImage": "data...",   ← Deprecated but still renders
  "maskParams": { ... }
}
        ↓
        Loads successfully! ✅
        ↓
ControlImageRenderer checks useAlphaMask
        ↓
If true: Uses alphaMaskImage for carved effect ✅
If false: Uses shape + maskParams for normal rendering ✅

Result: 100% backward compatible!
```
