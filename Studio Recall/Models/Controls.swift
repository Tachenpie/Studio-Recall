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
	
	enum SpriteMode: String, Codable {
		case atlasGrid
		case frames
	}
	
	/// Public accessor for sprite mode.
	/// Always non-optional. Defaults to `.frames` if no mode has been set.
	var spriteMode: SpriteMode {
		get { _spriteModeStorage ?? .frames }   // ✅ default to frames
		set { _spriteModeStorage = newValue }
	}
	
	// Backing store using raw string for Codable compatibility
	private var _spriteModeStorage: SpriteMode? {
		get { _spriteModeRaw.flatMap { SpriteMode(rawValue: $0) } }
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
					   scale: Double = 1.0,
					   mode: SpriteMode = .frames,
					   frames: [Data]? = nil,
					   indices: [Int]? = nil) -> Self
	{
		var m = Self.init(kind: .sprite, degMin: nil, degMax: nil, pivot: pivot, scalarRange: nil)
		m.spriteAtlasPNG = atlasPNG
		m.spriteCols = cols; m.spriteRows = rows
		m.pivot = pivot
		m.spritePivot = spritePivot
		m.spriteScale = scale
		m.spriteMode = mode
		m.spriteFrames = frames
		m.spriteIndices = indices
		return m
	}
}

extension VisualMapping {
	var hasEmbeddedSpriteData: Bool {
		(spriteAtlasPNG != nil) || ((spriteFrames?.isEmpty == false))
	}
}

extension VisualMapping {
	mutating func normalizeSpriteIndices() {
		guard let frames = spriteFrames else { return }
		if spriteIndices == nil {
			// Default mapping: 0, 1, 2...
			spriteIndices = Array(0..<frames.count)
		} else if spriteIndices!.count < frames.count {
			// Pad missing values with identity mapping
			let start = spriteIndices!.count
			spriteIndices!.append(contentsOf: start..<frames.count)
		} else if spriteIndices!.count > frames.count {
			// Trim extra indices
			spriteIndices = Array(spriteIndices!.prefix(frames.count))
		}
	}
}

extension VisualMapping {
	mutating func ensureSpriteOffsets() {
		let count = spriteFrames?.count ?? 0
		if spriteOffsets == nil {
			spriteOffsets = Array(repeating: .zero, count: count)
		} else if spriteOffsets!.count < count {
			spriteOffsets!.append(contentsOf: Array(repeating: .zero, count: count - spriteOffsets!.count))
		}
	}
}

enum ImageRegionShape: String, Codable { case rect, circle }

struct ImageRegion: Codable, Equatable {
	/// Normalized rect (0–1) in canvas/view coordinates
	var rect: CGRect
	/// How to transform the cropped patch as the control changes
	var mapping: VisualMapping?
	var shape: ImageRegionShape = .circle
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
	
	// Not persisted, runtime only
	var showLabel: Bool = false
    
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
	
	// Button and Lit Button
	var onLabel: String? = nil
	var offLabel: String? = nil
	
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
	enum SpriteLayout: String, Codable {
		case vertical
		case horizontal
	}
	var sprites: ControlSpriteSet? // nil = no sprites (use patch)
	var spriteIndex: Int?          // derive from pressed/index when present
	var spriteLayout: SpriteLayout = .vertical
	var frameMapping: [Int : Int]? = nil
	
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
		// identity
		case id, name, type
		
		// common value storage
		case value, stepIndex, options, selectedIndex, isPressed
		
		// stepped/multiswitch metadata
		case stepAngles, stepValues, optionAngles, optionValues
		
		// button/litbutton labels
		case onLabel, offLabel
		
		// knob ranges/taper
		case knobMin, knobMax
		
		// concentric values + ranges/tapers/mappings/labels
		case outerValue, innerValue
		case outerMin, outerMax, innerMin, innerMax
		case outerTaper, innerTaper
		case outerMapping, innerMapping
		case outerLabel, innerLabel
		
		// light & lamp
		case onColor, offColor
		case linkTarget, linkInverted, linkOnIndex
		case lampOnColor, lampOffColor, lampFollowsPress, lampOverrideOn
		
		// sprites
		case sprites, spriteIndex
		
		// layout/position
		case position, x, y
		
		// regions (new) + region (legacy)
		case regions
		case region
	}
	
	// Custom decode to migrate old -> new
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		
		// identity
		id   = try c.decode(UUID.self, forKey: .id)
		name = try c.decode(String.self, forKey: .name)
		type = try c.decode(ControlType.self, forKey: .type)
		
		// common values
		value         = try c.decodeIfPresent(Double.self, forKey: .value)
		stepIndex     = try c.decodeIfPresent(Int.self, forKey: .stepIndex)
		options       = try c.decodeIfPresent([String].self, forKey: .options)
		selectedIndex = try c.decodeIfPresent(Int.self, forKey: .selectedIndex)
		isPressed     = try c.decodeIfPresent(Bool.self, forKey: .isPressed)
		
		// stepped/multi arrays
		stepAngles    = try c.decodeIfPresent([Double].self, forKey: .stepAngles)
		stepValues    = try c.decodeIfPresent([Double].self, forKey: .stepValues)
		optionAngles  = try c.decodeIfPresent([Double].self, forKey: .optionAngles)
		optionValues  = try c.decodeIfPresent([Double].self, forKey: .optionValues)
		
		// button labels
		onLabel  = try c.decodeIfPresent(String.self, forKey: .onLabel)
		offLabel = try c.decodeIfPresent(String.self, forKey: .offLabel)
		
		// knob ranges
		knobMin = try c.decodeIfPresent(Bound.self, forKey: .knobMin)
		knobMax = try c.decodeIfPresent(Bound.self, forKey: .knobMax)
		
		// concentric
		outerValue = try c.decodeIfPresent(Double.self, forKey: .outerValue)
		innerValue = try c.decodeIfPresent(Double.self, forKey: .innerValue)
		outerMin   = try c.decodeIfPresent(Bound.self,  forKey: .outerMin)
		outerMax   = try c.decodeIfPresent(Bound.self,  forKey: .outerMax)
		innerMin   = try c.decodeIfPresent(Bound.self,  forKey: .innerMin)
		innerMax   = try c.decodeIfPresent(Bound.self,  forKey: .innerMax)
		outerTaper = try c.decodeIfPresent(ValueTaper.self, forKey: .outerTaper)
		innerTaper = try c.decodeIfPresent(ValueTaper.self, forKey: .innerTaper)
		outerMapping = try c.decodeIfPresent(VisualMapping.self, forKey: .outerMapping)
		innerMapping = try c.decodeIfPresent(VisualMapping.self, forKey: .innerMapping)
		outerLabel   = try c.decodeIfPresent(String.self, forKey: .outerLabel)
		innerLabel   = try c.decodeIfPresent(String.self, forKey: .innerLabel)
		
		// light & lamp
		onColor        = try c.decodeIfPresent(CodableColor.self, forKey: .onColor)
		offColor       = try c.decodeIfPresent(CodableColor.self, forKey: .offColor)
		linkTarget     = try c.decodeIfPresent(UUID.self, forKey: .linkTarget)
		linkInverted   = try c.decodeIfPresent(Bool.self, forKey: .linkInverted)
		linkOnIndex    = try c.decodeIfPresent(Int.self, forKey: .linkOnIndex)
		lampOnColor    = try c.decodeIfPresent(CodableColor.self, forKey: .lampOnColor)
		lampOffColor   = try c.decodeIfPresent(CodableColor.self, forKey: .lampOffColor)
		lampFollowsPress = try c.decodeIfPresent(Bool.self, forKey: .lampFollowsPress)
		lampOverrideOn   = try c.decodeIfPresent(Bool.self, forKey: .lampOverrideOn)
		
		// sprites
		sprites     = try c.decodeIfPresent(ControlSpriteSet.self, forKey: .sprites)
		spriteIndex = try c.decodeIfPresent(Int.self, forKey: .spriteIndex)
		
		// layout
		position = try c.decodeIfPresent(CGPoint.self, forKey: .position) ?? CGPoint(x: 0.5, y: 0.5)
		x = try c.decodeIfPresent(CGFloat.self, forKey: .x) ?? position.x
		y = try c.decodeIfPresent(CGFloat.self, forKey: .y) ?? position.y
		
		// regions (new) + region (legacy)
		regions = try c.decodeIfPresent([ImageRegion].self, forKey: .regions) ?? []
		if regions.isEmpty, let legacy = try c.decodeIfPresent(ImageRegion.self, forKey: .region) {
			regions = [legacy]
		}
	}

	
	// Encode both (for backward compat, optional)
	func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		
		// identity
		try c.encode(id, forKey: .id)
		try c.encode(name, forKey: .name)
		try c.encode(type, forKey: .type)
		
		// common values
		try c.encodeIfPresent(value, forKey: .value)
		try c.encodeIfPresent(stepIndex, forKey: .stepIndex)
		try c.encodeIfPresent(options, forKey: .options)
		try c.encodeIfPresent(selectedIndex, forKey: .selectedIndex)
		try c.encodeIfPresent(isPressed, forKey: .isPressed)
		
		// stepped/multi arrays
		try c.encodeIfPresent(stepAngles, forKey: .stepAngles)
		try c.encodeIfPresent(stepValues, forKey: .stepValues)
		try c.encodeIfPresent(optionAngles, forKey: .optionAngles)
		try c.encodeIfPresent(optionValues, forKey: .optionValues)
		
		// button labels
		try c.encodeIfPresent(onLabel, forKey: .onLabel)
		try c.encodeIfPresent(offLabel, forKey: .offLabel)
		
		// knob ranges
		try c.encodeIfPresent(knobMin, forKey: .knobMin)
		try c.encodeIfPresent(knobMax, forKey: .knobMax)
		
		// concentric
		try c.encodeIfPresent(outerValue, forKey: .outerValue)
		try c.encodeIfPresent(innerValue, forKey: .innerValue)
		try c.encodeIfPresent(outerMin,   forKey: .outerMin)
		try c.encodeIfPresent(outerMax,   forKey: .outerMax)
		try c.encodeIfPresent(innerMin,   forKey: .innerMin)
		try c.encodeIfPresent(innerMax,   forKey: .innerMax)
		try c.encodeIfPresent(outerTaper, forKey: .outerTaper)
		try c.encodeIfPresent(innerTaper, forKey: .innerTaper)
		try c.encodeIfPresent(outerMapping, forKey: .outerMapping)
		try c.encodeIfPresent(innerMapping, forKey: .innerMapping)
		try c.encodeIfPresent(outerLabel, forKey: .outerLabel)
		try c.encodeIfPresent(innerLabel, forKey: .innerLabel)
		
		// light & lamp
		try c.encodeIfPresent(onColor,  forKey: .onColor)
		try c.encodeIfPresent(offColor, forKey: .offColor)
		try c.encodeIfPresent(linkTarget,   forKey: .linkTarget)
		try c.encodeIfPresent(linkInverted, forKey: .linkInverted)
		try c.encodeIfPresent(linkOnIndex,  forKey: .linkOnIndex)
		try c.encodeIfPresent(lampOnColor,     forKey: .lampOnColor)
		try c.encodeIfPresent(lampOffColor,    forKey: .lampOffColor)
		try c.encodeIfPresent(lampFollowsPress, forKey: .lampFollowsPress)
		try c.encodeIfPresent(lampOverrideOn,   forKey: .lampOverrideOn)
		
		// sprites
		try c.encodeIfPresent(sprites,     forKey: .sprites)
		try c.encodeIfPresent(spriteIndex, forKey: .spriteIndex)
		
		// layout
		try c.encode(position, forKey: .position)
		try c.encode(x, forKey: .x)
		try c.encode(y, forKey: .y)
		
		// regions (new) + region (legacy one)
		try c.encode(regions, forKey: .regions)
		if let first = regions.first {
			try c.encode(first, forKey: .region)
		}
	}
	
	func bounds(in canvasSize: CGSize) -> CGRect {
		guard let first = regions.first else {
			return CGRect(
				x: x * canvasSize.width - 20,
				y: y * canvasSize.height - 20,
				width: 40, height: 40
			)
		}
		return CGRect(
			x: first.rect.minX * canvasSize.width,
			y: first.rect.minY * canvasSize.height,
			width: first.rect.width * canvasSize.width,
			height: first.rect.height * canvasSize.height
		)
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
		
		self.onLabel = "On"
		self.offLabel = "Off"
		
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
		
		if type == .concentricKnob {
			self.outerMin = .finite(0)
			self.outerMax = .finite(10)
			self.outerValue = 5.0
			self.outerTaper = .linear
			self.innerMin = .negInfinity
			self.innerMax = .finite(16)
			self.innerValue = 5.0
			self.innerTaper = .decibel
		}
		
		self.regions = []
	}
}

private extension Bound {
	var isNegInf: Bool { self == .negInfinity }
	var isPosInf: Bool { self == .posInfinity }
}

extension Control {
	func boundsNormalized() -> CGRect {
		// assume regions are already normalized
		regions.reduce(CGRect.null) { $0.union($1.rect) }
	}
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
	mutating func ensureConcentricRegions() {
		guard type == .concentricKnob else { return }
		
		if regions.count < 2 {
			// Outer region (big circle, full bounds)
			let outer = ImageRegion(
				rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
				mapping: .rotate(min: -135, max: 135,
								 pivot: CGPoint(x: 0.5, y: 0.5),
								 taper: .linear),
				shape: .circle
			)
			
			// Inner region (smaller circle inside)
			let inner = ImageRegion(
				rect: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3),
				mapping: .rotate(min: -135, max: 135,
								 pivot: CGPoint(x: 0.5, y: 0.5),
								 taper: .linear),
				shape: .circle
			)
			
			regions = [outer, inner]
		}
	}
}

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

extension Control {
	/// Bumps when any UI-affecting value changes.
	var renderKey: String {
		switch type {
			case .knob:
				return "knob:\(id)-\(value ?? 0)"
			case .steppedKnob:
				return "step:\(id)-\(stepIndex ?? 0)"
			case .multiSwitch:
				return "msw:\(id)-\(selectedIndex ?? 0)"
			case .button:
				return "btn:\(id)-\((isPressed ?? false) ? 1 : 0)"
			case .light:
				// If you prefer lamp logic, you can use `lightIsOn(given:)` at call-sites.
				return "lit:\(id)-\((isPressed ?? false) ? 1 : 0)"
			case .concentricKnob:
				return "ck:\(id)-\(outerValue ?? 0)-\(innerValue ?? 0)"
			case .litButton:
				return "lbtn:\(id)-\((isPressed ?? false) ? 1 : 0)"
		}
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
	
	// pixels per step of drag movement
	private let pixelsPerStep: CGFloat = 30
	
	var body: some View {
		ZStack {
			Circle()
				.fill(
					RadialGradient(colors: [.black, .gray],
								   center: .center,
								   startRadius: 5,
								   endRadius: 30)
				)
				.shadow(radius: 4)
			
			// indicator line
			Rectangle()
				.fill(Color.green)
				.frame(width: 2, height: 12)
				.offset(y: -25)
				.rotationEffect(.degrees(Double(index) / Double(steps - 1) * 270 - 135))
		}
		.frame(width: 60, height: 60)
		.highPriorityGesture(
			DragGesture(minimumDistance: 5).onEnded { drag in
				let stepDelta = Int(-drag.translation.height / pixelsPerStep)
				let newIndex = index + stepDelta
				index = min(max(newIndex, 0), steps - 1)
				print("New index: \(index)")
			}
		)
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

// MARK: - Canonical display formatting for control values
extension Control {
	/// Returns one or more display lines for this control using the current instance state.
	/// Handles absolute value conversions and labels (incl. concentric knobs).
	func displayLines(for instance: DeviceInstance) -> [String] {
		let value = instance.controlStates[id] ?? ControlValue.initialValue(for: self)
		return displayLines(for: value)
	}
	
	/// Overload if you already have a ControlValue on hand.
	func displayLines(for value: ControlValue) -> [String] {
		switch (type, value) {
			case (.concentricKnob, .concentricKnob(let outer, let inner)):
				let oAbs = unitToAbsolute(outer, lo: outerMin, hi: outerMax, taper: outerTaper)
				let iAbs = unitToAbsolute(inner, lo: innerMin, hi: innerMax, taper: innerTaper)
				let oLabel = outerLabel ?? "Outer"
				let iLabel = innerLabel ?? "Inner"
				return [
					"\(oLabel): " + numberString(oAbs, decimals: 2),
					"\(iLabel): " + numberString(iAbs, decimals: 2)
				]
				
			case (.knob, .knob(let u)):
				let abs = unitToAbsolute(u, lo: knobMin, hi: knobMax, taper: regions.first?.mapping?.taper)
				return [numberString(abs, decimals: 2)]
				
			case (.steppedKnob, .steppedKnob(let idx)):
				if let labels = options, labels.indices.contains(idx) {
					return [labels[idx]]
				} else {
					return ["\(idx)"]
				}
				
			case (.multiSwitch, .multiSwitch(let idx)):
				if let opts = options, opts.indices.contains(idx) {
					return [opts[idx]]
				} else {
					return ["\(idx)"]
				}
				
			case (.button, .button(let pressed)):
				return [pressed ? (onLabel ?? "On") : (offLabel ?? "Off")]
				
			case (.light, .light(let lit)):
				return [lit ? (onLabel ?? "On") : (offLabel ?? "Off")]
				
			case (.litButton, .litButton(let pressed)):
				return [pressed ? (onLabel ?? "On") : (offLabel ?? "Off")]
				
			default:
				// Mismatched pair (e.g., stale state type) — fall back gracefully
				return ["—"]
		}
	}
	
	// MARK: - Local helpers
	
	/// Convert unit value [0..1] into absolute using this app's tapers/bounds.
	private func unitToAbsolute(_ u: Double,
								lo: Bound?,
								hi: Bound?,
								taper: ValueTaper?) -> Double {
		let loV = (lo ?? .finite(0)).asFinite(-Double.greatestFiniteMagnitude)
		let hiV = (hi ?? .finite(1)).asFinite(Double.greatestFiniteMagnitude)
		
		let clampedU = min(max(u, 0.0), 1.0)
		
		switch taper ?? .linear {
			case .linear:
				return loV + (hiV - loV) * clampedU
//			case .log:
//				// Simple log-ish mapping (adjust if you already use a different one)
//				let minV = max(1e-6, loV)
//				let maxV = max(minV * 1.000001, hiV)
//				let logMin = log(minV)
//				let logMax = log(maxV)
//				return exp(logMin + (logMax - logMin) * clampedU)
			case .decibel:
				// Example dB mapping: treat lo/hi as dB and interpolate linearly
				return loV + (hiV - loV) * clampedU
		}
	}
	
	private func numberString(_ x: Double, decimals: Int) -> String {
		String(format: "%.\(decimals)f", x)
	}
}

private extension Bound {
	func asFinite(_ fallback: Double) -> Double {
		switch self {
			case .finite(let v): return v
			case .negInfinity:   return -Double.greatestFiniteMagnitude
			case .posInfinity:   return  Double.greatestFiniteMagnitude
		}
	}
}

