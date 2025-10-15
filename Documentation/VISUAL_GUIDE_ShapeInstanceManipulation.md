# Visual Guide: Shape Instance Direct Manipulation

## Overview

This guide provides visual representations of the shape instance manipulation system.

## Before and After

### Before: Slider-Based Editing

```
┌─────────────────────────────────────────────────────┐
│ Control Inspector                                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Shape 1                               [Remove]      │
│ ┌─────────────────────────────────────────────┐    │
│ │ ○ Circle  ■ Rectangle  △ Triangle           │    │
│ └─────────────────────────────────────────────┘    │
│                                                     │
│ Position X: 0.50                                   │
│ ├────────────●────────────┤                        │
│                                                     │
│ Position Y: 0.50                                   │
│ ├────────────●────────────┤                        │
│                                                     │
│ Width: 0.30                                        │
│ ├────────────●────────────┤                        │
│                                                     │
│ Height: 0.30                                       │
│ ├────────────●────────────┤                        │
│                                                     │
│ Rotation: 45°                                      │
│ ├────────────●────────────┤                        │
│                                                     │
└─────────────────────────────────────────────────────┘

Issues:
❌ Cluttered interface with many sliders
❌ Hard to understand spatial relationships
❌ Switching between canvas and inspector
❌ No visual feedback while adjusting
```

### After: Direct Manipulation

```
┌─────────────────────────────────────────────────────┐
│ Control Inspector                                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Shape 1                               [Remove]      │
│ ┌─────────────────────────────────────────────┐    │
│ │ ○ Circle  ■ Rectangle  △ Triangle           │    │
│ └─────────────────────────────────────────────┘    │
│                                                     │
│ 💡 Drag shape directly in the canvas to adjust    │
│    position, size, and rotation.                   │
│                                                     │
└─────────────────────────────────────────────────────┘

Benefits:
✅ Clean, minimal interface
✅ Direct visual feedback
✅ Work in context on the canvas
✅ Intuitive spatial manipulation
```

## Canvas Interaction

### Unselected Shape Instance

```
┌────────────────────────────────────┐
│  Control Region (dashed border)   │
│                                    │
│       ┌───────┐                    │
│       │       │   ← Shape instance │
│       │   ○   │      (no handles)  │
│       │       │                    │
│       └───────┘                    │
│                                    │
│  Click to select →                 │
│                                    │
└────────────────────────────────────┘
```

### Selected Shape Instance - Circle

```
┌────────────────────────────────────┐
│  Control Region                    │
│                                    │
│           ○  ← Rotation handle     │
│           ┊                        │
│       □───╔═══╗───□                │
│       │   ║░░░║   │                │
│       │   ║░○░║   │  ← Selected    │
│       │   ║░░░║   │     shape      │
│       □───╚═══╝───□                │
│           ▲                        │
│           │                        │
│  Marching ants outline (animated)  │
│                                    │
└────────────────────────────────────┘

Legend:
  ╔═══╗  Marching ants (dashed outline)
  ░░░░  Shape interior
  □     Corner resize handles
  ○     Rotation handle
  ┊     Connection line to rotation handle
```

### Selected Shape Instance - Rectangle

```
┌────────────────────────────────────┐
│  Control Region                    │
│                                    │
│           ○  ← Rotation handle     │
│           ┊                        │
│       □───□───□                    │
│       │   ╔═══╗   │                │
│       □   ║░░░║   □  ← Edge        │
│       │   ║░░░║   │     handles    │
│       □───╚═══╝───□                │
│           ▲                        │
│  Rectangle has 8 handles           │
│  (4 corners + 4 edges)             │
│                                    │
└────────────────────────────────────┘

Legend:
  □  Corner handles (8 total)
     - 4 on corners
     - 4 on edges (top, bottom, left, right)
```

### Selected Shape Instance - Triangle

```
┌────────────────────────────────────┐
│  Control Region                    │
│                                    │
│           ○  ← Rotation handle     │
│           ┊                        │
│       □───□───□                    │
│       │   ╱ ╲   │                  │
│       □  ╱░░░╲  □                  │
│       │ ╱░░░░░╲ │                  │
│       □─────────□                  │
│           ▲                        │
│  Triangle outline is bounding box  │
│  Shape itself has 3 vertices       │
│                                    │
└────────────────────────────────────┘

Note: Triangle always points up at 0° rotation
```

## Manipulation Operations

### Operation 1: Move (Drag Shape)

```
Before:                  During:                 After:
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│              │        │              │        │              │
│   ╔═══╗      │   →    │      ╔═══╗  │   →    │        ╔═══╗ │
│   ║░○░║      │        │      ║░○░║  │        │        ║░○░║ │
│   ╚═══╝      │        │      ╚═══╝  │        │        ╚═══╝ │
│              │        │              │        │              │
└──────────────┘        └──────────────┘        └──────────────┘

Action: Click and drag anywhere inside the shape
Cursor: Open hand (⚑) when moving
Constraint: Stays within region bounds (0-1)
```

### Operation 2: Resize from Corner

```
Before:                  During:                 After:
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  □───□       │        │  □           │        │  □           │
│  │ ╔═╗  │    │   →    │  │ ╔═══╗    │   →    │  │ ╔═════╗  │
│  □ ╚═╝  □    │        │  □ ╚═══╝    │        │  □ ╚═════╝  │
│    └────□    │        │    └────□    │        │    └──────□  │
└──────────────┘        └──────────────┘        └──────────────┘
     ↖                        ↖                       ↖
Drag bottom-right corner to resize
Cursor: Diagonal resize arrow (↘↖)
Anchored: Top-left corner stays fixed
```

### Operation 3: Resize from Edge (Rectangle/Triangle only)

```
Before:                  During:                 After:
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  □───□───□   │        │  □───□───□   │        │  □───□───□   │
│  │ ╔═══╗ │  │   →    │  │ ╔═════╗  │   →    │  │ ╔═══════╗ │
│  □ ╚═══╝ □  │        │  □ ╚═════╝  │        │  □ ╚═══════╝ │
│    └─────□   │        │    └───────□ │        │    └─────────□
└──────────────┘        └──────────────┘        └──────────────┘
         →                       →                       →
Drag right edge handle to resize width only
Cursor: Horizontal resize arrow (↔)
Fixed: Height and vertical center
```

### Operation 4: Rotate (Drag Rotation Handle)

```
Before (0°):            During (45°):           After (90°):
     ○                       ○                       ○
     ┊                      ┊╱                      ─┊
 □───□───□               □──╔╗──□               □───□───□
 │ ╔═══╗ │              ╱│  ║║  │╲              │ ╔═══╗ │
 □ ║░░░║ □             ╱ □  ║║  □ ╲             │ ║░░░║ │
 │ ╚═══╝ │            ╱    ╚╝    ╲             │ ║░░░║ │
 □───────□                                      □ ╚═══╝ □
                                                  └───────□

Action: Drag rotation handle in circular motion
Cursor: Crosshair (+) when rotating
Range: 0-360° (wraps around)
Reference: 0° points upward
```

## Multiple Shape Instances

### Scenario: Two Overlapping Shapes

```
┌────────────────────────────────────┐
│  Control Region                    │
│                                    │
│      ╔═══╗    ┏━━━┓                │
│      ║░1░║    ┃░2░┃ ← Shape 2      │
│      ║░░░╠════╪═══┫    (selected)  │
│      ╚═══╝    ┗━━━┛                │
│       ↑                             │
│   Shape 1 (unselected)             │
│                                    │
│  Click shape 1 to switch selection │
│                                    │
└────────────────────────────────────┘

Single line (═): Unselected shape (no handles)
Double line (━): Selected shape (with handles)
```

## Coordinate System Flow

```
┌─────────────────────────────────────────────────┐
│ 1. User Action (Parent/Viewport Space)          │
│    - Mouse position with zoom/pan applied       │
│    - Gesture translation in screen pixels       │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│ 2. Gesture Conversion                           │
│    - Parent pixels → Canvas pixels              │
│    - Apply zoom factor                          │
│    - Account for pan offset                     │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│ 3. Normalized Region Space (0-1)                │
│    - Canvas pixels → Region space               │
│    - Divide by region width/height              │
│    - Clamp to valid range (0-1)                 │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│ 4. Update ShapeInstance Model                   │
│    - shapeInstance.position = CGPoint(x, y)     │
│    - shapeInstance.size = CGSize(w, h)          │
│    - shapeInstance.rotation = degrees           │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│ 5. Render Update                                │
│    - Model → Canvas space for visual overlay    │
│    - Model → Parent space for hit testing       │
│    - SwiftUI updates automatically              │
└─────────────────────────────────────────────────┘
```

## Resize Handle Hit Areas

```
Visual Handles:        Actual Hit Areas:
                       (enlarged for easier grabbing)

□───□───□              ┌───┬───┬───┐
│       │              │ C │ E │ C │  C = Corner (12px)
□       □       →      ├───┼───┼───┤  E = Edge (14px)
│       │              │ E │   │ E │
□───────□              ├───┼───┼───┤
                       │ C │ E │ C │
                       └───┴───┴───┘

Notes:
- Hit areas are larger than visual handles
- Ensures handles are easy to grab
- Corners have priority over edges
- Hit areas scale with zoom (screen-constant)
```

## Z-Order / Layering

```
Stack Order (bottom to top):
┌─────────────────────────────────────────┐
│ Layer 5 (Top): Rotation Handles         │ ← Highest priority
├─────────────────────────────────────────┤
│ Layer 4: Shape Instance Hit Layers      │ ← Interactive
├─────────────────────────────────────────┤
│ Layer 3: Region Hit Layer               │ ← Region editing
├─────────────────────────────────────────┤
│ Layer 2: Visual Overlays                │
│          - RegionOverlay                │ ← Visual feedback
│          - ShapeInstanceOverlay         │
├─────────────────────────────────────────┤
│ Layer 1 (Bottom): Canvas Content        │
│          - Device image                 │ ← Base layer
│          - Rendered controls            │
└─────────────────────────────────────────┘

Hit Testing Order:
1. Rotation handle (if selected)
2. Shape instance (if in edit region)
3. Region boundary (if editing region)
4. Canvas content (control selection)
```

## State Diagram

```
┌─────────────┐
│   Idle      │  ← Starting state
│  (no shape  │
│  selected)  │
└──────┬──────┘
       │ Click shape
       ▼
┌─────────────┐
│  Selected   │
│  (showing   │
│  handles)   │
└──┬──────┬───┘
   │      │ Click different shape
   │      └──────────────┐
   │                     │
   │ Drag shape body    │
   ▼                     ▼
┌──────────┐     ┌─────────────┐
│  Moving  │     │   Select    │
│          │     │  Different  │
└──────────┘     │   Shape     │
   │             └─────────────┘
   │ Release          │
   └──────┬───────────┘
          ▼
   ┌─────────────┐
   │  Selected   │
   │  (showing   │
   │  handles)   │
   └──┬──────────┘
      │
      │ Drag handle
      ▼
   ┌──────────┐
   │ Resizing │
   │    or    │
   │ Rotating │
   └──────────┘
      │
      │ Release
      ▼
   ┌─────────────┐
   │  Selected   │
   └─────────────┘
```

## Inspector Integration

```
Inspector State Changes:

1. User clicks "Add Shape"
   ├─→ New ShapeInstance added to region
   ├─→ Instance appears at center (0.5, 0.5)
   └─→ Auto-select new instance (planned feature)

2. User changes shape type picker
   ├─→ ShapeInstance.shape property updates
   ├─→ Visual overlay regenerates path
   └─→ Hit layer updates geometry

3. User clicks "Remove"
   ├─→ ShapeInstance removed from array
   ├─→ If selected instance removed, clear selection
   └─→ Canvas updates to hide instance

4. Shape manipulated in canvas
   ├─→ ShapeInstance model updates
   ├─→ No change to inspector (sliders removed)
   └─→ Instructional text remains
```

## Performance Considerations

```
Operation              Cost      Notes
────────────────────────────────────────────────────
Click detection        Low       Single path contains check
Drag gesture           Low       Delta calculation only
Overlay rendering      Medium    Path generation + stroke
Hit layer rendering    Low       Invisible shapes
Multiple instances     Medium    N × render cost
High zoom (>200%)      Medium    More screen pixels to draw
Complex paths          Low       Simple geometric shapes
Animation (marching)   Medium    Phase offset updates
```

## Error Cases and Edge Handling

```
Problem: Shape at top edge, rotation handle off-screen
┌────────────────┐
│    ○ ┊         │  ← Rotation handle above viewport
├───────┊────────┤
│   ╔═══╩═╗      │
│   ║░░░░░║      │
│   ╚═════╝      │
└────────────────┘
Solution: Scroll or zoom out to access rotation handle

Problem: Minimum size constraint
┌────────────────┐
│   ╔╗            │  ← Cannot resize smaller than 5%
│   ╚╝            │
│                │
└────────────────┘
Solution: Resize stops at minimum, provides resistance

Problem: Overlapping shapes
┌────────────────┐
│  ╔═══╗━━━━┓    │  ← Two shapes overlap
│  ║░1░╠══╪2┃    │
│  ╚═══╝  ┗━━┛    │
└────────────────┘
Solution: Click to select, front shape has hit priority
```

## Keyboard Shortcuts (Planned)

```
Modifier         Effect
───────────────────────────────────────────
Shift            Constrain movement to H/V axis
Option/Alt       Duplicate while dragging
Command          Fine control (10% speed)
Backspace/Del    Delete selected shape
Escape           Deselect shape
Tab              Select next shape
Shift+Tab        Select previous shape
```

## Summary

This visual guide demonstrates:

✅ Clear before/after comparison showing UX improvement
✅ Detailed diagrams of all manipulation operations
✅ Coordinate system flow for developers
✅ State diagram showing interaction flow
✅ Handle hit areas and z-order layering
✅ Error cases and solutions
✅ Performance considerations

The direct manipulation system provides an intuitive, professional-grade editing experience that matches modern graphics software standards while integrating seamlessly with Studio Recall's existing control editing workflow.
