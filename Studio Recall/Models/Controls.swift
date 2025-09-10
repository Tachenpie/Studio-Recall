//
//  Controls.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

// MARK: - Control Types
enum ControlType: String, Codable, CaseIterable {
    case knob
    case steppedKnob
    case multiSwitch
    case button
	case light
	case concentricKnob
	case litButton
}

extension ControlType {
	var displayName: String {
		switch self {
			case .knob:            return "Knob"
			case .steppedKnob:     return "Stepped Knob"
			case .multiSwitch:     return "Switch"
			case .button:          return "Button"
			case .light:           return "Light"
			case .concentricKnob:  return "Concentric Knob"
			case .litButton:       return "Lit Button"
		}
	}
}

// MARK: - Helpers
enum Bound: Codable, Equatable {
	case finite(Double)
	case negInfinity
	case posInfinity
	
	func resolve(default v: Double) -> Double {
		switch self {
			case .finite(let d): return d
			case .negInfinity:   return -Double.greatestFiniteMagnitude
			case .posInfinity:   return  Double.greatestFiniteMagnitude
		}
	}
}

// MARK: - Visual Stuff
enum VisualMappingKind: String, Codable { case rotate, brightness, opacity, translate, flip3D, sprite }

enum ValueTaper: String, Codable, CaseIterable {
	case linear
	case decibel   // good for dB ranges like −∞ … 0 dB
}

struct RangeD: Codable, Equatable { var lower: Double; var upper: Double }
struct RangeF: Codable, Equatable { var lower: CGFloat; var upper: CGFloat }

struct VisualMapping: Codable, Equatable {
	var kind: VisualMappingKind

	// Rotate
	var degMin: Double?; var degMax: Double?; var pivot: CGPoint?
	
	// Brightness/Opacity
	var scalarRange: RangeD?
	var taper: ValueTaper? = nil

	// Translate (region local, 0...1 of region w/h)
	var transStart: CGPoint? = nil
	var transEnd:   CGPoint? = nil

	/// Flip (3D tilt) parameters
	var tiltMin: Double? = nil
	var tiltMax: Double? = nil
	/// Which axis is the hinge around? `.x` = flips up/down, `.y` = flips left/right
	enum Axis3D: String, Codable { case x, y, z }
	var tiltAxis: Axis3D? = nil
	/// Perspective (0…1). ~0.6 looks like real hardware.
	var perspective: Double? = nil
	// Tilts for multiswitches
	var tiltByIndex: [Double]? = nil
	var tiltRefIndex: Int? = nil
	
	var showGizmo: Bool? = nil // when true, renderer draws the pivot/hinge gizmo
	
	// SPRITE (poses)
	var spriteAssetId: UUID? = nil
	var spriteAtlasPNG: Data? = nil     // PNG data for the atlas
	var spriteCols: Int? = 1            // grid columns in the atlas
	var spriteRows: Int? = 1            // grid rows in the atlas
	var spriteIndices: [Int]? = nil     // optional per-option frame index (multiswitch); otherwise uses Selected
	var spriteScale: Double? = 1.0      // relative to region height
	var spritePivot: CGPoint? = CGPoint(x: 0.5, y: 0.9) // 0…1 within the sprite frame (e.g., 0.9 ~ near bottom)
	var spriteQuarterTurns: Int? = 0
	
	enum SpriteMode: String, Codable { case atlasGrid, frames }
	var spriteMode: SpriteMode? {                                  // default to grid for backward compat
		get { _spriteMode ?? .atlasGrid }
		set { _spriteMode = newValue }
	}
	private var _spriteMode: SpriteMode? {
		get { _spriteModeStorage }
		set { _spriteModeStorage = newValue }
	}
	// backing store (so the computed var stays Codable)
	private var _spriteModeStorage: SpriteMode? {
		get { _spriteModeRaw == nil ? nil : SpriteMode(rawValue: _spriteModeRaw!) }
		set { _spriteModeRaw = newValue?.rawValue }
	}
	private var _spriteModeRaw: String? { get { spriteModeRaw } set { spriteModeRaw = newValue } }
	var spriteModeRaw: String?   // <- add this stored optional String in VisualMapping
	
	// NEW: freeform frames (use when you can’t mirror/flip, or N>2)
	var spriteFrames: [Data]? = nil        // PNG/JPEG data for each frame, in order (0..N-1)
	
	// (optional niceties; all default to global settings if nil)
	var spritePivots: [CGPoint]? = nil     // per-frame pivot inside each frame (0…1), if you need it
	var spriteOffsets: [CGPoint]? = nil    // tiny per-frame offsets in region space (−1…+1 of region size)
	
	static func rotate(min: Double = -135,
					   max: Double = 135,
					   pivot: CGPoint = .init(x: 0.5, y: 0.5),
					   taper: ValueTaper? = nil) -> Self
	{
		.init(kind: .rotate, degMin: min, degMax: max, pivot: pivot, scalarRange: nil, taper: taper)
	}
	static func brightness(_ r: RangeD) -> Self { .init(kind: .brightness, degMin: nil, degMax: nil, pivot: nil, scalarRange: r, taper: nil) }
	static func opacity(_ r: RangeD)    -> Self { .init(kind: .opacity,    degMin: nil, degMax: nil, pivot: nil, scalarRange: r, taper: nil) }
	static func translate(from: CGPoint = .zero, to: CGPoint = .zero) -> Self {
		var m = Self.init(kind: .translate, degMin: nil, degMax: nil, pivot: nil, scalarRange: nil)
		m.transStart = from; m.transEnd = to
		return m
	}
	static func flip3D(min: Double = -22,
					   max: Double =  22,
					   axis: Axis3D = .x,
					   pivot: CGPoint = .init(x: 0.5, y: 0.85),
					   perspective: Double = 0.6) -> Self {
		var m = Self.init(kind: .flip3D, degMin: min, degMax: max, pivot: pivot, scalarRange: nil)
		m.tiltMin = min; m.tiltMax = max
		m.tiltAxis = axis; m.perspective = perspective
		return m
	}
	
	static func sprite(atlasPNG: Data? = nil,
					   cols: Int = 1, rows: Int = 1,
					   pivot: CGPoint = .init(x: 0.5, y: 0.85),
					   spritePivot: CGPoint = .init(x: 0.5, y: 0.9),
					   scale: Double = 1.0) -> Self
	{
		var m = Self.init(kind: .sprite, degMin: nil, degMax: nil, pivot: pivot, scalarRange: nil)
		m.spriteAtlasPNG = atlasPNG
		m.spriteCols = cols; m.spriteRows = rows
		m.pivot = pivot
		m.spritePivot = spritePivot
		m.spriteScale = scale
		return m
	}
}

extension VisualMapping {
	var hasEmbeddedSpriteData: Bool {
		(spriteAtlasPNG != nil) || ((spriteFrames?.isEmpty == false))
	}
}

enum ImageRegionShape: String, Codable { case rect, circle }

struct ImageRegion: Codable, Equatable {
	/// Normalized rect (0–1) in canvas/view coordinates
	var rect: CGRect
	/// How to transform the cropped patch as the control changes
	var mapping: VisualMapping?
	var shape: ImageRegionShape = .rect
}

extension ImageRegion {
	/// Default placeholder size for newly created/placeholder regions (in canvas-normalized units)
	static let defaultSize: CGFloat = 0.06
}


struct CodableColor: Codable, Equatable {
	var r: Double
	var g: Double
	var b: Double
	var a: Double
	
	// Use this anywhere you currently call `CodableColor(someSwiftUIColor)`
	init(_ color: Color) {
#if os(macOS)
		// Bridge -> NSColor, then force sRGB
		let base = NSColor(color)
		let srgb = base.usingColorSpace(.sRGB)
		?? base.usingColorSpace(.deviceRGB)
		?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
		
		var rr: CGFloat = 1, gg: CGFloat = 1, bb: CGFloat = 1, aa: CGFloat = 1
		srgb.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
		
		self.r = Double(rr)
		self.g = Double(gg)
		self.b = Double(bb)
		self.a = Double(aa)
#else
		// iOS/tvOS: UIColor path (also ensure sRGB)
		let ui = UIColor(color)
		var rr: CGFloat = 1, gg: CGFloat = 1, bb: CGFloat = 1, aa: CGFloat = 1
		if ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
			self.r = Double(rr)
			self.g = Double(gg)
			self.b = Double(bb)
			self.a = Double(aa)
		} else {
			// Fallback for monochrome colorspaces
			var white: CGFloat = 1
			ui.getWhite(&white, alpha: &aa)
			self.r = Double(white)
			self.g = Double(white)
			self.b = Double(white)
			self.a = Double(aa)
		}
#endif
	}
	
	// Convenience when you already have numeric components
	static func srgb(r: Double, g: Double, b: Double, a: Double = 1.0) -> CodableColor {
		CodableColor(Color(.sRGB, red: r, green: g, blue: b, opacity: a))
	}
	
	// Always return an sRGB Color so SwiftUI renders consistently
	var color: Color {
		Color(.sRGB, red: r, green: g, blue: b, opacity: a)
	}
}


struct ControlSpriteSet: Codable, Equatable {
	var states: [Data]  // PNGs with alpha, in control-local space
	// Optional: a pivot for rotation if these sprites include switch levers
	var pivot: CGPoint? = nil
}

// MARK: - Control Model
struct Control: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var type: ControlType
    
    // Common value storage
    var value: Double?        // knob: 0.0 ... 1.0
    var stepIndex: Int?       // stepped knob: selected index
    var options: [String]?    // multi-switch: label list
    var selectedIndex: Int?   // multi-switch: current index
    var isPressed: Bool?      // button: true/false
	
	// Specifics
	// KNOB ranges (+∞, −∞ safe)
	var knobMin: Bound? = nil
	var knobMax: Bound? = nil
	
	// Stepped knob: per-step angles & values
	var stepAngles: [Double]? = nil      // degrees (UI mapping)
	var stepValues: [Double]? = nil      // user semantics (e.g., dB)
	
	// Multi-switch: per-position angles & values
	var optionAngles: [Double]? = nil
	var optionValues: [Double]? = nil
	
	// Concentric knob (outer ring + inner ring
	var outerValue: Double?          // normalized 0…1 (e.g. Gain)
	var innerValue: Double?          // normalized 0…1 (e.g. Q)
	
	// Optional semantic ranges & tapers (mirrors your knob support)
	var outerMin: Bound? = nil
	var outerMax: Bound? = nil
	var innerMin: Bound? = nil
	var innerMax: Bound? = nil
	var outerTaper: ValueTaper? = nil
	var innerTaper: ValueTaper? = nil
	
	// Optional per-ring visual mappings (e.g. rotate, sprite)
	var outerMapping: VisualMapping? = nil
	var innerMapping: VisualMapping? = nil
	
	// Labels for inspector/tooltip clarity
	var outerLabel: String? = nil    // "Gain"
	var innerLabel: String? = nil    // "Q"
	
	// === Lit button (integrated lamp) ===
	var lampOnColor: CodableColor? = nil  // overrides onColor if set
	var lampOffColor: CodableColor? = nil // overrides offColor if set
	
	/// Lamp behavior: when nil → default follows `isPressed`.
	/// If you want the lamp to follow a different control (like a ratio selection),
	/// reuse your existing link fields (linkTarget/linkInverted/linkOnIndex).
	var lampFollowsPress: Bool? = nil   // default true if nil
	
	// If you want a lamp that can be set manually (rare), provide an override:
	var lampOverrideOn: Bool? = nil     // when set, this wins
	
	// Light colors
	var onColor: CodableColor? = nil
	var offColor: CodableColor? = nil
	var linkTarget: UUID?		// for lamps that indicate control status
	var linkInverted: Bool?		// also for lamps
	var linkOnIndex: Int? = nil
	
	// For when we need sprites
	var sprites: ControlSpriteSet? // nil = no sprites (use patch)
	var spriteIndex: Int?          // derive from pressed/index when present
	
    // Draggable position
	var position: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var x: CGFloat = 0.5   // normalized (0–1)
    var y: CGFloat = 0.5   // normalized (0–1)
	
	var regions: [ImageRegion] = []
	
	// Legacy shim so older code still compiles
	var region: ImageRegion? {
		get { regions.first }
		set {
			if let r = newValue {
				if regions.isEmpty { regions.append(r) }
				else { regions[0] = r }
			} else {
				regions.removeAll()
			}
		}
	}
	
	enum CodingKeys: String, CodingKey {
		case id, name, type, value, stepIndex, options, selectedIndex, isPressed
		case knobMin, knobMax, stepAngles, stepValues, optionAngles, optionValues
		case onColor, offColor, linkTarget, linkInverted, linkOnIndex
		case sprites, spriteIndex, position, x, y
		case regions   // new
		case region    // legacy
	}
	
	// Custom decode to migrate old -> new
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(UUID.self, forKey: .id)
		name = try c.decode(String.self, forKey: .name)
		type = try c.decode(ControlType.self, forKey: .type)
		// … decode all your other fields …
		regions = try c.decodeIfPresent([ImageRegion].self, forKey: .regions) ?? []
		if regions.isEmpty, let legacy = try c.decodeIfPresent(ImageRegion.self, forKey: .region) {
			regions = [legacy]
		}
	}
	
	// Encode both (for backward compat, optional)
	func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		try c.encode(id, forKey: .id)
		try c.encode(name, forKey: .name)
		try c.encode(type, forKey: .type)
		// … encode other fields …
		try c.encode(regions, forKey: .regions)
		if let first = regions.first {
			try c.encode(first, forKey: .region)
		}
	}

}

extension Control {
	init(name: String, type: ControlType, x: CGFloat, y: CGFloat) {
		self.id = UUID()
		self.name = name
		self.type = type
		
		// common fields default
		self.value = nil
		self.stepIndex = nil
		self.options = nil
		self.selectedIndex = nil
		self.isPressed = nil
		
		// specifics default
		self.knobMin = nil
		self.knobMax = nil
		self.stepAngles = nil
		self.stepValues = nil
		self.optionAngles = nil
		self.optionValues = nil
		
		self.onColor = nil
		self.offColor = nil
		self.linkTarget = nil
		self.linkInverted = nil
		self.linkOnIndex = nil
		
		self.sprites = nil
		self.spriteIndex = nil
		
		self.position = CGPoint(x: x, y: y)
		self.x = x
		self.y = y
		
		self.regions = []
	}
}

private extension Bound {
	var isNegInf: Bool { self == .negInfinity }
	var isPosInf: Bool { self == .posInfinity }
}

extension Control {
	/// Normalize a semantic `value` (e.g. dB) to 0…1 using knobMin/knobMax and mapping taper.
	func normalizedValueForMapping(_ v: Double? = nil, mapping: VisualMapping?) -> Double {
//		let value = v ?? self.value ?? 0
//		let loB = knobMin
//		let hiB = knobMax
		let taper = mapping?.taper ?? .linear
		
		switch taper {
			case .decibel:
				// value in dB → linear ratio, then normalize 0…1
				let rVal: Double = pow(10.0, (v ?? self.value ?? 0) / 20.0)
				
				// Safely unwrap bounds (use practical defaults if nil)
				let minDb: Double = (knobMin?.resolve(default: -120)) ?? -120
				let maxDb: Double = (knobMax?.resolve(default:    0)) ??   0
				
				// If min == −∞, resolve() returns a very large negative, and pow(...) underflows to 0 → perfect.
				let rMin: Double = pow(10.0, minDb / 20.0)   // 0 when minDb is −∞
				let rMax: Double = pow(10.0, maxDb / 20.0)   // 1 when maxDb is 0 dB
				
				let denom = max(1e-12, rMax - rMin)
				let t = (rVal - rMin) / denom
				return min(max(t, 0), 1)
				
			case .linear:
				guard let lo = knobMin?.resolve(default: 0),
					  let hi = knobMax?.resolve(default: 1),
					  hi != lo
				else { return 0 }
				let t = ((v ?? self.value ?? 0) - lo) / (hi - lo)
				return min(max(t, 0), 1)
		}
	}
}

// For the Light
extension Control {
	/// Returns the evaluated "on" state for a light, considering links & inversion.
	func lightIsOn(given device: Device) -> Bool {
		// Manual if no link
		guard type == .light else { return isPressed ?? false }
		if let targetId = linkTarget,
		   let target = device.controls.first(where: { $0.id == targetId }) {
			
			var on: Bool = isPressed ?? false
			switch target.type {
				case .button:
					on = target.isPressed ?? false
					
				case .multiSwitch:
					let want = linkOnIndex ?? 0
					on = (target.selectedIndex ?? 0) == want
					
				case .knob, .steppedKnob:
					// Optional: consider "on when > 0"—for now, treat as off.
					on = false
					
				default:
					on = false
			}
			if linkInverted == true { on.toggle() }
			return on
		}
		// No link? Manual switch
		return isPressed ?? false
	}
	
	/// The actual display color this light should use, based on `lightIsOn(...)`.
	func displayColor(in device: Device) -> Color {
		let on = lightIsOn(given: device)
		let onC  = (onColor  ?? CodableColor(.green)).color
		let offC = (offColor ?? CodableColor(.gray)).color
		return on ? onC : offC
	}
}

// Extension for concentric knobs and lit buttons
extension Control {
	// Decibel/linear normalization helpers exist; mirror them per-ring if you need semantics:
	func normalizedOuter(mapping: VisualMapping?) -> Double {
		normalized(v: outerValue,
				   lo: outerMin?.resolve(default: 0),
				   hi: outerMax?.resolve(default: 1),
				   taper: outerTaper ?? mapping?.taper ?? .linear)
	}
	func normalizedInner(mapping: VisualMapping?) -> Double {
		normalized(v: innerValue,
				   lo: innerMin?.resolve(default: 0),
				   hi: innerMax?.resolve(default: 1),
				   taper: innerTaper ?? mapping?.taper ?? .linear)
	}
	
	private func normalized(v: Double?, lo: Double?, hi: Double?, taper: ValueTaper) -> Double {
		switch taper {
			case .linear:
				guard let lo, let hi, hi != lo else { return 0 }
				let t = ((v ?? 0) - lo) / (hi - lo)
				return min(max(t, 0), 1)
			case .decibel:
				let val = pow(10.0, (v ?? 0) / 20.0)
				let minDb = (lo ?? -120)
				let maxDb = (hi ?? 0)
				let rMin = pow(10.0, minDb / 20.0)
				let rMax = pow(10.0, maxDb / 20.0)
				let denom = max(1e-12, rMax - rMin)
				let t = (val - rMin) / denom
				return min(max(t, 0), 1)
		}
	}
	
	/// Lit-button lamp evaluation
	func litButtonLampIsOn(in device: Device) -> Bool {
		guard type == .litButton else { return false }
		if let override = lampOverrideOn { return override }
		if lampFollowsPress ?? true { return isPressed ?? false }
		
		// Otherwise reuse link semantics (same as lights)
		if let targetId = linkTarget,
		   let target = device.controls.first(where: { $0.id == targetId }) {
			var on = false
			switch target.type {
				case .button:      on = target.isPressed ?? false
				case .multiSwitch: on = (target.selectedIndex ?? 0) == (linkOnIndex ?? 0)
				default:           on = false
			}
			if linkInverted == true { on.toggle() }
			return on
		}
		return isPressed ?? false
	}
}

extension VisualMapping {
	/// Convenience: compute rotation angle for current control value
	func rotationDegrees(for control: Control) -> Double {
		let t = control.normalizedValueForMapping(mapping: self)
		let a0 = degMin ?? -135
		let a1 = degMax ??  135
		return a0 + (a1 - a0) * t
	}
	
	func rotationDegrees(for value: Double?,
						 lo: Bound? = nil,
						 hi: Bound? = nil,
						 taper: ValueTaper? = nil) -> Double {
		let t: Double
		switch taper ?? .linear {
			case .linear:
				guard let loV = lo?.resolve(default: 0) ?? 0 as Double?,
					  let hiV = hi?.resolve(default: 1) ?? 1 as Double?,
					  hiV != loV else { t = 0; break }
				t = ((value ?? 0) - loV) / (hiV - loV)
			case .decibel:
				let val = pow(10.0, (value ?? 0) / 20.0)
				let minDb = lo?.resolve(default: -120) ?? -120
				let maxDb = hi?.resolve(default: 0) ?? 0
				let rMin = pow(10.0, minDb / 20.0)
				let rMax = pow(10.0, maxDb / 20.0)
				let denom = max(1e-12, rMax - rMin)
				t = (val - rMin) / denom
		}
		let clamped = min(max(t, 0), 1)
		let a0 = degMin ?? -135
		let a1 = degMax ??  135
		return a0 + (a1 - a0) * clamped
	}
}


// MARK: - Continuous Knob
struct Knob: View {
    @Binding var value: Double // 0.0 ... 1.0
    var label: String
	
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [.gray.opacity(0.8), .black],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .shadow(radius: 4)
            
            Circle()
                .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
            
            // Indicator line
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: 12)
                .offset(y: -25)
                .rotationEffect(.degrees(value * 270 - 135))
        }
        .frame(width: 60, height: 60)
        .gesture(DragGesture().onChanged { drag in
            let delta = -Double(drag.translation.height) / 150
            value = min(max(value + delta, 0), 1)
        })
        .help("\(label): \(String(format: "%.2f", value))")
    }
}

// MARK: - Stepped Knob
struct SteppedKnob: View {
    @Binding var index: Int
    let steps: Int
    var label: String
    var stepLabels: [String]?
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [.black, .gray],
                                   center: .center, startRadius: 5, endRadius: 30)
                )
                .shadow(radius: 4)
            
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 12)
                .offset(y: -25)
                .rotationEffect(.degrees(Double(index) / Double(steps - 1) * 270 - 135))
        }
        .frame(width: 60, height: 60)
        .gesture(DragGesture().onEnded { drag in
            if drag.translation.height < 0 {
                index = min(index + 1, steps - 1)
            } else {
                index = max(index - 1, 0)
            }
        })
        .help("\(label): \(stepLabels?[index] ?? "\(index)")")
    }
}

// MARK: - Multi-Position Switch
struct MultiSwitch: View {
    @Binding var selectedIndex: Int
    let options: [String]
    var label: String
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i])
                    .font(.caption2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == selectedIndex ? Color.green : Color.gray.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.black.opacity(0.8), lineWidth: 1)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2)) {
                            selectedIndex = i
                        }
                    }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.9))
        .cornerRadius(6)
        .shadow(radius: 2)
        .help("\(label): \(options[selectedIndex])")
    }
}

// MARK: - Button
struct GearButton: View {
    @Binding var isPressed: Bool
    var label: String
    var onLabel: String = "On"
    var offLabel: String = "Off"
    var onColor: Color = .red
    var offColor: Color = .gray.opacity(0.8)
    
    var body: some View {
        Circle()
            .fill(isPressed ? onColor : offColor)
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 2, y: 2)
            .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 2))
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2), value: isPressed)
            .onTapGesture { isPressed.toggle() }
            .help("\(label): \(isPressed ? onLabel : offLabel)")
    }
}

// MARK: - Status Light
struct StatusLight: View {
	@Binding var isOn: Bool
	var label: String
	var onLabel: String = "On"
	var offLabel: String = "Off"
	var onColor: Color = .green
	var indicatingControl: Control.ID
	
	var body: some View {
		Circle()
			.fill(isOn ? onColor : .gray.opacity(0.6))
			.frame(width: 16, height: 16)
			.overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
			.shadow(radius: isOn ? 3 : 0)
			.help("\(label): " + (isOn ? onLabel : offLabel))
	}
}

// MARK: - Concentric Knob
struct ConcentricKnob: View {
	@Binding var outer: Double      // e.g., Gain   (0…1)
	@Binding var inner: Double      // e.g., Q      (0…1)
	var outerLabel: String = "Gain"
	var innerLabel: String = "Q"
	
	var body: some View {
		ZStack {
			// Outer ring (bigger)
			Knob(value: $outer, label: outerLabel)
				.frame(width: 64, height: 64)
			
			// Inner ring (smaller), on top
			Knob(value: $inner, label: innerLabel)
				.frame(width: 42, height: 42)
		}
		.frame(width: 64, height: 64)
	}
}

// MARK: - Lit Button
struct LitButton: View {
	@Binding var isPressed: Bool
	var lampOn: Bool
	var onColor: Color
	var offColor: Color
	
	var body: some View {
		ZStack {
			// Button body
			GearButton(isPressed: $isPressed, label: "Button")
				.frame(width: 42, height: 42)
			
			// Integrated lamp “glow”
			Circle()
				.strokeBorder(lampOn ? onColor : offColor, lineWidth: lampOn ? 3 : 1)
				.shadow(radius: lampOn ? 6 : 0)
				.padding(2)
		}
		.frame(width: 42, height: 42)
	}
}

