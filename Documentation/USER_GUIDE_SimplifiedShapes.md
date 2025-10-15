# User Guide: Simplified Control Shapes

## Overview

Studio Recall's control shapes system has been simplified to make it easier and more intuitive to create accurate control masks. You can now use basic shapes (circle, rectangle, triangle) and combine multiple instances to create any pattern you need.

## What Are Shape Instances?

Shape instances are individual shapes that you can add to a control region to define which parts of the faceplate image should be masked. Each instance can be:
- Positioned independently
- Sized independently
- Rotated independently
- One of three simple types: circle, rectangle, or triangle

## How to Use

### Step 1: Select a Control

1. Click on a control in the faceplate editor
2. The Control Inspector will appear on the right

### Step 2: Create or Edit a Region

1. If the control doesn't have a region, click "Create"
2. If it already has a region, toggle "Edit" to enable editing mode

### Step 3: Add Shape Instances

1. Scroll to the "Shape Instances" section in the inspector
2. Click "Add Shape" to create a new shape instance
3. Each new shape starts at the center (0.5, 0.5) with default size

### Step 4: Configure Each Shape

For each shape instance, you can adjust:

#### Shape Type
- **Circle**: Best for round knobs, buttons, or dots
- **Rectangle**: Best for linear indicators, bars, or rectangular markers
- **Triangle**: Best for pointing indicators or directional markers

#### Position
- **Position X** (0-1): Horizontal position within the region
  - 0 = left edge
  - 0.5 = center
  - 1 = right edge
- **Position Y** (0-1): Vertical position within the region
  - 0 = top edge
  - 0.5 = center
  - 1 = bottom edge

#### Size
- **Width** (0.05-1): Shape width relative to region
  - 0.1 = 10% of region width
  - 0.5 = 50% of region width
  - 1 = full region width
- **Height** (0.05-1): Shape height relative to region
  - Same scale as width

#### Rotation
- **Rotation** (0-360°): Clockwise rotation
  - 0° = no rotation
  - 90° = quarter turn
  - 180° = half turn
  - 270° = three-quarter turn

### Step 5: Remove Unwanted Shapes

- Click the red "Remove" button next to any shape instance to delete it

## Color Matching

**Automatic**: The system automatically samples the faceplate color at the region center and applies it to your shapes. This creates a seamless appearance where the shapes blend naturally with the faceplate.

The color matching:
- Samples a 5×5 pixel area for accuracy
- Averages the color values
- Updates automatically when you move the region

## Common Patterns

### Simple Knob Pointer
1. Add 1 rectangle
2. Position: X=0.5, Y=0.5
3. Size: Width=0.1, Height=0.4
4. Rotation: 0° (will rotate with knob value)

### Dual Pointer Knob
1. Add 2 rectangles
2. **First rectangle** (outer):
   - Position: X=0.5, Y=0.5
   - Size: Width=0.08, Height=0.45
   - Rotation: 0°
3. **Second rectangle** (inner):
   - Position: X=0.5, Y=0.5
   - Size: Width=0.06, Height=0.25
   - Rotation: 0°

### Triangular Indicator
1. Add 1 triangle
2. Position: X=0.5, Y=0.5
3. Size: Width=0.2, Height=0.2
4. Rotation: 0° (points up by default)

### Cross Pattern
1. Add 2 rectangles
2. **First rectangle** (horizontal):
   - Position: X=0.5, Y=0.5
   - Size: Width=0.4, Height=0.1
   - Rotation: 0°
3. **Second rectangle** (vertical):
   - Position: X=0.5, Y=0.5
   - Size: Width=0.1, Height=0.4
   - Rotation: 0°

### Circular Dot
1. Add 1 circle
2. Position: X=0.5, Y=0.3 (towards top)
3. Size: Width=0.15, Height=0.15
4. Rotation: 0° (rotation doesn't affect circles)

### Complex Vintage Knob
1. Add 3 shapes:
   - **Base circle**: Large circle for knob body
   - **Pointer rectangle**: Thin rectangle for indicator
   - **Tip circle**: Small circle at pointer tip
2. Position them to create the desired appearance

## Tips and Best Practices

### Positioning
- Use X=0.5, Y=0.5 for centered shapes
- For pointers, position at center and extend with size/rotation
- Remember: coordinates are relative to the region, not the whole faceplate

### Sizing
- Start with conservative sizes (0.2-0.3)
- Fine-tune with 0.01 increments
- Width and height can be different for elongated shapes

### Rotation
- Knob controls typically need a vertical pointer (0° or 180°)
- The rotation will animate based on the control's mapping
- Test rotation in the session view to see the effect

### Multiple Shapes
- Add shapes from largest to smallest for better visual hierarchy
- Use overlapping shapes to create complex patterns
- Remove unnecessary shapes to keep the design clean

### Performance
- Keep the number of shape instances reasonable (typically 1-5)
- More instances = more rendering work
- For most controls, 1-2 shapes are sufficient

## Migration from Old System

If you have existing controls with complex shapes:
- **They still work!** No action required
- Old shapes automatically map to simplified equivalents:
  - chickenhead → rectangle
  - wedge → triangle
  - knurl → triangle
  - line → rectangle
  - etc.

If you want to update to the new system:
1. Select the control
2. Delete the old region
3. Create a new region
4. Add shape instances as described above

## Troubleshooting

### Shapes Don't Appear
- Check that you've added at least one shape instance
- Verify the region is large enough to see the shapes
- Check position values (should be 0-1)

### Color Doesn't Match
- The color is sampled from the region center
- Move the region if needed to sample a better color
- Future updates may add manual color selection

### Shapes Are Too Large/Small
- Adjust the Size Width and Height sliders
- Remember: 1.0 = full region size
- Try values between 0.1 and 0.5 for most uses

### Rotation Doesn't Work
- Rotation requires a mapping (like "rotate" mapping)
- Circles don't visually change with rotation
- Check that the control type supports rotation (knobs, stepped knobs)

## Example Workflow

Let's create a classic knob with a line indicator:

1. **Create the control**
   - Add a knob control
   - Position it on the faceplate

2. **Create the region**
   - Click "Create" in the region section
   - Size and position the region to cover the knob

3. **Add the pointer**
   - Click "Add Shape"
   - Select "Rectangle" as the shape type

4. **Position the pointer**
   - Set Position X to 0.5 (center horizontally)
   - Set Position Y to 0.5 (center vertically)

5. **Size the pointer**
   - Set Width to 0.08 (thin line)
   - Set Height to 0.4 (extends from center to edge)

6. **Test it**
   - Exit edit mode
   - Adjust the knob value
   - The pointer should rotate with the knob

7. **Fine-tune**
   - Re-enter edit mode if needed
   - Adjust position, size, or rotation
   - Add more shapes if desired

## Getting Help

If you need assistance:
1. Check the full implementation documentation: `IMPLEMENTATION_SimplifiedShapes.md`
2. Review the code examples in the test files
3. Experiment with the sliders to understand their effects
4. Start simple and add complexity gradually

## What's Next?

Future enhancements may include:
- Manual color picker
- Shape presets for common patterns
- Visual preview in the inspector
- Alignment and snapping tools
- Save/load shape configurations

---

**Happy creating!** The simplified shapes system gives you the power to create any control mask you need with just a few simple shapes.
