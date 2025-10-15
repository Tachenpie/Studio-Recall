# Complex Control Shapes Documentation

## Overview

Studio Recall now supports advanced control shapes for creating more realistic and detailed hardware representations. These complex shapes complement the basic circle and rectangle shapes to enable precise modeling of various hardware control types.

## Supported Complex Shapes

### 1. Chickenhead Knob
**Type:** `ImageRegionShape.chickenhead`

A classic pointer style found on many vintage audio equipment knobs. Features a tapered design that's wide at the base and narrows to a point at the tip.

**Best Used For:**
- Vintage audio equipment knobs
- Retro-styled controls
- Classic guitar amplifiers

**Parameters:**
- `width`: Controls the base width of the pointer (tip is automatically 1/6 of base width, fixed ratio)
- `innerRadius`: Starting point of the pointer (typically 0.0)
- `outerRadius`: End point of the pointer (typically 1.0)
- `angleOffset`: Rotation angle in degrees (0° = right, -90° = up)

**Note:** The 6:1 base-to-tip taper ratio is currently fixed for authentic vintage appearance. Future versions may allow customization.

### 2. Knurl
**Type:** `ImageRegionShape.knurl`

Represents a knurled edge with multiple small notches around the perimeter, commonly found on precision controls.

**Best Used For:**
- Fine-adjustment knobs
- Precision potentiometers
- Rotary encoders

**Parameters:**
- `width`: Controls the thickness of individual notches
- `outerRadius`: Controls the outer edge position
- Note: Automatically generates 12 evenly-spaced notches

**Current Limitation:** The notch count is fixed at 12 for optimal balance between visual detail and rendering performance. Future versions may allow user-configurable notch counts.

### 3. D-Line Pointer
**Type:** `ImageRegionShape.dLine`

A line pointer with a semicircular cap at the tip, resembling the letter "D". Provides clear visual indication while maintaining elegance.

**Best Used For:**
- Modern control panels
- Professional audio interfaces
- Clean, contemporary designs

**Parameters:**
- `width`: Line thickness
- `innerRadius`: Start position
- `outerRadius`: End position (where the D-cap is drawn)
- `angleOffset`: Rotation angle

### 4. Triangle Pointer
**Type:** `ImageRegionShape.trianglePointer`

A simple, bold triangular pointer that extends from base to tip.

**Best Used For:**
- High-visibility indicators
- Large control knobs
- Easy-to-read interfaces

**Parameters:**
- `width`: Base width of the triangle
- `innerRadius`: Base position
- `outerRadius`: Tip position
- `angleOffset`: Rotation angle

### 5. Arrow Pointer
**Type:** `ImageRegionShape.arrowPointer`

A sophisticated pointer with a narrow shaft and a distinct arrowhead tip.

**Best Used For:**
- Precision indicators
- Professional equipment
- Multi-position selectors

**Parameters:**
- `width`: Controls overall arrow width (shaft is 1/3, head is full width)
- `innerRadius`: Start of shaft
- `outerRadius`: Tip of arrowhead
- Note: Arrow transition occurs at 60% of total length (fixed proportion)

**Technical Note:** The shaft-to-head transition point at 60% and the 3:1 width ratio are currently fixed for professional appearance. These may become customizable in future versions.

## Usage

### Setting Up a Complex Shape in the Editor

1. **Select a Control**: Click on a control in the faceplate editor
2. **Enable Region Editing**: Toggle "Edit" in the Control Inspector
3. **Choose Shape**: Select your desired shape from the Shape picker
4. **Configure Parameters** (if using Alpha Mask):
   - Enable "Use Alpha Mask (Carved Pointer)"
   - Select "Pointer Style" matching your shape
   - Adjust angle, width, inner/outer radius sliders

### Programmatic Creation

```swift
// Create a chickenhead knob region
let chickenheadRegion = ImageRegion(
    rect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
    mapping: .rotate(min: -135, max: 135),
    shape: .chickenhead,
    useAlphaMask: true,
    maskParams: MaskParameters(
        style: .chickenhead,
        angleOffset: -90,
        width: 0.15,
        innerRadius: 0.0,
        outerRadius: 1.0
    )
)

// Add to control
var control = Control(name: "Gain", type: .knob, x: 0.5, y: 0.5)
control.regions = [chickenheadRegion]
```

## Integration with Visual Mappings

Complex shapes work seamlessly with all existing visual mapping types:

- **Rotate**: Pointer rotates based on control value
- **Brightness/Opacity**: Shape visibility adjusts with value
- **Translate**: Shape moves within the region
- **Flip3D**: Shape participates in 3D tilt effects
- **Sprite**: Can be used with sprite-based animations

## Alpha Mask Mode

All complex shapes support alpha mask mode, which creates a "carved" effect:

1. **Background Layer**: Shows the static faceplate image
2. **Mask Layer**: The complex shape defines which areas of the rotating patch are visible
3. **Result**: Pointer appears to be carved into the knob surface

This technique is ideal for:
- Realistic knob pointers
- Integrated indicators
- Subtle visual cues

## Best Practices

### Shape Selection Guidelines

- **Chickenhead**: Best for 1-3 unit diameter knobs with retro aesthetic
- **Knurl**: Use on small (< 1 unit) precision controls
- **D-Line**: Modern interfaces, 2-4 unit diameter knobs
- **Triangle**: High-contrast situations, large knobs (> 3 units)
- **Arrow**: Professional gear, medium to large knobs

### Parameter Tuning

1. **Width**:
   - Start with 0.1 (10% of radius)
   - Increase for visibility, decrease for subtlety
   - Chickenhead looks best at 0.12-0.18

2. **Inner/Outer Radius**:
   - Default: 0.0 to 1.0 (full span)
   - For partial pointers: try 0.2 to 0.9
   - Knurl uses 0.85-1.0 range automatically

3. **Angle Offset**:
   - -90° for top-pointing (most common)
   - 0° for right-pointing
   - Adjust to match hardware photos

### Performance Considerations

- Complex shapes use path rendering, which is efficient
- Alpha masks involve compositing, use when needed
- Knurl generates multiple paths (12 notches) but remains performant

## Compatibility

- **Representational View**: Uses simplified glyphs, independent of shape choice
- **Photorealistic View**: Fully renders all complex shapes
- **Export/Import**: Shapes are fully serializable via JSON
- **Backward Compatibility**: Older sessions without complex shapes load normally

## Troubleshooting

### Shape Not Visible
1. Ensure region rect is properly positioned on the control
2. Check that maskParams are set when using parametric shapes
3. Verify alpha mask image is generated (preview in inspector)

### Pointer Appears at Wrong Angle
1. Adjust `angleOffset` in mask parameters
2. For rotate mapping, verify `degMin` and `degMax`
3. Remember: 0° = right, -90° = up, 180° = left, 90° = down

### Shape Looks Distorted
1. Ensure region rect is square or proportional
2. Check that width parameter is reasonable (0.05-0.3 range)
3. Verify innerRadius < outerRadius

## Examples

### Classic Audio Compressor
```swift
// Ratio knob with chickenhead pointer
let ratioKnob = ImageRegion(
    rect: CGRect(x: 0.3, y: 0.4, width: 0.15, height: 0.15),
    mapping: .rotate(min: -120, max: 120),
    shape: .chickenhead,
    maskParams: MaskParameters(style: .chickenhead, angleOffset: -90, width: 0.14)
)
```

### Modern EQ with Precision Controls
```swift
// Q knob with knurl edge
let qKnob = ImageRegion(
    rect: CGRect(x: 0.6, y: 0.5, width: 0.08, height: 0.08),
    mapping: .rotate(min: -135, max: 135),
    shape: .knurl,
    maskParams: MaskParameters(style: .knurl, width: 0.08)
)
```

### Contemporary Interface
```swift
// Gain reduction with D-line
let grKnob = ImageRegion(
    rect: CGRect(x: 0.5, y: 0.3, width: 0.12, height: 0.12),
    mapping: .rotate(min: -150, max: 150),
    shape: .dLine,
    maskParams: MaskParameters(style: .dLine, angleOffset: -90, width: 0.1)
)
```

## Future Enhancements

Potential additions in future versions:
- Custom SVG path import for arbitrary shapes
- Multi-color complex shapes
- Animated shape transitions
- Shape presets library
- User-defined notch count for knurl

## See Also

- [Controls.swift](../Studio%20Recall/Models/Controls.swift) - Core shape definitions
- [RegionClipShape.swift](../Studio%20Recall/Handlers/RegionClipShape.swift) - Shape rendering
- [MaskGenerator.swift](../Studio%20Recall/Utilities/MaskGenerator.swift) - Alpha mask generation
- [ControlInspector.swift](../Studio%20Recall/Views/Controls/ControlInspector.swift) - UI for shape configuration
