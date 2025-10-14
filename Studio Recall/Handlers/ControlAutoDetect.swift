//
//  ControlDraft.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


//  ControlAutoDetect.swift
//  Studio Recall
//
//  A lightweight, CoreGraphics-only heuristic detector for faceplates.
//  Works entirely in pixel space (image-native), no CoreML required.

import Foundation
import CoreGraphics
import CoreImage
import AppKit

// Very fast approximate luminance (0..1) from 8-bit RGBA bytes
@inline(__always)
private func lum(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Float {
	return Float(0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
}

/// Build a flat RGBA8 buffer once so we can sample quickly.
private func rgbaBuffer(from cg: CGImage) -> (data: [UInt8], stride: Int)? {
	let w = cg.width, h = cg.height
	var data = [UInt8](repeating: 0, count: w*h*4)
	let cs = CGColorSpaceCreateDeviceRGB()
	guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
							  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
	else { return nil }
	// Draw upright into buffer (CoreGraphics default origin is bottom-left; our overlay logic expects top-left).
	ctx.translateBy(x: 0, y: CGFloat(h))
	ctx.scaleBy(x: 1, y: -1)
	ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
	return (data, w*4)
}

/// Sample mean luminance of points on a ring [r0, r1] around center `c`.
/// Uses 48 directions; fast enough but robust.
private func ringMeanLuma(buffer: [UInt8], stride: Int, w: Int, h: Int,
						  c: CGPoint, r0: CGFloat, r1: CGFloat) -> Float {
	let K = 32
	var sum: Float = 0
	var cnt = 0
	for k in 0..<K {
		let a = (Double(k) / Double(K)) * 2.0 * Double.pi
		let ca = cos(a), sa = sin(a)
		// take two samples along the ray to average the ring
		for t in 0..<1 {
			let rr = Double(r0) * 0.6 + (t == 0 ? Double(r0) : Double(r1)) * 0.4
			let x = Int(round(Double(c.x) + rr * ca))
			let y = Int(round(Double(c.y) + rr * sa))
			if x <= 0 || y <= 0 || x >= w-1 || y >= h-1 { continue }
			let idx = y*stride + x*4
			sum += lum(buffer[idx], buffer[idx+1], buffer[idx+2])
			cnt += 1
		}
	}
	return cnt > 0 ? sum / Float(cnt) : 1.0
}


// MARK: Draft model (pixel-space)
struct ControlDraft: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case knob, steppedKnob, multiSwitch, button, light, litButton, concentricKnob }
    var id = UUID()
    var kind: /*Kind*/ ControlType
    var rect: CGRect          // pixel-space bounding rect (origin at top-left of CGImage)
    var center: CGPoint       // pixel-space center
    var radius: CGFloat?      // if circular
    var label: String
    var confidence: Double    // 0…1
}

enum ControlAutoDetect {
	struct Config {
		// --- global / legacy knobs ---
		var downscaleMax: CGFloat        = 720
		var knobMinDiameterPx: CGFloat   = 28
		var knobMaxDiameterPx: CGFloat   = 200
		var limitSearchToBands: Bool     = true
		
		// enable/disable the Hough circle pass (blob pass still runs)
		var enableCirclePass: Bool       = true
		
		// --- blob pass classification thresholds (scaled-space unless noted) ---
		// Minimum connected-component area (in scaled pixels^2) to consider.
		var areaMinPx: CGFloat           = 18 * 18
		// Anything circular below this diameter (FULL px) is treated as an LED, not a knob.
		var ledMaxDiameterPx: CGFloat    = 36
		/// Roundness tolerance for “round-enough” shapes (1 - roundness ≤ tol)
		var rectRoundnessTolerance: CGFloat = 0.28
		
		// === New, slider-driven tuning ===
		// Band crop padding (scaled-space, each side)
		var bandPadFrac: CGFloat         = 0.18          // 0.12 (strict) … 0.24 (loose)
		// Max radius as a fraction of local band height (scaled-space)
		var bandMaxRFrac: CGFloat        = 0.40          // 0.34 … 0.44
		
		// Radial edge agreement (Hough vetting)
		var covBase: Float               = 0.22          // 0.32 … 0.18
		var aliBase: Float               = 0.54          // 0.64 … 0.50
		// Luma contrast floor between outer and inner rings
		var contrastFloor: Float         = 0.024         // 0.032 … 0.020
		
		// Printed “0” ring rejection (small circles only; FULL px)
		var smallInkMaxDiameter: CGFloat = 60
		var ringInkCutSmall: Float       = 0.070         // looser => fewer rejections
		
		// Per-band size clamp (applies only when sizes are tight)
		var sizeClampLo: CGFloat         = 0.60          // 0.70 … 0.55
		var sizeClampHi: CGFloat         = 1.40          // 1.30 … 1.55
		var sizeClampEnableSpread: CGFloat = 1.45        // if p90/p10 <= this, clamp
		
		// Expected counts → controls “rescue” behaviour
		var wantPerBandBase: Int         = 6             // 4 … 8
		var wantPerBandPer1000px: Int    = 3             // 2 … 5
		
		// Cross-band alignment (column reconcile)
		var xTolPx: CGFloat              = 30            // 24 … 36 (cluster tol)
		var maxGridSnapShiftPx: CGFloat  = 18            // 10 … 24
		
		// Factory preset from the UI slider (0…1). Higher = more recall.
		static func fromSensitivity(_ sRaw: Double) -> Config {
			let s = max(0.0, min(1.0, sRaw))
			let t = CGFloat(pow(s, 0.85))
			let tf = Float(t)
			func lerp<T: BinaryFloatingPoint>(_ a: T, _ b: T, _ u: T) -> T { a + (b - a) * u }
			
			var c = Config()
			
			c.bandPadFrac      = lerp(0.12, 0.24, t)
			c.bandMaxRFrac     = lerp(0.34, 0.44, t)
			
			c.covBase          = lerp(0.32, 0.18, tf)
			c.aliBase          = lerp(0.64, 0.50, tf)
			c.contrastFloor    = lerp(0.032, 0.020, tf)
			
			c.smallInkMaxDiameter = lerp(52.0, 64.0, t)
			c.ringInkCutSmall  = lerp(0.055, 0.085, tf)
			
			c.sizeClampLo      = lerp(0.70, 0.55, t)
			c.sizeClampHi      = lerp(1.30, 1.55, t)
			c.sizeClampEnableSpread = lerp(1.35, 1.55, t)
			
			c.wantPerBandBase  = Int(round(lerp(4.0, 8.0, t)))
			c.wantPerBandPer1000px = Int(round(lerp(2.0, 5.0, t)))
			
			c.xTolPx           = lerp(24.0, 36.0, t)
			c.maxGridSnapShiftPx = lerp(10.0, 24.0, t)
			
			// classic global guard, mildly sensitivity-scaled
			c.knobMinDiameterPx = lerp(30.0, 26.0, t)
			c.knobMaxDiameterPx = lerp(180.0, 210.0, t)
			
			return c
		}
	}
	
	/// Returns up to two NON-OVERLAPPING horizontal bands in the mask's
	/// **scaled, top-left** coordinate space. If peak picking collapses toward
	/// the interior, we fall back to quartiles so top/bottom rows are covered.
	static func rowBands(from mask: CGImage) -> [ClosedRange<CGFloat>] {
		let w = mask.width, h = mask.height
		guard let data = mask.dataProvider?.data as Data? else { return [] }
		let g = Array(data) // grayscale 0/255
		
		// --- 1) estimate plate interior (top+bottom) by column medians ---
		var tops = [Int](), bots = [Int]()
		tops.reserveCapacity(w); bots.reserveCapacity(w)
		for x in 0..<w {
			var t = -1, b = -1, p = x
			for y in 0..<h { if g[p] != 0 { t = y; break }; p += w }
			if t != -1 {
				p = x + (h-1)*w
				for y in stride(from: h-1, through: 0, by: -1) { if g[p] != 0 { b = y; break }; p -= w }
			}
			if t != -1, b != -1, b > t { tops.append(t); bots.append(b) }
		}
		guard !tops.isEmpty else { return [] }
		func med(_ a: [Int]) -> Int { var s = a; s.sort(); return s[s.count/2] }
		
		let yTop = med(tops), yBot = med(bots)
		if yBot - yTop < max(24, h/6) { return [] }
		
		// Interior window (keep generous; we’ll NMS peaks but also have a fallback)
		let interiorH = yBot - yTop
		let shrink = max(4, Int(Double(interiorH) * 0.06))
		let yMin = max(0, yTop + shrink)
		let yMax = min(h-1, yBot - shrink)
		guard yMax > yMin else { return [] }
		
		// --- 2) edge-density by row + smoothing ---
		var hist = [Double](repeating: 0, count: h)
		for y in yMin...yMax {
			var sum = 0; let base = y*w
			for x in 0..<w { sum += (g[base + x] != 0) ? 1 : 0 }
			hist[y] = Double(sum)
		}
		func boxSmooth(_ a: [Double], r: Int) -> [Double] {
			var out = a; let R = max(1, r)
			for y in yMin...yMax {
				let lo = max(yMin, y - R), hi = min(yMax, y + R)
				var s = 0.0
				for k in lo...hi { s += a[k] }
				out[y] = s / Double(hi - lo + 1)
			}
			return out
		}
		var sm = boxSmooth(hist, r: 3); sm = boxSmooth(sm, r: 3)
		
		// --- 3) peak picking with NMS ---
		struct Peak { let y: Int; let v: Double }
		var cands: [Peak] = []
		if yMax - yMin >= 3 {
			for y in (yMin+1)..<(yMax-1) where sm[y] > sm[y-1] && sm[y] > sm[y+1] {
				cands.append(Peak(y: y, v: sm[y]))
			}
		}
		cands.sort { $0.v > $1.v }
		
		let minSep = max(6, Int(Double(interiorH) * 0.22))
		let nmsR   = max(3, Int(Double(interiorH) * 0.12))
		
		var peaks: [Int] = []
		var blocked = [Bool](repeating: false, count: h)
		for p in cands {
			if blocked[p.y] { continue }
			peaks.append(p.y)
			let lo = max(yMin, p.y - nmsR), hi = min(yMax, p.y + nmsR)
			for y in lo...hi { blocked[y] = true }
			if peaks.count == 2 { break }
		}
		
		// --- 4) turn peaks into *disjoint* bands ---
		func makeBand(center y: Int, half: Int) -> ClosedRange<CGFloat> {
			let a = max(yMin, y - half)
			let b = min(yMax, y + half)
			return CGFloat(a)...CGFloat(max(a+1, b))
		}
		
		let half = max(14, Int(Double(interiorH) * 0.13)) // total band ≈ 0.26×interior
		var bands: [ClosedRange<CGFloat>] = []
		
		if peaks.count >= 2 {
			peaks.sort()
			var b0 = makeBand(center: peaks[0], half: half)
			var b1 = makeBand(center: peaks[1], half: half)
			// enforce disjointness by trimming toward the centers
			if b0.upperBound > b1.lowerBound {
				let ov = Int(b0.upperBound - b1.lowerBound)
				let trim = (ov / 2) + 1
				b0 = CGFloat(Int(b0.lowerBound)) ... CGFloat(Int(b0.upperBound) - trim)
				b1 = CGFloat(Int(b1.lowerBound) + trim) ... CGFloat(Int(b1.upperBound))
			}
			bands = [b0, b1]
		} else if peaks.count == 1 {
			bands = [ makeBand(center: peaks[0], half: half) ]
		}
		
		// --- 5) Check if this is truly a single-row device (merge bands if appropriate) ---
		// If we have 2 bands but the gap between them is mostly empty, it's likely a single-row device
		// where the peak detection created artificial bands at top/bottom.
		if bands.count == 2 {
			let c0 = (bands[0].lowerBound + bands[0].upperBound) * 0.5
			let c1 = (bands[1].lowerBound + bands[1].upperBound) * 0.5
			let gapStart = Int(bands[0].upperBound)
			let gapEnd = Int(bands[1].lowerBound)

			// Sample the gap between bands to see if it's mostly empty
			if gapEnd > gapStart {
				var gapDensity = 0
				for y in gapStart...gapEnd {
					let base = y * w
					for x in 0..<w {
						if g[base + x] != 0 { gapDensity += 1 }
					}
				}
				let gapArea = (gapEnd - gapStart + 1) * w
				let gapFill = Double(gapDensity) / Double(max(1, gapArea))

#if DEBUG
				print("rowBands: gap analysis y=\(gapStart)..\(gapEnd) fill=\(String(format: "%.1f%%", gapFill*100))")
#endif

				// If gap is very sparse (< 5% filled), merge bands into single band
				// Relaxed from 3% to 5% to catch more single-row devices
				if gapFill < 0.05 {
					let mergedCenter = (c0 + c1) * 0.5
					let expandedHalf = max(half, Int(Double(interiorH) * 0.35))
					bands = [makeBand(center: Int(mergedCenter), half: expandedHalf)]
#if DEBUG
					print("rowBands: merged 2 bands → 1 (gap was sparse)")
#endif
				}
			}
		}

		// --- 6) Fallback / correction: if bands are too central, force quartiles ---
		func frac(_ y: CGFloat) -> Double { Double((y - CGFloat(yMin)) / CGFloat(max(1, yMax - yMin))) }
		let needFallback: Bool = {
			guard bands.count == 2 else {
				// If we have 1 band, it's likely a single-row device - keep it!
				// If we have 0 bands, we need a fallback.
				return bands.count == 0
			}
			let c0 = (bands[0].lowerBound + bands[0].upperBound) * 0.5
			let c1 = (bands[1].lowerBound + bands[1].upperBound) * 0.5
			let f0 = frac(c0), f1 = frac(c1)
			let sepOK = abs(c1 - c0) >= CGFloat(minSep)
			// if both centers live in the central 30-70% OR separation is too small → fallback
			let central = (f0 > 0.30 && f0 < 0.70) && (f1 > 0.30 && f1 < 0.70)
			return central || !sepOK
		}()

		if needFallback {
			// If we already have 1 band (single-row device), expand it to cover more area
			if bands.count == 1 {
				let existingCenter = (bands[0].lowerBound + bands[0].upperBound) * 0.5
				// Make the band taller for single-row devices (≈ 50% of interior height)
				let expandedHalf = max(half, Int(Double(interiorH) * 0.25))
				bands = [makeBand(center: Int(existingCenter), half: expandedHalf)]
			} else {
				// No bands found - place bands near top/bottom quartiles of the interior
				let cTop = yMin + Int(Double(yMax - yMin) * 0.25)
				let cBot = yMin + Int(Double(yMax - yMin) * 0.75)
				var b0 = makeBand(center: cTop, half: half)
				var b1 = makeBand(center: cBot, half: half)
				if b0.upperBound > b1.lowerBound {
					let ov = Int(b0.upperBound - b1.lowerBound)
					let trim = (ov / 2) + 1
					b0 = CGFloat(Int(b0.lowerBound)) ... CGFloat(Int(b0.upperBound) - trim)
					b1 = CGFloat(Int(b1.lowerBound) + trim) ... CGFloat(Int(b1.upperBound))
				}
				bands = [b0, b1]
			}
		}
		
#if DEBUG
		for (i,b) in bands.enumerated() {
			print(String(format: "rowBands: band[%d] = %.0f...%.0f (h=%d)", i, b.lowerBound, b.upperBound, Int(b.upperBound-b.lowerBound)))
		}
#endif
		return bands
	}

	// MARK: - Public entry
	static func detect(on nsImage: NSImage, config: Config = .init()) -> [ControlDraft] {
		guard let cgFull = nsImage.forceCGImage() else {
#if DEBUG
			print("AutoDetect: could not make CGImage from NSImage")
#endif
			return []
		}
		
#if DEBUG
		let debug = true
#else
		let debug = false
#endif
		
		// Build a context we can thread through helpers (fewer params, fewer retains).
		var ctx = DetectContext(cgFull: cgFull, config: config)
		
		// 1) Preprocess (downscale + edges + percentile mask)
		preprocess(&ctx)
		
		// 2) Bands & gates
		computeBands(&ctx)
		
		// 3) Blob-pass (connected components over mask) → draft knobs
		var drafts = blobPass(&ctx, debug: debug)
		
		// 4) Circle-finder pass (primary) gated to interior
		if config.enableCirclePass {
			drafts += circlePass(&ctx, debug: debug)
		}
		
		// 5) Relaxed circle pass if we were too sparse
		drafts += relaxedCirclePassIfSparse(&ctx, current: drafts, debug: debug)
		
		// 6) Promotions (run BEFORE post-filters/NMS so they can influence scoring/merging)
		promoteLitButtons(&drafts, debug: debug)
		promoteConcentricKnobs(&drafts, debug: debug)
		
		// 7) Post-filters to kill bezel/plate artifacts and out-of-gate circles
		drafts = postFilters(&ctx, drafts: drafts)
		
		// 8) NMS + center-dedupe
		drafts = NonMaxSuppression.reduce(drafts, iouThreshold: 0.60)
		drafts = dedupeByCenter(drafts)
		
		// 9) Per-(band,row) per-column merge so vertically aligned rows survive
		drafts = mergePerBandPerColumn(&ctx, drafts: drafts, debug: debug)
		
		// 10) Optional: align columns across bands (gentle X nudge only)
		drafts = reconcileColumnsAcrossBands(&ctx, drafts: drafts, debug: debug)
		drafts = clampDraftsToImage(drafts, w: ctx.srcWf, h: ctx.srcHf)
		
#if DEBUG
		for d in drafts {
			if d.rect.minX < 0 || d.rect.minY < 0 || d.rect.maxX > ctx.srcWf || d.rect.maxY > ctx.srcHf {
				print("WARN: draft outside image: \(d.rect)  (image \(Int(ctx.srcW))×\(Int(ctx.srcH)))")
			}
		}
#endif

		// 11) Numbered default labels (only if still generic/empty)
		assignDefaultLabels(&drafts)

		if debug {
			let byKind = Dictionary(grouping: drafts, by: { $0.kind })
				.mapValues { $0.count }
			print("Kinds: \(byKind)")
		}
#if DEBUG
		let k = drafts.filter { $0.kind == .knob }.count
		print("AutoDetect summary: blobs=\(ctx.blobs.count) knobs=\(k) total=\(drafts.count)")
		if let first = drafts.first(where: { $0.kind == .knob }) {
			print("first knob center px:", first.center)
		}
#endif
		
		return drafts
	}

	// MARK: - Small context carried across stages
	private struct DetectContext {
		// Inputs
		let cgFull: CGImage
		let config: Config
		
		// Derived (image sizes)
		let srcW: Int
		let srcH: Int
		let srcWf: CGFloat
		let srcHf: CGFloat
		
		// Downscaled working image
		let scale: CGFloat
		let cgScaled: CGImage
		let scaledWf: CGFloat
		let scaledHf: CGFloat
		
		// Upscale factors (scaled → full)
		let upX: CGFloat
		let upY: CGFloat
		
		// Edge & mask
		var edgeCG: CGImage!
		var maskCG: CGImage!
		
		// Components & bands
		var blobs: [ConnectedComponents.Blob] = []
		var bandsScaled: [ClosedRange<CGFloat>] = []   // in downscaled (mask) coord
		var bandsPx: [CGRect] = []                     // in TOP-LEFT full pixel space
		var gateTopScaled: CGFloat = 0
		var gateBotScaled: CGFloat = 0
		
		// Luma buffer for refinement
		let rgba: ([UInt8], Int)? // (data array, stride)
		
		init(cgFull: CGImage, config: Config) {
			self.cgFull = cgFull
			self.config = config
			self.srcW = cgFull.width
			self.srcH = cgFull.height
			self.srcWf = CGFloat(srcW)
			self.srcHf = CGFloat(srcH)
			
			// FIX: make maxSide a CGFloat
			let s = downscaleFactor(for: cgFull, maxSide: CGFloat(config.downscaleMax))
			self.scale = s
			self.cgScaled = (s < 1.0) ? cgFull.resized(by: s) : cgFull
			self.scaledWf = CGFloat(cgScaled.width)
			self.scaledHf = CGFloat(cgScaled.height)
			
			self.upX = srcWf / max(1, scaledWf)
			self.upY = srcHf / max(1, scaledHf)
			
			self.rgba = rgbaBuffer(from: cgFull)
		}
	}
	
	// MARK: - Coordinate helpers
	@inline(__always)
	private static func flipY(_ p: CGPoint, srcHf: CGFloat) -> CGPoint { CGPoint(x: p.x, y: srcHf - p.y) }
	
	@inline(__always)
	private static func flipY(_ r: CGRect, srcHf: CGFloat) -> CGRect {
		CGRect(x: r.minX, y: srcHf - r.maxY, width: r.width, height: r.height)
	}
	
	@inline(__always)
	private static func midY(_ r: CGRect) -> CGFloat { (r.minY + r.maxY) * 0.5 }
	
	// MARK: - Stage 1: preprocess
	@inline(__always)
	private static func preprocess(_ ctx: inout DetectContext) {
		let ci = CIImage(cgImage: ctx.cgScaled)
			.applyingFilter("CIColorControls", parameters: [
				kCIInputSaturationKey: 0.0,
				kCIInputBrightnessKey: 0.0,
				kCIInputContrastKey: 1.05
			])
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
			.applyingFilter("CILineOverlay", parameters: [
				"inputNRNoiseLevel": 0.01,
				"inputNRSharpness": 0.6,
				"inputEdgeIntensity": 1.0,
				"inputThreshold": 0.1,
				"inputContrast": 50.0
			])
		
		let cictx = CIContext()
		guard let edge = cictx.createCGImage(ci, from: ci.extent) else { return }
		ctx.edgeCG = edge
		ctx.maskCG = percentileMask(from: edge, keepTopFraction: 0.06)
		ctx.blobs = ConnectedComponents.find(in: ctx.maskCG)
	}
	
	// MARK: - Stage 2: bands/gates
	@inline(__always)
	private static func computeBands(_ ctx: inout DetectContext) {
		// Bands are returned in SCALED, TOP-LEFT IMAGE space (y down).
		let bands = rowBands(from: ctx.maskCG)
		ctx.bandsScaled = bands
		
		// Gate in scaled coords
		let lowers = bands.map { $0.lowerBound }
		let uppers = bands.map { $0.upperBound }
		if let lo = lowers.min(), let hi = uppers.max() {
			ctx.gateTopScaled = lo
			ctx.gateBotScaled = hi
		} else {
			// FIX: keep everything as CGFloat
			ctx.gateTopScaled = CGFloat(0)
			ctx.gateBotScaled = CGFloat(ctx.cgScaled.height - 1)
		}
	}

	// MARK: - Small band utilities (scaled-space)
	@inline(__always)
	private static func bandCenterAndHalfHeights(_ bands: [ClosedRange<CGFloat>]) -> ([CGFloat],[CGFloat]) {
		let centers = bands.map { ($0.lowerBound + $0.upperBound) * 0.5 }
		let halves  = bands.map { ($0.upperBound - $0.lowerBound) * 0.5 }
		return (centers, halves)
	}
	
	@inline(__always)
	private static func inBandsScaled(_ y: CGFloat, bands: [ClosedRange<CGFloat>], gateTop: CGFloat, gateBot: CGFloat, limit: Bool) -> Bool {
		guard limit else { return true }
		if bands.isEmpty { return y >= gateTop && y <= gateBot }
		return bands.contains { $0.contains(y) }
	}
	
	@inline(__always)
	private static func nearAnyBandCenter(
		_ y: CGFloat,
		bands: [ClosedRange<CGFloat>],
		centers: [CGFloat],
		halves: [CGFloat],
		limit: Bool
	) -> Bool {
		guard limit, !bands.isEmpty else { return true }
		// For single-band (single-row) devices, be much more permissive
		let tolFactor: CGFloat = bands.count == 1 ? 1.5 : 0.80
		for (i, c) in centers.enumerated() {
			// FIX: make the literal a CGFloat and use Swift.max to avoid overload ambiguity
			let tol: CGFloat = Swift.max(10.0, tolFactor * halves[i] + 4.0)
			if Swift.abs(y - c) <= tol { return true }
		}
		return false
	}

	@inline(__always)
	private static func bandHeightNear(_ y: CGFloat, bands: [ClosedRange<CGFloat>], gateTop: CGFloat, gateBot: CGFloat) -> CGFloat {
		if let b = bands.first(where: { $0.contains(y) }) { return b.upperBound - b.lowerBound }
		return Swift.max(24.0, gateBot - gateTop) * 0.5
	}

	@inline(__always)
	private static func bandIndexForY(_ yPx: CGFloat, bandsPx: [CGRect]) -> Int? {
		guard !bandsPx.isEmpty else { return nil }
		var best = (-1, CGFloat.greatestFiniteMagnitude)
		for (i,b) in bandsPx.enumerated() {
			let d = abs(yPx - midY(b))
			if d < best.1 { best = (i,d) }
		}
		return best.0 >= 0 ? best.0 : nil
	}
	
	// MARK: - Band index from SCALED Y (robust to TL/BL flips)
	/**
	 Returns the index of the nearest band for a given **scaled-space** Y
	 (where `0` is the top of the downscaled mask image and Y increases downward).
	 
	 We compute scaledY from a draft's full-res TL pixel center as:
	 scaledY = (srcHf - centerPx.y) / upY   (invert the earlier flip)
	 */
	@inline(__always)
	private static func bandIndexForScaledY(_ yScaled: CGFloat, bandsScaled: [ClosedRange<CGFloat>]) -> Int? {
		guard !bandsScaled.isEmpty else { return nil }
		var bestIdx = -1
		var bestDist = CGFloat.greatestFiniteMagnitude
		for (i, b) in bandsScaled.enumerated() {
			let c = (b.lowerBound + b.upperBound) * 0.5
			let d = abs(yScaled - c)
			if d < bestDist { bestDist = d; bestIdx = i }
		}
		return bestIdx >= 0 ? bestIdx : nil
	}

	// MARK: - Small luma refinement (captures ctx.rgba)
	@inline(__always)
	private static func refineCenterAndRadius(_ c: CGPoint, rClamp: CGFloat, rgba: ([UInt8], Int)?, srcW: Int, srcH: Int) -> (CGPoint, CGFloat) {
		guard let (buf, stride) = rgba else { return (c, Swift.max(4.0, rClamp)) }
		var bestC = c
		var bestS: Float = -Float.greatestFiniteMagnitude
		var bestR = Swift.max(4.0, rClamp * 0.90)

		let rInner: CGFloat = Swift.max(4.0, rClamp * 0.60)
		let rOuter: CGFloat = Swift.max(rInner + 1.0, rClamp * 1.10)

		// Expanded search range from -2...2 to -4...4 for better alignment
		let searchRange = max(2, Int(rClamp * 0.15))
		for dy in -searchRange...searchRange {
			for dx in -searchRange...searchRange {
				let cc = CGPoint(x: c.x + CGFloat(dx), y: c.y + CGFloat(dy))
				let inner = ringMeanLuma(buffer: buf, stride: stride, w: srcW, h: srcH, c: cc, r0: 0,       r1: rInner)
				let outer = ringMeanLuma(buffer: buf, stride: stride, w: srcW, h: srcH, c: cc, r0: rOuter, r1: rOuter*1.35)
				let score: Float = outer - inner
				if score > bestS {
					bestS = score
					bestC = cc
					bestR = rInner
				}
			}
		}
		return (bestC, bestR)
	}
	
	// MARK: - Stage 3: blob pass
	private static func blobPass(_ ctx: inout DetectContext, debug: Bool) -> [ControlDraft] {
		var drafts: [ControlDraft] = []
		drafts.reserveCapacity(ctx.blobs.count)
		
		let (centers, halves) = bandCenterAndHalfHeights(ctx.bandsScaled)
		let limit = ctx.config.limitSearchToBands
		
		for b in ctx.blobs {
			let rect = b.bounds // scaled
			let touchesTopOrBottom = rect.minY <= 2 || rect.maxY >= CGFloat(ctx.cgScaled.height - 2)
			let isElongated = (max(rect.width, rect.height) / max(1.0, min(rect.width, rect.height))) >= 2.2
			if touchesTopOrBottom && isElongated { continue }
			
			let w = rect.width, h = rect.height
			if w * h < ctx.config.areaMinPx { continue }
			
			let aspect = max(w, h) / max(1.0, min(w, h))
			let r = 0.5 * min(w, h)
			let area = CGFloat(b.area)
			let roundArea = .pi * r * r
			let roundness = min(1.0, max(0.0, min(roundArea, area) / max(roundArea, area)))
			
			// classify
			var kind: ControlType = .button
			if r * 2 <= ctx.config.ledMaxDiameterPx, roundness > (1 - ctx.config.rectRoundnessTolerance) {
				kind = .light
			} else if (ctx.config.knobMinDiameterPx...ctx.config.knobMaxDiameterPx).contains(r * 2),
					  roundness > (1 - ctx.config.rectRoundnessTolerance),
					  aspect < 1.25 {
				kind = .knob
			} else if aspect >= 1.8 {
				kind = .multiSwitch
			} else {
				kind = .button
			}
			
			var upC = CGPoint(x: rect.midX * ctx.upX, y: rect.midY * ctx.upY)
			var upR = 0.5 * min(rect.width*ctx.upX, rect.height*ctx.upY)

			// luminance gate - be more lenient for buttons/switches since they may be flush with panel
			var keep = true
			if let (buf, stride) = ctx.rgba {
				let inner = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: 0, r1: upR*0.60)
				let outer = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: upR*1.05, r1: upR*1.40)
				let contrastThreshold: Float = (kind == .button || kind == .multiSwitch) ? 0.03 : 0.06
				keep = (outer - inner) >= contrastThreshold
			}
			let yScaled = rect.midY
			guard keep,
				  Self.inBandsScaled(yScaled, bands: ctx.bandsScaled, gateTop: ctx.gateTopScaled, gateBot: ctx.gateBotScaled, limit: limit),
				  Self.nearAnyBandCenter(yScaled, bands: ctx.bandsScaled, centers: centers, halves: halves, limit: limit)
			else { continue }
			
			let bH = bandHeightNear(yScaled, bands: ctx.bandsScaled, gateTop: ctx.gateTopScaled, gateBot: ctx.gateBotScaled)
			let bandMaxRScaled = 0.36 * bH
			let rClamp = min(upR, (0.33 * bH) * max(ctx.upX, ctx.upY))
			(upC, upR) = refineCenterAndRadius(upC, rClamp: rClamp, rgba: ctx.rgba, srcW: ctx.srcW, srcH: ctx.srcH)
			
			let finalRScaled = min(upR / max(ctx.upX, ctx.upY), bandMaxRScaled)
			let finalUpR = finalRScaled * max(ctx.upX, ctx.upY)
			let upRect = CGRect(x: upC.x - finalUpR, y: upC.y - finalUpR, width: finalUpR*2, height: finalUpR*2)
			
			let centerPx = flipY(upC, srcHf: ctx.srcHf)
			let rectPx   = flipY(upRect, srcHf: ctx.srcHf)
			if debug {
				// y in scaled space (invert earlier flip): scaledY = (srcHf - centerPx.y)/upY
				let scaledY = (ctx.srcHf - centerPx.y) / ctx.upY
				let bi = bandIndexForScaledY(scaledY, bandsScaled: ctx.bandsScaled)
				print("  ↳ draft@px(\(Int(centerPx.x)), \(Int(centerPx.y))) band=\(bi ?? -1)")
			}
			
			// Decide confidence from the class we inferred
			let conf: Double
			switch kind {
				case .knob:           conf = 0.62
				case .concentricKnob: conf = 0.64
				case .light:          conf = 0.55
				case .button:         conf = 0.58  // Raised from 0.45 to help buttons survive filtering
				case .multiSwitch:    conf = 0.56  // Raised from 0.40 to help switches survive
				default:              conf = 0.50  // Raised default floor
			}

			// Append draft using computed kind/conf (not hard-coded)
			drafts.append(ControlDraft(kind: kind,
									   rect: rectPx.integral,
									   center: centerPx,
									   radius: finalUpR,
									   label: (kind == .knob || kind == .concentricKnob) ? "Knob" : kind.rawValue.capitalized,
									   confidence: conf))
		}
		
		return drafts
	}

	// MARK: - Stage 4: circle pass (per-band) using Config thresholds
	private static func circlePass(_ ctx: inout DetectContext, debug: Bool) -> [ControlDraft] {
		let scaled = ctx.cgScaled
		let (centers, halves) = bandCenterAndHalfHeights(ctx.bandsScaled)
		let limit = ctx.config.limitSearchToBands
		var out: [ControlDraft] = []
		
		for (bandIdx, band) in ctx.bandsScaled.enumerated() {
			let bandH: CGFloat = Swift.max(1.0, band.upperBound - band.lowerBound)
			let pad: CGFloat   = Swift.max(2.0, bandH * ctx.config.bandPadFrac)
			let cropY: CGFloat = Swift.max(0, floor(band.lowerBound - pad))
			let cropH: CGFloat = Swift.min(CGFloat(scaled.height) - cropY, ceil(bandH + 2.0 * pad))
			let crop  = CGRect(x: 0, y: cropY, width: CGFloat(scaled.width), height: cropH).integral
			guard let cropped = scaled.cropping(to: crop) else { continue }
			let yOff = crop.minY
			
			let ref = Swift.max(CGFloat(80.0), Swift.min(ctx.scaledHf, ctx.scaledWf))
			let rMin: CGFloat = Swift.max(8.0,  ref * 0.08)
			let rMax: CGFloat = Swift.min(120.0, ref * 0.22)
			
			let cfg = CircleFinder.Config(
				maxSide: ctx.config.downscaleMax,
				minRadius: rMin, maxRadius: rMax, radiusStep: 4,
				edgePercentile: 0.53, voteThresholdFraction: 0.32,
				maxResults: 64, nmsRadius: 18,
				enableNaiveAngleFallback: true
			)
			
			let circles = CircleFinder.find(in: cropped, cfg: cfg)
#if DEBUG
			if debug {
				print("CircleFinder band \(bandIdx) returned \(circles.count) circles (crop y=\(Int(crop.minY))..\(Int(crop.maxY)))")
			}
#endif
			
			var bandDrafts: [ControlDraft] = []
			var rejected: [(score: Float, draft: ControlDraft)] = []
			
			for c in circles {
				let cyScaled = CGFloat(c.center.y) + yOff
				guard Self.inBandsScaled(cyScaled, bands: ctx.bandsScaled,
										 gateTop: ctx.gateTopScaled, gateBot: ctx.gateBotScaled,
										 limit: limit),
					  Self.nearAnyBandCenter(cyScaled, bands: ctx.bandsScaled,
											 centers: centers, halves: halves, limit: limit)
				else { continue }
				
				// upscale to full-res TL space
				var upC = CGPoint(x: CGFloat(c.center.x) * ctx.upX, y: cyScaled * ctx.upY)
				let bH  = bandHeightNear(cyScaled, bands: ctx.bandsScaled,
										 gateTop: ctx.gateTopScaled, gateBot: ctx.gateBotScaled)
				let bandMaxRScaled = ctx.config.bandMaxRFrac * bH
				let rScaled = Swift.min(CGFloat(c.radius), bandMaxRScaled)
				let upR = rScaled * Swift.max(ctx.upX, ctx.upY)
				let diameter = upR * 2
				
				// global sanity (lights stay under this; knobs well above)
				guard (ctx.config.knobMinDiameterPx...ctx.config.knobMaxDiameterPx).contains(diameter) else { continue }
				
				// luma refinement + contrast
				(upC, _) = refineCenterAndRadius(upC, rClamp: upR, rgba: ctx.rgba, srcW: ctx.srcW, srcH: ctx.srcH)
				
				var inner: Float = 0, ring: Float = 0, outer: Float = 0, contrast: Float = 0
				if let (buf, stride) = ctx.rgba, upR > 4 {
					inner = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: 0,       r1: upR*0.55)
					ring  = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: upR*0.90, r1: upR*1.15)
					outer = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: upR*1.05, r1: upR*1.40)
					contrast = outer - inner
					if contrast < ctx.config.contrastFloor { continue }
				}
				
				// radial agreement (coverage+alignment)
				let (covRaw, aliRaw) = radialEdgeScore(rgba: ctx.rgba, srcW: ctx.srcW, srcH: ctx.srcH, center: upC, radius: upR)

				// Tighten thresholds progressively based on diameter to reject text/glyphs
				// Smaller circles need much stronger evidence since they're more likely to be glyphs
				var covThresh: Float = ctx.config.covBase
				var aliThresh: Float = ctx.config.aliBase
				if diameter < 24.0 { covThresh += 0.16; aliThresh += 0.08 }  // Tightened from 0.12/0.06
				else if diameter < 36.0 { covThresh += 0.09; aliThresh += 0.05 }  // Tightened from 0.06/0.03
				else if diameter < 48.0 { covThresh += 0.04; aliThresh += 0.02 }  // Tightened from 0.02/0.01
				else if diameter < 60.0 { covThresh += 0.02; aliThresh += 0.01 }  // NEW: medium size boost
				if contrast < 0.05 { covThresh -= 0.03; aliThresh -= 0.02 }
				if diameter > 90 { covThresh -= 0.02 }

				let passRadial = (covRaw >= covThresh && aliRaw >= aliThresh)
				
				// Printed glyph rings (very common on 500-series). Reject early.
				if isLikelyPrintedGlyph(inner: inner, ring: ring, outer: outer, diameter: diameter) {
					continue
				}
				
				// LED vs knob classification.
				// Prefer color evidence for LED (no size cap). Fall back to luma-based LED
				// ONLY when the circle is small (protects real small knobs).
				var draftKind: ControlType = .knob
				var draftLabel = "Knob"
				
				var ledByColor = false
				if let (buf, stride) = ctx.rgba {
					ledByColor = isLikelyLEDColor(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH,
												  center: upC, radius: upR, diameter: diameter, cfg: ctx.config)
				}
				let ledByLuma = isLikelyLED(inner: inner, ring: ring, outer: outer,
											diameter: diameter, cfg: ctx.config)   // this one still size-gated
				
				if ledByColor || ledByLuma {
					draftKind = .light
					draftLabel = "Light"
				}
				
				// Build the draft (convert back to TL px space)
				// Build rect in TL pixel space and clamp to image
				let imageTL = CGRect(x: 0, y: 0, width: ctx.srcWf, height: ctx.srcHf)
				
				// raw TL rect from refined center/radius
				let rectTL = CGRect(x: upC.x - upR, y: upC.y - upR, width: upR * 2, height: upR * 2)
				
				// clamp rect to the image; drop if it ends up degenerate
				let clampedTL = rectTL.intersection(imageTL)
				guard clampedTL.width >= 3, clampedTL.height >= 3 else { continue }
				
				// also clamp center to image so handles/labels can’t jump off canvas
				var clampedCenter = upC
				clampedCenter.x = min(max(clampedCenter.x, 0), ctx.srcWf - 1)
				clampedCenter.y = min(max(clampedCenter.y, 0), ctx.srcHf - 1)
				
				// flip to our overlay coordinate system
				let draftRect  = flipY(clampedTL,     srcHf: ctx.srcHf).integral
				let draftCenter = flipY(clampedCenter, srcHf: ctx.srcHf)
				
				let draft = ControlDraft(
					kind: draftKind,
					rect: draftRect,
					center: draftCenter,
					radius: upR, // keep the original radius for metadata; the rect is what we draw
					label: draftLabel,
					confidence: (draftKind == .light ? 0.70 : 0.72)
				)
				
				// keep, or keep for rescue if not tiny
				if passRadial && !(draftKind == .light && diameter < 8.0) {
					bandDrafts.append(draft)
				} else {
					let tiny = diameter < 24.0
					if !tiny {
						let score = max(0, covRaw) * max(0, aliRaw) * max(0.5, min(1.5, contrast * 12))
						rejected.append((score, draft))
					}
				}
			}
			
			// Per-band size clamp (keeps sizes consistent)
			if !bandDrafts.isEmpty {
				let ds = bandDrafts.compactMap { ($0.radius ?? 0) * 2 }.sorted()
				let p10 = ds[Swift.max(0, Int(floor(0.10 * Double(ds.count-1))))]
				let p90 = ds[Swift.min(ds.count-1, Int(floor(0.90 * Double(ds.count-1))))]
				let spread = (p10 > 0) ? (p90 / p10) : 1.0
				if spread <= ctx.config.sizeClampEnableSpread {
					let med = ds[ds.count/2]
					let lo = med * ctx.config.sizeClampLo
					let hi = med * ctx.config.sizeClampHi
					bandDrafts.removeAll {
						guard let r = $0.radius else { return true }
						let d = r * 2
						return d < lo || d > hi
					}
				}
			}
			
			// Rescue near-misses if this band is sparse
			let wantPerBand = Swift.max(ctx.config.wantPerBandBase,
										Int(ceil(CGFloat(scaled.width) / 1000.0)) * ctx.config.wantPerBandPer1000px)
			if bandDrafts.count < wantPerBand, !rejected.isEmpty {
				let need = Swift.min(wantPerBand - bandDrafts.count, 8)
				let rescued = rejected.sorted { $0.score > $1.score }.prefix(Swift.max(0, need)).map { $0.draft }
				bandDrafts.append(contentsOf: rescued)
			}
			
#if DEBUG
			if debug {
				print("Band \(bandIdx): kept \(bandDrafts.count) after slider-driven filters (want≈\(wantPerBand))")
			}
#endif
			
			out.append(contentsOf: bandDrafts)
		}
		
		return out
	}

	// MARK: - Stage 5: relaxed pass if sparse
	private static func relaxedCirclePassIfSparse(_ ctx: inout DetectContext, current: [ControlDraft], debug: Bool) -> [ControlDraft] {
		let neededMin = 6
		let currentKnobCount = current.filter({ $0.kind == .knob }).count

		// Always run if we found absolutely nothing, otherwise respect band limits
		let shouldRun = currentKnobCount < neededMin && (ctx.config.limitSearchToBands || current.isEmpty)

		guard shouldRun else { return [] }

#if DEBUG
		print("relaxedCirclePassIfSparse: only \(currentKnobCount) knobs found, trying full-image scan...")
#endif

		let scaled = ctx.cgScaled
		let ref = Swift.max(CGFloat(80.0), Swift.min(ctx.scaledHf, ctx.scaledWf))
		let rMin: CGFloat = Swift.max(8.0,  ref * 0.08)
		let rMax: CGFloat = Swift.min(120.0, ref * 0.22)

		// More aggressive parameters for sparse detection
		let cfg = CircleFinder.Config(
			maxSide: ctx.config.downscaleMax,
			minRadius: rMin, maxRadius: rMax, radiusStep: 2,  // Reduced from 3 for finer search
			edgePercentile: 0.40, voteThresholdFraction: 0.22,  // Very relaxed for difficult images
			maxResults: 128, nmsRadius: 12,  // Increased max results, reduced NMS
			enableNaiveAngleFallback: true
		)
		let circles = CircleFinder.find(in: scaled, cfg: cfg)

#if DEBUG
		print("relaxedCirclePassIfSparse: CircleFinder returned \(circles.count) circles with very relaxed params")
#endif
		
		var out: [ControlDraft] = []
		for c in circles {
			guard c.center.y >= ctx.gateTopScaled, c.center.y <= ctx.gateBotScaled else { continue }
			var upC = CGPoint(x: CGFloat(c.center.x) * ctx.upX, y: CGFloat(c.center.y) * ctx.upY)
			
			let bH = Swift.max(24.0, ctx.gateBotScaled - ctx.gateTopScaled) * 0.5
			let bandMaxRScaled = 0.36 * bH
			let rScaled = min(CGFloat(c.radius), bandMaxRScaled)
			let upR = rScaled * max(ctx.upX, ctx.upY)
			
			(upC, _) = refineCenterAndRadius(upC, rClamp: upR, rgba: ctx.rgba, srcW: ctx.srcW, srcH: ctx.srcH)
			
			if let (buf, stride) = ctx.rgba, upR > 6 {
				let inner = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: 0,       r1: upR*0.60)
				let outer = ringMeanLuma(buffer: buf, stride: stride, w: ctx.srcW, h: ctx.srcH, c: upC, r0: upR*1.05, r1: upR*1.40)
				if (outer - inner) < Float(0.045) { continue }
			}

			// Clamp to image bounds in TL pixel space
			let imageTL = CGRect(x: 0, y: 0, width: ctx.srcWf, height: ctx.srcHf)
			
			// Raw TL rect from refined center/radius
			let rawTL = CGRect(x: upC.x - upR, y: upC.y - upR, width: upR * 2, height: upR * 2)
			
			// Intersect; drop if degenerate after clamping
			let clampedTL = rawTL.intersection(imageTL)
			guard clampedTL.width >= 3, clampedTL.height >= 3 else { continue }
			
			// Clamp center too (keeps handles/labels on-canvas)
			var cTL = upC
			cTL.x = min(max(cTL.x, 0), ctx.srcWf - 1)
			cTL.y = min(max(cTL.y, 0), ctx.srcHf - 1)
			
			// Convert to overlay space
			let pxCenter = flipY(cTL, srcHf: ctx.srcHf)
			let rectPx   = flipY(clampedTL, srcHf: ctx.srcHf).integral
			
			out.append(ControlDraft(
				kind: .knob,
				rect: rectPx,
				center: pxCenter,
				radius: upR,
				label: "Knob",
				confidence: 0.55
			))

		}
		return out
	}
	
	// MARK: - Stage 6: promote "button + inner light" → a single Lit Button draft.
	@inline(__always)
	private static func promoteLitButtons(_ drafts: inout [ControlDraft], debug: Bool = false) {
		guard !drafts.isEmpty else { return }
		var removeIDs = Set<UUID>()
		
		for i in drafts.indices {
			guard drafts[i].kind == .button else { continue }
			let r = drafts[i].rect
			let inner = r.insetBy(dx: r.width * 0.18, dy: r.height * 0.18)
			if let j = drafts.firstIndex(where: { $0.kind == .light && inner.contains($0.center) }) {
				removeIDs.insert(drafts[j].id)
				drafts[i].label = "Lit Button"
				drafts[i].confidence = max(drafts[i].confidence, 0.70)
				if debug {
					print("Promote: button+\(drafts[j].kind) ⇒ Lit Button @ \(drafts[i].center)")
				}
			}
		}
		if !removeIDs.isEmpty {
			drafts.removeAll { removeIDs.contains($0.id) }
		}
	}
	
	// Promote two concentric knobs → a single Concentric Knob draft.
	@inline(__always)
	private static func promoteConcentricKnobs(_ drafts: inout [ControlDraft], debug: Bool = false) {
		guard !drafts.isEmpty else { return }
		
		// any circular candidate with a radius qualifies as a potential ring
		let circleIdxs = drafts.indices.filter { drafts[$0].radius != nil }
		
		guard circleIdxs.count >= 2 else { return }
		var remove = Set<Int>()
		
		for i in circleIdxs {
			if remove.contains(i) { continue }
			guard let Ri = drafts[i].radius else { continue }
			let Ci = drafts[i].center
			let centerTol: CGFloat = Swift.max(6.0, Ri * 0.35)
			
			for j in circleIdxs where j != i && !remove.contains(j) {
				guard let Rj = drafts[j].radius else { continue }
				let Cj = drafts[j].center
				if hypot(Cj.x - Ci.x, Cj.y - Ci.y) <= centerTol {
					// order them
					let (outerIdx, innerIdx) = (Ri >= Rj) ? (i, j) : (j, i)
					guard let Rout = drafts[outerIdx].radius, let Rin = drafts[innerIdx].radius else { continue }
					let ratio = Rin / Swift.max(1.0, Rout)
					
					// concentric pair: inner between 35–70% of the outer
					if ratio >= 0.35, ratio <= 0.70 {
						drafts[outerIdx].kind = .concentricKnob
						drafts[outerIdx].label = "Concentric"
						drafts[outerIdx].confidence = Swift.max(drafts[outerIdx].confidence, 0.80)
						remove.insert(innerIdx)
						if debug {
							print("Promote: concentric pair ⇒ Concentric @ \(drafts[outerIdx].center) (ratio=\(ratio))")
						}
						break
					}
				}
			}
		}
		
		if !remove.isEmpty {
			drafts = drafts.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
		}
	}
	
	// MARK: - Stage 7: post filters (structural / dynamic, column-aware)
	@inline(__always)
	private static func postFilters(_ ctx: inout DetectContext, drafts: [ControlDraft]) -> [ControlDraft] {
		guard !drafts.isEmpty else { return drafts }
		var keep = drafts
		
		// ---- 7a) Dynamic minimum knob diameter (learn from image) ----
		let knobDs = keep.filter { $0.kind == .knob && $0.radius != nil }
			.map { ($0.radius ?? 0) * 2 }
			.sorted()
		var dynKnobFloor: CGFloat = ctx.config.knobMinDiameterPx
		if knobDs.count >= 5 {
			// use the top-half median as a robust estimate of "real knob" size
			let halfStart = knobDs.count / 2
			let topHalf = Array(knobDs[halfStart..<knobDs.count])
			let medTopHalf = topHalf[topHalf.count / 2]
			// Relaxed from 0.55 to 0.45 to catch smaller knobs
			dynKnobFloor = max(ctx.config.knobMinDiameterPx, medTopHalf * 0.45)
		}

		// Remove tiny "knob" lookalikes according to learned floor
		// Only apply this if we have high confidence in the floor estimate
		if knobDs.count >= 8 {
			keep.removeAll {
				if $0.kind == .knob, let r = $0.radius {
					return (r * 2) < dynKnobFloor
				}
				return false
			}
		}
		guard !keep.isEmpty else { return keep }
		
		// ---- 7b) Column clustering on X, then prune noisy columns ----
		// Sort by X so we can cluster adjacent drafts into columns.
		let sortedIdx = keep.indices.sorted { keep[$0].center.x < keep[$1].center.x }
		let xs = sortedIdx.map { keep[$0].center.x }
		
		// median gap as a column spacing prior
		var gaps: [CGFloat] = []
		if xs.count >= 2 {
			gaps.reserveCapacity(xs.count - 1)
			for i in 1..<xs.count { gaps.append(xs[i] - xs[i-1]) }
		}
		let medGap: CGFloat = gaps.sorted().dropFirst(gaps.count/3).first ?? max(18.0, ctx.srcWf * 0.02)
		let xTol: CGFloat = max(8.0, medGap * 0.33)
		
		// build columns as groups of indices whose X is within xTol
		var cols: [[Int]] = []
		var cur: [Int] = []
		for i in sortedIdx {
			if cur.isEmpty {
				cur = [i]
			} else if abs(keep[i].center.x - keep[cur.last!].center.x) <= xTol {
				cur.append(i)
			} else {
				cols.append(cur); cur = [i]
			}
		}
		if !cur.isEmpty { cols.append(cur) }
		
		// classify/prune columns
		var bad: Set<Int> = []
		for col in cols {
			var knobDiameters: [CGFloat] = []
			var lightCount = 0
			var concentricCount = 0
			var buttonCount = 0
			var switchCount = 0

			for j in col {
				let d = keep[j]
				switch d.kind {
					case .light:
						lightCount += 1
					case .concentricKnob:
						concentricCount += 1
						if let r = d.radius { knobDiameters.append(r*2) }
					case .knob:
						if let r = d.radius { knobDiameters.append(r*2) }
					case .button, .litButton:
						buttonCount += 1
					case .multiSwitch:
						switchCount += 1
					default:
						break
				}
			}

			knobDiameters.sort()
			let medColKnob: CGFloat = knobDiameters.isEmpty ? 0 : knobDiameters[knobDiameters.count/2]

			// Relaxed column validation criteria
			// A column is a valid LED column if it has several lights.
			let isLEDColumn = lightCount >= 2  // Reduced from 3 to 2

			// A column is a valid knob column if its median knob diameter is "big enough".
			// Relaxed threshold from dynKnobFloor to 0.85 * dynKnobFloor
			let isKnobColumn = medColKnob >= (dynKnobFloor * 0.85)

			// Keep column if it has any knobs at all (not just based on median)
			let hasAnyKnobs = !knobDiameters.isEmpty

			// NEW: Recognize button and switch columns as valid columns
			let isButtonColumn = buttonCount >= 1
			let isSwitchColumn = switchCount >= 1

			// Always keep if we saw a concentric knob (robust signal).
			let keepColumn = isLEDColumn || isKnobColumn || (concentricCount > 0) || hasAnyKnobs || isButtonColumn || isSwitchColumn

			if !keepColumn {
				// Drop only the non-lights from this bad column (keep any lights just in case).
				for j in col {
					if keep[j].kind != .light {
						bad.insert(j)
					}
				}
			}
		}
		
		if !bad.isEmpty {
			keep = keep.enumerated().filter { !bad.contains($0.offset) }.map { $0.element }
		}
		
		return keep
	}

	private static func baseName(for kind: ControlType) -> String {
		switch kind {
			case .knob, .steppedKnob, .concentricKnob: return "Knob"
			case .light:                                return "Lamp"
			case .button, .litButton:                   return "Button"
			case .multiSwitch:                          return "Switch"
		}
	}
	
	// --- LED & glyph heuristics ---
	
	@inline(__always)
	private static func isLikelyLED(inner: Float, ring: Float, outer: Float,
									diameter: CGFloat, cfg: Config) -> Bool {
		guard diameter <= cfg.ledMaxDiameterPx else { return false }
		// Core clearly brighter than surroundings ⇒ lit LED
		let corePop: Float = inner - min(ring, outer)
		return corePop >= 0.06
	}
	
	@inline(__always)
	private static func meanRGB(buffer: [UInt8], stride: Int, w: Int, h: Int,
								center c: CGPoint, radius r: CGFloat) -> (Float, Float, Float) {
		let K = 24
		var rt: Float = 0, gt: Float = 0, bt: Float = 0, n: Float = 0
		let rr = max(1.0, r)
		for k in 0..<K {
			let a = (Double(k) / Double(K)) * 2.0 * Double.pi
			let x = Int(round(Double(c.x) + Double(rr*0.45) * cos(a)))
			let y = Int(round(Double(c.y) + Double(rr*0.45) * sin(a)))
			if x <= 0 || y <= 0 || x >= w || y >= h { continue }
			let i = y*stride + x*4
			rt += Float(buffer[i    ]) / 255.0
			gt += Float(buffer[i + 1]) / 255.0
			bt += Float(buffer[i + 2]) / 255.0
			n += 1
		}
		if n == 0 { return (0,0,0) }
		return (rt/n, gt/n, bt/n)
	}
	
	// LED color: bright + somewhat saturated (green / red / yellow LEDs).
	// IMPORTANT: no diameter cap here — works for any size.
	@inline(__always)
	private static func isLikelyLEDColor(buffer: [UInt8], stride: Int, w: Int, h: Int,
										 center c: CGPoint, radius r: CGFloat,
										 diameter: CGFloat, cfg: Config) -> Bool {
		let (rMean, gMean, bMean) = meanRGB(buffer: buffer, stride: stride, w: w, h: h, center: c, radius: r)
		let maxC = max(rMean, max(gMean, bMean))
		let minC = min(rMean, min(gMean, bMean))
		let dom  = maxC - minC
		// bright + chromatic
		return (maxC >= 0.38 && dom >= 0.10)
	}

	// Printed "0"/tick rings: bright ring with inner≈outer background — not a knob or LED.
	@inline(__always)
	private static func isLikelyPrintedGlyph(inner: Float, ring: Float, outer: Float,
											 diameter: CGFloat) -> Bool {
		// Printed "0" / ticks / dial markings are small bright rings drawn on the panel.
		// Heuristics:
		//  • small diameter
		//  • ring brighter than BOTH inner & outer
		//  • inner and outer roughly the same (panel background)
		if diameter > 68 { return false }                   // glyphs are small (relaxed slightly from 64)
		let ringGain: Float = ring - max(inner, outer)      // how much the ring pops
		let innerOuterClose = abs(inner - outer) <= 0.030   // background is same (relaxed from 0.025)
		// Tightened threshold from 0.09 to 0.07 to catch more printed text
		return ringGain >= 0.07 && innerOuterClose
	}

	// MARK: - Stage 8: de-dupe by center
	private static func dedupeByCenter(_ a: [ControlDraft]) -> [ControlDraft] {
		var keep: [ControlDraft] = []
		for d in a.sorted(by: { $0.confidence > $1.confidence }) {
			if !keep.contains(where: {
				guard $0.kind == d.kind else { return false }
				let r0 = $0.radius ?? 0, r1 = d.radius ?? 0
				let tol = Swift.max(6.0, Swift.min(r0, r1) * 0.35)
				return hypot($0.center.x - d.center.x, $0.center.y - d.center.y) < tol
			}) { keep.append(d) }
		}
		return keep
	}

	// MARK: - Stage 9: per-(band,row) per-column merge
	private static func mergePerBandPerColumn(_ ctx: inout DetectContext, drafts: [ControlDraft], debug: Bool) -> [ControlDraft] {
		// Band index from scaled-space Y (robust)
		func bandIndexForDraft(_ d: ControlDraft) -> Int {
			let yScaled = (ctx.srcHf - d.center.y) / ctx.upY
			return bandIndexForScaledY(yScaled, bandsScaled: ctx.bandsScaled) ?? -1
		}
		
		let knobs = drafts.filter { $0.kind == .knob }
		var merged: [ControlDraft] = drafts.filter { $0.kind != .knob } // keep non-knobs
		
		let grouped = Dictionary(grouping: knobs, by: { bandIndexForDraft($0) })
		
		for (bandIdx, items) in grouped {
			// Per-band median diameter
			let diameters: [CGFloat] = items.compactMap { ($0.radius ?? 0) * 2 }
			let medianDia: CGFloat = {
				guard !diameters.isEmpty else { return 28 }
				let s = diameters.sorted()
				return s[s.count/2]
			}()
			
			// Compute sorted X and gaps to measure spacing between columns
			let xs = items.map { $0.center.x }.sorted()
			var gaps: [CGFloat] = []
			gaps.reserveCapacity(max(0, xs.count - 1))
			for i in 1..<xs.count { gaps.append(xs[i] - xs[i-1]) }
			let medGap: CGFloat = {
				guard !gaps.isEmpty else { return max(36, medianDia * 1.2) }
				let s = gaps.sorted()
				return s[s.count/2]
			}()
			let q25Gap: CGFloat = {
				guard !gaps.isEmpty else { return medGap }
				let s = gaps.sorted()
				let idx = max(0, min(s.count-1, Int(floor(0.25 * Double(s.count-1)))))
				return s[idx]
			}()
			
			// Tolerance tuned to dedupe *only* true duplicates in the same column:
			// - tighten by diameter (≈ 0.45×D)
			// - also cap by a fraction of the lower spacing quantile (0.60×Q25)
			let tolFromDia = max(8, medianDia * 0.45)
			let tolFromGap = max(8, min(q25Gap * 0.60, medGap * 0.50))
			let xTol: CGFloat = min(tolFromDia, tolFromGap)
			
			let sorted = items.sorted { $0.center.x < $1.center.x }
			var cluster: [ControlDraft] = []
			var lastX: CGFloat = -.greatestFiniteMagnitude
			
			func flush() {
				guard !cluster.isEmpty else { return }
				// Keep the best representative of the column
				let best = cluster.max {
					if $0.confidence == $1.confidence { return ($0.radius ?? 0) < ($1.radius ?? 0) }
					return $0.confidence < $1.confidence
				}!
				merged.append(best)
				cluster.removeAll(keepingCapacity: true)
			}
			
			for d in sorted {
				if abs(d.center.x - lastX) > xTol {
					flush()
					cluster = [d]
					lastX = d.center.x
				} else {
					cluster.append(d)
					// slight inertia to avoid oscillation
					lastX = (lastX * 0.7) + (d.center.x * 0.3)
				}
			}
			flush()
			
#if DEBUG
			if debug {
				let kept = merged.filter { $0.kind == .knob && bandIndexForDraft($0) == bandIdx }.count
				print("Band \(bandIdx): kept \(kept) of \(items.count) column clusters (xTol≈\(Int(xTol)))")
			}
#endif
		}
		
		return merged
	}
	
	@inline(__always)
	private static func clampDraftsToImage(
		_ drafts: [ControlDraft],
		w: CGFloat,
		h: CGFloat
	) -> [ControlDraft] {
		var out: [ControlDraft] = []
		out.reserveCapacity(drafts.count)
		
		let w1 = max(0, w - 1)
		let h1 = max(0, h - 1)
		
		for var d in drafts {
			var r = d.rect.standardized
			
			// Clamp origin first
			r.origin.x = max(0, r.origin.x)
			r.origin.y = max(0, r.origin.y)
			
			// Clamp size so the rect stays inside the image
			r.size.width  = max(0, min(r.size.width,  w - r.origin.x))
			r.size.height = max(0, min(r.size.height, h - r.origin.y))
			
			// Drop degenerate
			if r.width < 3 || r.height < 3 { continue }
			
			// Clamp center too (keeps handles/labels sane)
			d.center.x = min(max(d.center.x, 0), w1)
			d.center.y = min(max(d.center.y, 0), h1)
			d.rect = r.integral
			
			out.append(d)
		}
		return out
	}

    private static func defaultLabel(for kind: ControlType) -> String {
        switch kind {
        case .knob: return "Knob"
        case .steppedKnob: return "Stepped"
        case .multiSwitch: return "Switch"
			case .button, .litButton: return "Button"
        case .light: return "Lamp"
        case .concentricKnob: return "Concentric"
        }
    }
	
	// MARK: - Stage 10: Radial edge agreement on a circle rim (reject printed "0"s etc.)
	@inline(__always)
	private static func radialEdgeScore(
		rgba: ([UInt8], Int)?,
		srcW: Int, srcH: Int,
		center c: CGPoint,
		radius r: CGFloat
	) -> (coverage: Float, alignment: Float) {
		guard let (buf, stride) = rgba, r >= 4 else { return (0, 0) }
		
		@inline(__always)
		func lumaAt(_ x: Int, _ y: Int) -> Float {
			if x <= 0 || y <= 0 || x >= srcW-1 || y >= srcH-1 { return 0 }
			let i = y*stride + x*4
			return lum(buf[i], buf[i+1], buf[i+2])
		}
		
		@inline(__always)
		func gradAt(_ x: Int, _ y: Int) -> (Float, Float) {
			let gx = lumaAt(x+1, y) - lumaAt(x-1, y)
			let gy = lumaAt(x, y+1) - lumaAt(x, y-1)
			return (gx, gy)
		}
		
		let K = 64
		var covered = 0
		var alignSum: Float = 0
		let magThresh: Float = 0.015
		
		for k in 0..<K {
			let a = (Double(k) / Double(K)) * 2.0 * Double.pi
			let ux = Float(cos(a)), uy = Float(sin(a))
			let x  = Int(round(Double(c.x) + Double(r) * cos(a)))
			let y  = Int(round(Double(c.y) + Double(r) * sin(a)))
			if x <= 0 || y <= 0 || x >= srcW-1 || y >= srcH-1 { continue }
			
			let (gx, gy) = gradAt(x, y)
			let mag = sqrtf(gx*gx + gy*gy)
			if mag < (1e-6 as Float) { continue }      // keep literal as Float
			
			let nx = gx / mag, ny = gy / mag
			let agree = fabsf(nx*ux + ny*uy)
			
			if mag >= magThresh && agree >= (0.55 as Float) {
				covered += 1
				alignSum += agree
			}
		}
		
		let cov = Float(covered) / Float(K)
		let ali: Float = covered > 0 ? alignSum / Float(covered) : 0
		return (cov, ali)
	}

	static func edgesPreview(for imageSize: CGSize, in config: Config) -> NSImage? {
		// This function relies on the last-detected image; for simplicity generate a blank grid if not available.
		// A production version would cache the last CI edge image; here we return nil to keep it safe.
		return nil
	}

	/// Build a binary mask keeping the brightest `keepTopFraction` pixels of a CGImage.
	private static func percentileMask(from cg: CGImage, keepTopFraction p: Double) -> CGImage {
		let w = cg.width, h = cg.height
		// Read RGB → luma
		let ctx = CGContext(data: nil, width: w, height: h,
							bitsPerComponent: 8, bytesPerRow: w*4,
							space: CGColorSpaceCreateDeviceRGB(),
							bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
		let raw = ctx.data!.assumingMemoryBound(to: UInt8.self)
		
		var mags = [UInt8](repeating: 0, count: w*h)
		for i in 0..<(w*h) {
			let r = raw[i*4+0], g = raw[i*4+1], b = raw[i*4+2]
			let m = Float(0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b))
			mags[i] = UInt8(max(0, min(255, m)))
		}
		
		// Find cutoff at the (1-p) percentile (we keep the brightest p fraction)
		var hist = [Int](repeating: 0, count: 256)
		for v in mags { hist[Int(v)] &+= 1 }
		let target = Int(Double(w*h) * (1.0 - p))
		var sum = 0, cutoff = 255
		for t in 0..<256 {
			sum += hist[t]
			if sum >= target { cutoff = t; break }
		}
		
		// Threshold
		var bin = [UInt8](repeating: 0, count: w*h)
		for i in 0..<(w*h) { bin[i] = mags[i] >= cutoff ? 255 : 0 }
		
		let provider = CGDataProvider(data: Data(bin) as CFData)!
		return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
					   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
					   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
	}
	
	// MARK: - Cross-band column reconcile (shared X grid snap)
	private static func reconcileColumnsAcrossBands(
		_ ctx: inout DetectContext,
		drafts: [ControlDraft],
		debug: Bool
	) -> [ControlDraft] {
		
		// Band from scaled-space Y
		func bandIndex(for d: ControlDraft) -> Int {
			let yScaled = (ctx.srcHf - d.center.y) / ctx.upY
			return bandIndexForScaledY(yScaled, bandsScaled: ctx.bandsScaled) ?? -1
		}
		
		let knobs = drafts.filter { $0.kind == .knob }
		var others = drafts.filter { $0.kind != .knob }
		
		let byBand = Dictionary(grouping: knobs, by: bandIndex(for:))
		guard let A = byBand[0], let B = byBand[1], !A.isEmpty, !B.isEmpty else { return drafts }
		
		// Build a unified grid of column seeds from the union of both bands’ Xs
		let xsAll = (A.map { $0.center.x } + B.map { $0.center.x }).sorted()
		
		// Estimate typical spacing from pairwise gaps
		var gaps: [CGFloat] = []
		gaps.reserveCapacity(max(0, xsAll.count - 1))
		for i in 1..<xsAll.count { gaps.append(xsAll[i] - xsAll[i-1]) }
		let medGap: CGFloat = {
			guard !gaps.isEmpty else { return 48 }
			let s = gaps.sorted(); return s[s.count/2]
		}()
		// Merge close seeds into one grid position
		let mergeTol: CGFloat = Swift.max(10.0, medGap * 0.45)

		var grid: [CGFloat] = []
		for x in xsAll {
			if let last = grid.last, abs(x - last) <= mergeTol {
				grid[grid.count - 1] = (last + x) * 0.5
			} else {
				grid.append(x)
			}
		}
		
		// Snap each band’s knobs to nearest grid seed with a capped nudge
		let maxShift: CGFloat = ctx.config.maxGridSnapShiftPx   // was a hard-coded 18
		let snapTol: CGFloat = max(maxShift * 1.5, mergeTol)
		
		func snapped(_ items: [ControlDraft]) -> [ControlDraft] {
			return items.map { d in
				// find nearest grid seed
				var best = grid[0]; var bestDx = abs(d.center.x - best)
				for gx in grid {
					let dx = abs(d.center.x - gx)
					if dx < bestDx { bestDx = dx; best = gx }
				}
				// only nudge if we’re reasonably close to some grid seed
				let target = (bestDx <= snapTol) ? best : d.center.x
				let dx = max(-maxShift, min(maxShift, target - d.center.x))
				if abs(dx) < 0.5 { return d }
				var dd = d
				dd.center.x += dx
				if let r = d.radius {
					dd.rect = CGRect(x: dd.center.x - r, y: dd.center.y - r, width: r*2, height: r*2).integral
				} else {
					dd.rect.origin.x += dx
				}
				return dd
			}
		}
		
		let A2 = snapped(A)
		let B2 = snapped(B)
		
#if DEBUG
		if debug {
			print("Reconcile(grid): seeds=\(grid.count), medGap≈\(Int(medGap)), maxShift≤\(Int(maxShift))")
		}
#endif
		
		others.append(contentsOf: A2 + B2)
		return others
	}
	
	// MARK: - Stage 11: Numbered default labels
	private static func assignDefaultLabels(_ drafts: inout [ControlDraft]) {
		// Treat these as “generic” — if a draft still has one of these, we replace it with a numbered name.
		let generic: Set<String> = ["", "knob", "lamp", "light", "button", "switch"]
		
		let tolY: CGFloat = 16   // row tolerance in pixels
		for kind in ControlType.allCases {
			// indices of drafts of this kind
			let idxs = drafts.indices.filter { drafts[$0].kind == kind }
			// stable sort: by row (y), then by column (x)
			let sorted = idxs.sorted {
				let a = drafts[$0], b = drafts[$1]
				if abs(a.center.y - b.center.y) > tolY { return a.center.y < b.center.y }
				return a.center.x < b.center.x
			}
			
			var n = 1
			let base = baseName(for: kind)
			for i in sorted {
				let raw = drafts[i].label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
				if generic.contains(raw) {
					drafts[i].label = "\(base) \(n)"
				}
				n += 1
			}
		}
	}
}

// MARK: - Helpers (CG/CI)

@inline(__always)
private func topLeftToCoreImage(_ r: CGRect, imageHeight h: CGFloat) -> CGRect {
	// convert a top-left pixel-space rect to Core Image (bottom-left) rect
	CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

private extension CIImage {
    func applyingSobel() -> CIImage {
        // Quick Sobel (horizontal + vertical)
        let kx = CIVector(values: [-1,0,1,-2,0,2,-1,0,1], count: 9)
        let ky = CIVector(values: [-1,-2,-1,0,0,0,1,2,1], count: 9)
        let gx = applyingFilter("CIConvolution3X3", parameters: ["inputWeights": kx, "inputBias": 0])
        let gy = applyingFilter("CIConvolution3X3", parameters: ["inputWeights": ky, "inputBias": 0])
        return gx.applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": gy])
            .applyingFilter("CIColorAbsoluteDifference", parameters: ["inputImage2": CIImage(color: .black).cropped(to: extent)])
    }

    func makeCGImage(context: CIContext = CIContext()) -> CGImage? {
        context.createCGImage(self, from: extent)
    }
}

private extension CGImage {
    func resized(by scale: CGFloat) -> CGImage {
        let w = Int(CGFloat(width) * scale)
        let h = Int(CGFloat(height) * scale)
        let cs = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: bitsPerComponent,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()!
    }

    func thresholdMask(threshold: Float) -> CGImage {
        // CPU threshold into single-channel mask (8-bit)
        let w = width, h = height
        var pixels = [UInt8](repeating: 0, count: w*h)
        let data = CFDataCreateMutable(nil, w*h*4)!
        let ctx = CGContext(data: CFDataGetMutableBytePtr(data),
                            width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w*4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let raw = CFDataGetMutableBytePtr(data)!

        for i in 0..<w*h {
            let r = raw[i*4 + 0]
            let g = raw[i*4 + 1]
            let b = raw[i*4 + 2]
            // Approx luma of edge mag
            let m = (0.2126*Double(r) + 0.7152*Double(g) + 0.0722*Double(b)) / 255.0
            pixels[i] = (m >= Double(threshold)) ? 255 : 0
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

private extension NSImage {
	func bestCGImage() -> CGImage? {
		if let cg = self.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
		guard let rep = tiffRepresentation,
			  let img = NSBitmapImageRep(data: rep) else { return nil }
		return img.cgImage
	}
}

private extension NSImage {
	/// Very robust conversion to CGImage for any NSImage (PDF-backed, TIFF-only, etc.).
	func forceCGImage() -> CGImage? {
		// Fast path
		if let cg = self.cgImage(forProposedRect: nil, context: nil, hints: nil) {
			return cg
		}
		
		// Try via TIFF/bitmap rep
		if let tiff = self.tiffRepresentation,
		   let rep  = NSBitmapImageRep(data: tiff),
		   let cg   = rep.cgImage {
			return cg
		}
		
		// Final fallback: draw into a CGContext
		let pixelSize: CGSize = {
			if let rep = self.representations.first {
				return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
			} else {
				return self.size // may be points; better than nothing
			}
		}()
		let w = max(Int(pixelSize.width.rounded()), 1)
		let h = max(Int(pixelSize.height.rounded()), 1)
		
		let cs = CGColorSpaceCreateDeviceRGB()
		guard let ctx = CGContext(data: nil,
								  width: w,
								  height: h,
								  bitsPerComponent: 8,
								  bytesPerRow: 0,
								  space: cs,
								  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			return nil
		}
		
		// AppKit coordinates are flipped; set up so image draws upright
		ctx.translateBy(x: 0, y: CGFloat(h))
		ctx.scaleBy(x: 1, y: -1)
		
		let rect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
		
		NSGraphicsContext.saveGraphicsState()
		let gc = NSGraphicsContext(cgContext: ctx, flipped: false) // non-optional
		NSGraphicsContext.current = gc
		self.draw(in: rect)
		NSGraphicsContext.restoreGraphicsState()
		
		return ctx.makeImage()
	}
}

private enum ConnectedComponents {
    struct Blob { let bounds: CGRect; let area: Int }

    static func find(in mask: CGImage) -> [Blob] {
        // Simple 4-neighborhood flood fill on byte mask == 255
        let w = mask.width, h = mask.height
        guard let data = mask.dataProvider?.data as Data? else { return [] }
        let grid = Array(data)
        var visited = [Bool](repeating: false, count: w*h)
        var blobs: [Blob] = []

        func idx(_ x: Int,_ y: Int) -> Int { y*w + x }
        for y in 0..<h {
            for x in 0..<w {
                let i = idx(x,y)
                if visited[i] || grid[i] == 0 { continue }
                // BFS
                var q = [i]; visited[i] = true
                var minX = x, maxX = x, minY = y, maxY = y, area = 0
                while let cur = q.popLast() {
                    area += 1
                    let cx = cur % w, cy = cur / w
                    minX = min(minX, cx); maxX = max(maxX, cx)
                    minY = min(minY, cy); maxY = max(maxY, cy)
                    for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                        let nx = cx + dx, ny = cy + dy
                        if nx<0 || ny<0 || nx>=w || ny>=h { continue }
                        let ni = idx(nx,ny)
                        if !visited[ni], grid[ni] != 0 {
                            visited[ni] = true
                            q.append(ni)
                        }
                    }
                }
                let r = CGRect(x: minX, y: minY, width: max(1, maxX-minX+1), height: max(1, maxY-minY+1))
                blobs.append(.init(bounds: r, area: area))
            }
        }
        return blobs
    }
}

private enum NonMaxSuppression {
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let iArea = inter.width * inter.height
        let uArea = a.width*a.height + b.width*b.height - iArea
        return (uArea <= 0) ? 0 : (iArea / uArea)
    }

    static func reduce(_ drafts: [ControlDraft], iouThreshold: CGFloat) -> [ControlDraft] {
        let sorted = drafts.sorted { $0.confidence > $1.confidence }
        var kept: [ControlDraft] = []
        for d in sorted {
            if !kept.contains(where: { iou($0.rect, d.rect) > iouThreshold }) { kept.append(d) }
        }
        return kept
    }
}

private func downscaleFactor(for cg: CGImage, maxSide: CGFloat) -> CGFloat {
    let side = max(cg.width, cg.height)
    return side > Int(maxSide) ? maxSide / CGFloat(side) : 1.0
}

extension ControlAutoDetect.Config {
	func toggling(limitSearchToBands: Bool) -> Self {
		var c = self
		c.limitSearchToBands = limitSearchToBands
		return c
	}
}
