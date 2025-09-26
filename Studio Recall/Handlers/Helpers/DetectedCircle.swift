//  DetectedCircle.swift
//  Studio Recall

import Foundation
import CoreImage
import CoreGraphics
import AppKit

struct DetectedCircle {
	var center: CGPoint
	var radius: CGFloat
	var score: Float
}

enum CircleFinder {
	struct Config {
		var maxSide: CGFloat = 900          // downscale target
		var minRadius: CGFloat = 8
		var maxRadius: CGFloat = 64
		var radiusStep: CGFloat = 2
		var edgePercentile: Double = 0.65   // auto threshold on edge magnitude
		var voteThresholdFraction: Float = 0.45 // fraction of (radius * π) to accept
		var maxResults = 96
		var nmsRadius: CGFloat = 12         // non-max suppression radius (px)
		var enableNaiveAngleFallback: Bool = true
	}
	
	/// Finds circles in `source` (CGImage). Returns circles in the *downscaled* pixel space.
	static func find(in source: CGImage, cfg: Config = Config()) -> [DetectedCircle] {
		// 1) Downscale if needed
		let scale = downscaleFactor(for: source, maxSide: cfg.maxSide)
		let img = (scale < 1.0) ? source.resized(by: scale) : source
		let w = img.width, h = img.height
		if w == 0 || h == 0 { return [] }
		
		// 2) Make grayscale CIImage + Sobel Gx/Gy + magnitude
		let ci = CIImage(cgImage: img)
			.applyingFilter("CIColorControls", parameters: [
				kCIInputSaturationKey: 0.0,
				kCIInputBrightnessKey: 0.0,
				kCIInputContrastKey: 1.05
			])
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.6])
		
		let kx = CIVector(values: [-1,0,1,-2,0,2,-1,0,1], count: 9)
		let ky = CIVector(values: [-1,-2,-1,0,0,0,1,2,1], count: 9)
		let gxImg = ci.applyingFilter("CIConvolution3X3", parameters: ["inputWeights": kx])
		let gyImg = ci.applyingFilter("CIConvolution3X3", parameters: ["inputWeights": ky])
		
		guard let gxCG = gxImg.makeCGImage(),
			  let gyCG = gyImg.makeCGImage() else { return [] }
		
		// Use the w/h we defined at the top of find()
		let count = w * h
		
		// Read gradient images into floats
		let Gx: [Float] = gxCG.toFloatGray()
		let Gy: [Float] = gyCG.toFloatGray()
		
		// Robust magnitude: hypot(Gx, Gy)
		var mag = [Float](repeating: 0, count: count)
		for i in 0..<count {
			mag[i] = hypotf(Gx[i], Gy[i])
		}
		normalize(&mag)
		
		// Loose threshold so we actually keep weak edges on brushed metal
		let thr: Float = max(0.10, percentile(mag, 0.25))
		
		// 5) Accumulator (centers)
		var acc = [UInt16](repeating: 0, count: w * h)
		@inline(__always) func accIdx(_ x: Int,_ y: Int) -> Int { y * w + x }
		
		// 6) Iterate edge pixels; vote along inward normal for each radius
		let rMin = Int(cfg.minRadius.rounded(.toNearestOrAwayFromZero))
		let rMax = Int(cfg.maxRadius.rounded(.toNearestOrAwayFromZero))
		let rStep = max(1, Int(cfg.radiusStep.rounded()))
		
		for y in 1..<(h - 1) {
			for x in 1..<(w - 1) {
				let i = accIdx(x, y)
				if mag[i] < Float(thr) { continue }
				
				let gxv = Gx[i], gyv = Gy[i]
				let len = sqrtf(gxv * gxv + gyv * gyv)
				if len < 1e-5 { continue }
				// inward normal (unit)
				let nx = gxv / len
				let ny = gyv / len
				
				var r = rMin
				while r <= rMax {
					// inward
					var cx = Int(roundf(Float(x) - Float(r) * nx))
					var cy = Int(roundf(Float(y) - Float(r) * ny))
					if cx > 1 && cy > 1 && cx < (w - 2) && cy < (h - 2) {
						let ai = accIdx(cx, cy)
						if acc[ai] < UInt16.max { acc[ai] &+= 1 }
					}
					// outward
					cx = Int(roundf(Float(x) + Float(r) * nx))
					cy = Int(roundf(Float(y) + Float(r) * ny))
					if cx > 1 && cy > 1 && cx < (w - 2) && cy < (h - 2) {
						let ai = accIdx(cx, cy)
						if acc[ai] < UInt16.max { acc[ai] &+= 1 }
					}
					r += rStep
				}
			}
		}
		
		// 7) Pick peaks and estimate per-peak radius by maximizing radial vote density
		let maxAcc = (acc.max() ?? 0)
		if maxAcc == 0 { return [] }
		
		var raw: [DetectedCircle] = []
		// Simple threshold relative to radius arc length: votes ~ circumference
		// We'll approximate expected votes by using a fraction of max accumulator.
		let acceptLevel = UInt16(max(2, Int(Float(maxAcc) * 0.12)))
		
		for y in 1..<(h - 1) {
			for x in 1..<(w - 1) {
				let v = acc[accIdx(x, y)]
				if v < acceptLevel { continue }
				// local maxima check
				var isPeak = true
				for yy in (y - 1)...(y + 1) where isPeak {
					for xx in (x - 1)...(x + 1) where !(xx == x && yy == y) {
						if acc[accIdx(xx, yy)] > v { isPeak = false; break }
					}
				}
				if !isPeak { continue }
				
				// Estimate radius by sampling radial edge density
				let bestR = estimateRadius(at: CGPoint(x: x, y: y),
										   Gx: Gx, Gy: Gy, mag: mag,
										   w: w, h: h, rMin: rMin, rMax: rMax)
				let refined = refineCenter(from: CGPoint(x: x, y: y),
										   Gx: Gx, Gy: Gy, mag: mag,
										   w: w, h: h, r: bestR, thr: thr)
				
				let (cov, out, hits) = quality(at: refined, radius: bestR, Gx: Gx, Gy: Gy, mag: mag,
											   w: w, h: h, thr: thr)
				
				if cov >= 0.38, out >= 0.28, hits >= 8 {
					raw.append(DetectedCircle(center: refined,
											  radius: CGFloat(bestR),
											  score: Float(v)))
				}
			}
		}

		let rawCountDirected = raw.count
		if rawCountDirected == 0, cfg.enableNaiveAngleFallback {
			// Rebuild a fresh accumulator for angle sweep
			var acc2 = [UInt16](repeating: 0, count: w*h)
			@inline(__always) func acc2Idx(_ x:Int,_ y:Int)->Int { y*w + x }
			
			// Precompute 12 unit directions on the circle
			let K = 12
			let dirs: [(Float,Float)] = (0..<K).map { k in
				let a = (Float(k)/Float(K)) * 2 * Float.pi
				return (cosf(a), sinf(a))
			}
			
			let rMin = Int(cfg.minRadius.rounded(.toNearestOrAwayFromZero))
			let rMax = Int(cfg.maxRadius.rounded(.toNearestOrAwayFromZero))
			let rStep = max(1, Int(cfg.radiusStep.rounded()))
			
			// For each edge pixel, vote every angle for each radius
			for y in 1..<(h-1) {
				for x in 1..<(w-1) {
					let i = y*w + x
					if mag[i] < thr { continue }
					var r = rMin
					while r <= rMax {
						for (cx, cy) in dirs {
							let cxInt = Int(roundf(Float(x) - Float(r)*cx))
							let cyInt = Int(roundf(Float(y) - Float(r)*cy))
							if cxInt>1 && cyInt>1 && cxInt<(w-2) && cyInt<(h-2) {
								let ai = acc2Idx(cxInt, cyInt)
								if acc2[ai] < UInt16.max { acc2[ai] &+= 1 }
							}
						}
						r += rStep
					}
				}
			}
			
			// Pick peaks from acc2
			let maxAcc2 = (acc2.max() ?? 0)
			if maxAcc2 > 0 {
				var raw2: [DetectedCircle] = []
				let accept2 = UInt16(max(2, Int(Float(maxAcc2) * 0.10))) // loose accept
				for y in 1..<(h-1) {
					for x in 1..<(w-1) {
						let v = acc2[acc2Idx(x,y)]
						if v < accept2 { continue }
						// local max
						var isPeak = true
						for yy in (y-1)...(y+1) where isPeak {
							for xx in (x-1)...(x+1) where !(xx==x && yy==y) {
								if acc2[acc2Idx(xx,yy)] > v { isPeak = false; break }
							}
						}
						if !isPeak { continue }
						let bestR = estimateRadius(at: CGPoint(x: x, y: y),
												   Gx: Gx, Gy: Gy, mag: mag,
												   w: w, h: h,
												   rMin: rMin, rMax: rMax)
						let refined = refineCenter(from: CGPoint(x: x, y: y),
												   Gx: Gx, Gy: Gy, mag: mag,
												   w: w, h: h, r: bestR, thr: thr)
						
						let (cov, out, hits) = quality(at: refined, radius: bestR, Gx: Gx, Gy: Gy, mag: mag,
													   w: w, h: h, thr: thr)
						
						if cov >= 0.38, out >= 0.28, hits >= 8 {
							raw2.append(DetectedCircle(center: refined,
													  radius: CGFloat(bestR),
													  score: Float(v)))
						}
					}
				}
				// Replace the raw set if fallback found anything
				if !raw2.isEmpty {
					// print("CircleFinder fallback hit: \(raw2.count) peaks") // optional debug
					var tmp = nms(raw2, within: cfg.nmsRadius)
					if tmp.count > cfg.maxResults { tmp = Array(tmp.prefix(cfg.maxResults)) }
					return tmp
				}
			}
		}

		// --- FINAL FALLBACK: center-grid ring sampler (no gradients needed) ---
		if raw.isEmpty {
			// Build a coarse edge map from magnitude so we can count ring pixels quickly
			// We already have `mag` (Float 0..1) and `w`,`h` in scope.
			// Choose a very loose threshold to keep weak edges.
			let loose = max(0.06, percentile(mag, 0.08))
			
			// Center grid stride (in downscaled pixels)
			let cxStep = max(3, Int((min(w, h)).quotientAndRemainder(dividingBy: 120).remainder == 0 ? (min(w, h)/120) : (min(w,h)/80)))
			let cyStep = cxStep
			
			// Precompute ring offsets for each radius
			let rMin = Int(cfg.minRadius.rounded(.toNearestOrAwayFromZero))
			let rMax = Int(cfg.maxRadius.rounded(.toNearestOrAwayFromZero))
			let rStep = max(1, Int(cfg.radiusStep.rounded()))
			
			struct Ring { var dx: [Int]; var dy: [Int] }
			var rings: [Int: Ring] = [:]
			@inline(__always) func makeRing(_ r: Int) -> Ring {
				if let existing = rings[r] { return existing }
				var dx: [Int] = [], dy: [Int] = []
				// 36 samples around the circle
				for k in 0..<36 {
					let a = (Float(k) / 36.0) * 2.0 * Float.pi
					dx.append(Int(roundf(Float(r) * cosf(a))))
					dy.append(Int(roundf(Float(r) * sinf(a))))
				}
				let ring = Ring(dx: dx, dy: dy)
				rings[r] = ring
				return ring
			}
			
			@inline(__always) func idx(_ x: Int,_ y: Int) -> Int { y*w + x }
			
			var acc = [UInt16](repeating: 0, count: w*h)
			
			// For each center on a grid, score the best radius by counting ring hits from mag[]
			for cy in stride(from: rMax+2, through: h - rMax - 3, by: cyStep) {
				for cx in stride(from: rMax+2, through: w - rMax - 3, by: cxStep) {
					var bestHits = 0
					var r = rMin
					while r <= rMax {
						let ring = makeRing(r)
						var hits = 0
						var s = 0
						while s < ring.dx.count {
							let x = cx + ring.dx[s]
							let y = cy + ring.dy[s]
							let m = mag[idx(x, y)]
							if m >= loose { hits += 1 }
							s += 1
						}
						if hits > bestHits { bestHits = hits }
						r += rStep
					}
					// If the best ring has ≥ 40% of its samples above loose threshold, vote this center
					if bestHits >= Int(0.40 * 36.0) {
						let ai = idx(cx, cy)
						if acc[ai] < UInt16.max { acc[ai] &+= UInt16(bestHits) }
					}
				}
			}
			
			// Turn center votes into peaks and estimate radius by re-sampling rings densely
			let maxAcc = (acc.max() ?? 0)
			if maxAcc > 0 {
				var rawGrid: [DetectedCircle] = []
				let accept = UInt16(max(2, Int(Float(maxAcc) * 0.40))) // keep stronger centers
				for y in rMax+2..<(h - rMax - 2) {
					for x in rMax+2..<(w - rMax - 2) {
						let v = acc[idx(x,y)]
						if v < accept { continue }
						// local max
						var isPeak = true
						for yy in (y-1)...(y+1) where isPeak {
							for xx in (x-1)...(x+1) where !(xx==x && yy==y) {
								if acc[idx(xx,yy)] > v { isPeak = false; break }
							}
						}
						if !isPeak { continue }
						
						// dense radius estimation at this peak (similar to estimateRadius)
						var bestR = rMin, bestScore = -1
						var r = rMin
						while r <= rMax {
							let ring = makeRing(r)
							var hits = 0
							for s in 0..<ring.dx.count {
								let x2 = x + ring.dx[s]
								let y2 = y + ring.dy[s]
								let m = mag[idx(x2, y2)]
								if m >= loose { hits += 1 }
							}
							if hits > bestScore { bestScore = hits; bestR = r }
							r += 1
						}
						let (cov, out, hits) = quality(at: CGPoint(x: x, y: y),
													   radius: bestR, Gx: Gx, Gy: Gy, mag: mag,
													   w: w, h: h, thr: thr)
						if cov >= 0.38, out >= 0.28, hits >= 8 {
							rawGrid.append(DetectedCircle(center: CGPoint(x: x, y: y),
														  radius: CGFloat(bestR),
														  score: Float(v)))
						}
					}
				}
				if !rawGrid.isEmpty {
					var kept = nms(rawGrid, within: cfg.nmsRadius)
					if kept.count > cfg.maxResults { kept = Array(kept.prefix(cfg.maxResults)) }
					return kept
				}
			}
		}

		// 8) NMS over peaks
		let kept = nms(raw, within: cfg.nmsRadius)
		
		// 9) Cap results
		return Array(kept.prefix(cfg.maxResults))
	}
	
	// MARK: Internals
	
	private static func estimateRadius(at c: CGPoint, Gx: [Float], Gy: [Float], mag: [Float],
									   w: Int, h: Int, rMin: Int, rMax: Int) -> Int {
		@inline(__always) func idx(_ x: Int,_ y: Int) -> Int { y * w + x }
		var bestR = rMin, bestScore: Float = 0
		var r = rMin
		while r <= rMax {
			// sample 12 angles on the circle; count how many are edges
			var hits: Float = 0
			for k in 0..<12 {
				let ang = (Float(k) / 12.0) * 2.0 * .pi
				let sx = Int(round(c.x + CGFloat(r) * CGFloat(cosf(ang))))
				let sy = Int(round(c.y + CGFloat(r) * CGFloat(sinf(ang))))
				if sx <= 1 || sy <= 1 || sx >= w - 2 || sy >= h - 2 { continue }
				let m = mag[idx(sx, sy)]
				if m > 0.2 { hits += 1 }
			}
			if hits > bestScore { bestScore = hits; bestR = r }
			r += 1
		}
		return bestR
	}
	
	/// Evaluate a candidate circle by sampling the ring and measuring angular coverage and gradient alignment.
	/// Returns (coverage in 0..1, outward alignment in 0..1, hit count).
	private static func quality(at c: CGPoint, radius r: Int,
								Gx: [Float], Gy: [Float], mag: [Float],
								w: Int, h: Int, thr: Float) -> (Float, Float, Int) {
		@inline(__always) func idx(_ x: Int,_ y: Int) -> Int { y*w + x }
		let K = 36                    // samples around circle
		let sectors = 12              // angular bins
		var sectorHit = [Int](repeating: 0, count: sectors)
		var outwardHits = 0
		var totalHits  = 0
		
		for k in 0..<K {
			let ang = (Float(k) / Float(K)) * 2.0 * .pi
			let sx = Int(round(c.x + CGFloat(r) * CGFloat(cosf(ang))))
			let sy = Int(round(c.y + CGFloat(r) * CGFloat(sinf(ang))))
			if sx<=1 || sy<=1 || sx>=w-2 || sy>=h-2 { continue }
			let i = idx(sx, sy)
			if mag[i] >= thr {
				totalHits += 1
				
				// sector coverage
				let bin = Int(floor(Float(sectors) * (Float(k)/Float(K))))
				sectorHit[min(max(0, bin), sectors-1)] += 1
				
				// outward alignment (grad roughly radial)
				let gx = Gx[i], gy = Gy[i]
				let glen = max(1e-5, sqrtf(gx*gx + gy*gy))
				let rx = Float(sx) - Float(c.x), ry = Float(sy) - Float(c.y)
				let rlen = max(1e-5, sqrtf(rx*rx + ry*ry))
				let dot = (gx/glen) * (rx/rlen) + (gy/glen) * (ry/rlen)
				if abs(dot) > 0.4 { outwardHits += 1 } // sign can flip; we just want “radial”
			}
		}
		
		let covered = Float(sectorHit.filter { $0 > 0 }.count) / Float(sectors)   // 0..1
		let outward = totalHits > 0 ? Float(outwardHits) / Float(totalHits) : 0.0 // 0..1
		return (covered, outward, totalHits)
	}

	// Search a small window around an initial center and pick the offset with the best ring quality.
	private static func refineCenter(from c: CGPoint,
									 Gx: [Float], Gy: [Float], mag: [Float],
									 w: Int, h: Int, r: Int, thr: Float) -> CGPoint {
		@inline(__always) func idx(_ x: Int,_ y: Int) -> Int { y*w + x }
		// search window proportional to radius; knobs often pull upward, so allow deeper vertical search
		let dxy = max(1, Int(round(Double(r) * 0.10)))
		let dy  = dxy
		var best = c
		var bestScore: Float = -1
		
		var yy = -dy
		while yy <= dy {
			var xx = -dxy
			while xx <= dxy {
				let cx = Int(round(c.x)) + xx
				let cy = Int(round(c.y)) + yy
				if cx <= 1 || cy <= 1 || cx >= w-2 || cy >= h-2 { xx += 1; continue }
				let (cov, out, _) = quality(at: CGPoint(x: cx, y: cy),
											   radius: r, Gx: Gx, Gy: Gy, mag: mag,
											   w: w, h: h, thr: thr)
				// coverage first, then outward alignment; both in 0..1
				let score = cov * 0.75 + out * 0.25
				if score > bestScore {
					bestScore = score
					best = CGPoint(x: cx, y: cy)
				}
				xx += 1
			}
			yy += 1
		}
		return best
	}

	private static func nms(_ circles: [DetectedCircle], within rad: CGFloat) -> [DetectedCircle] {
		var sorted = circles.sorted { $0.score > $1.score }
		var kept: [DetectedCircle] = []
		@inline(__always) func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
			let dx = a.x - b.x, dy = a.y - b.y
			return sqrt(dx*dx + dy*dy)
		}
		while let c = sorted.first {
			kept.append(c)
			sorted.removeFirst()
			sorted.removeAll { dist($0.center, c.center) < rad }
		}
		return kept
	}
}

// MARK: - Small CG/CI helpers

private func downscaleFactor(for cg: CGImage, maxSide: CGFloat) -> CGFloat {
	let side = max(cg.width, cg.height)
	return side > Int(maxSide) ? maxSide / CGFloat(side) : 1.0
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
}

private extension CIImage {
	func makeCGImage(context: CIContext = CIContext()) -> CGImage? {
		context.createCGImage(self, from: extent)
	}
}

private func normalize(_ a: inout [Float]) {
	var lo = Float.greatestFiniteMagnitude, hi: Float = 0
	for v in a { lo = min(lo, v); hi = max(hi, v) }
	let d = max(1e-6, hi - lo)
	for i in a.indices { a[i] = (a[i] - lo) / d }
}

private func percentile(_ a: [Float], _ p: Double) -> Float {
	let n = a.count
	if n == 0 { return 0 }
	let k = max(0, min(n - 1, Int(Double(n - 1) * p)))
	let sorted = a.sorted()
	return sorted[k]
}

private extension CGImage {
	// Read single-channel brightness approx into Float array 0..1
	func toFloatGray() -> [Float] {
		let w = width, h = height
		let ctx = CGContext(data: nil, width: w, height: h,
							bitsPerComponent: 8, bytesPerRow: w * 4,
							space: CGColorSpaceCreateDeviceRGB(),
							bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		ctx.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
		let raw = ctx.data!.assumingMemoryBound(to: UInt8.self)
		var out = [Float](repeating: 0, count: w * h)
		for i in 0..<(w * h) {
			let r = raw[i*4+0], g = raw[i*4+1], b = raw[i*4+2]
			let m = (0.2126*Float(r) + 0.7152*Float(g) + 0.0722*Float(b)) / 255.0
			out[i] = m
		}
		return out
	}
}
