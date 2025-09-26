//
//  BandsDebugStripes.swift
//  Studio Recall
//
//  Created by True Jackie on 9/26/25.
//
import SwiftUI

 struct BandsDebugStripes: View {
	let image: NSImage
	let fitted: CGRect
	let sx: CGFloat
	let sy: CGFloat
	let ox: CGFloat
	let oy: CGFloat
	
	// --- Local copies so we don't depend on private helpers in ControlAutoDetect.swift ---
	
	private func localPercentileMask(from cg: CGImage, keepTopFraction p: Double) -> CGImage {
		let w = cg.width, h = cg.height
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
		
		var hist = [Int](repeating: 0, count: 256)
		for v in mags { hist[Int(v)] &+= 1 }
		let target = Int(Double(w*h) * (1.0 - p))
		var sum = 0, cutoff = 255
		for t in 0..<256 {
			sum += hist[t]
			if sum >= target { cutoff = t; break }
		}
		
		var bin = [UInt8](repeating: 0, count: w*h)
		for i in 0..<(w*h) { bin[i] = mags[i] >= cutoff ? 255 : 0 }
		
		let provider = CGDataProvider(data: Data(bin) as CFData)!
		return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
					   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
					   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
	}
	
	/// Very small port of `rowBands(from:)` tuned for debug overlay.
	private func localRowBands(from mask: CGImage) -> [ClosedRange<CGFloat>] {
		let w = mask.width, h = mask.height
		guard let data = mask.dataProvider?.data as Data? else { return [] }
		let g = Array(data) // 0 or 255
		
		// 1) Plate interior via column medians
		var tops = [Int](), bots = [Int]()
		tops.reserveCapacity(w); bots.reserveCapacity(w)
		for x in 0..<w {
			var t = -1, b = -1
			var base = x
			var y = 0
			while y < h { if g[base] != 0 { t = y; break }; y += 1; base += w }
			if t != -1 {
				base = x + (h-1)*w; y = h-1
				while y >= 0 { if g[base] != 0 { b = y; break }; y -= 1; base -= w }
			}
			if t != -1, b != -1, b > t { tops.append(t); bots.append(b) }
		}
		guard !tops.isEmpty else { return [] }
		func median(_ a: [Int]) -> Int { var s = a; s.sort(); return s[s.count/2] }
		let topMed = median(tops), botMed = median(bots)
		if botMed - topMed < max(24, h/6) { return [] }
		
		let interiorH = botMed - topMed
		let shrink = max(6, Int(Double(interiorH) * 0.14))
		let yMin = max(0, topMed + shrink)
		let yMax = min(h-1, botMed - shrink)
		if yMax <= yMin { return [] }
		
		let pad = max(6, Int(Double(interiorH) * 0.16))
		let safeMin = max(0, yMin + pad)
		let safeMax = min(h-1, yMax - pad)
		guard safeMax > safeMin else { return [] }
		
		// 2) Row choppiness score
		var score = [Double](repeating: 0, count: h)
		for y in safeMin...safeMax {
			let rowBase = y*w
			var transitions = 0
			var runLen = 0, maxRun = 0
			var on = false
			for x in 0..<w {
				let bit = (g[rowBase + x] != 0)
				if bit { runLen += 1 }
				if bit != on {
					transitions += 1
					if !bit { maxRun = max(maxRun, runLen); runLen = 0 }
					on = bit
				}
			}
			maxRun = max(maxRun, runLen)
			if maxRun > Int(Double(w) * 0.35) { continue }
			if transitions > 0 {
				var s = pow(Double(transitions), 1.2)
				let dTop = Double(y - safeMin)
				let dBot = Double(safeMax - y)
				let d = min(dTop, dBot) / Double(max(1, safeMax - safeMin))
				let edgeTaper = max(0.0, min(1.0, (d - 0.05) / 0.45))
				s *= edgeTaper
				score[y] = s
			}
		}
		let win = 4
		var sm = score
		for y in yMin...yMax {
			var s = 0.0; var n = 0
			let lo = max(yMin, y - win)
			let hi = min(yMax, y + win)
			for k in lo...hi { s += score[k]; n += 1 }
			sm[y] = n > 0 ? s / Double(n) : 0
		}
		var peaks: [Int] = []
		if yMax - yMin >= 3 {
			for y in (yMin+1)..<(yMax-1) {
				if sm[y] > sm[y-1], sm[y] > sm[y+1] { peaks.append(y) }
			}
		}
		peaks.sort { sm[$0] > sm[$1] }
		
		let bw = Int(Double(interiorH) * 0.20)
		var out: [ClosedRange<CGFloat>] = []
		if !peaks.isEmpty {
			for y in peaks.prefix(2) {
				let a = max(safeMin, y - bw), b = min(safeMax, y + bw)
				out.append(CGFloat(a)...CGFloat(b))
			}
		} else {
			let c1 = safeMin + (safeMax - safeMin)/3
			let c2 = safeMin + 2*(safeMax - safeMin)/3
			let a1 = max(yMin, c1 - bw), b1 = min(yMax, c1 + bw)
			out.append(CGFloat(a1)...CGFloat(b1))
			if b1 - a1 > 24 {
				let a2 = max(yMin, c2 - bw), b2 = min(yMax, c2 + bw)
				out.append(CGFloat(a2)...CGFloat(b2))
			}
		}
		return out
	}
	
	// Build an edge image → percentile mask → row bands (full-res)
	private func computeBands() -> (bands: [ClosedRange<CGFloat>], maskH: CGFloat)? {
		// Access CGImage without relying on file-private helpers in another file
		let cg: CGImage? = {
			if let fast = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return fast }
			guard let tiff = image.tiffRepresentation,
				  let rep  = NSBitmapImageRep(data: tiff),
				  let slow = rep.cgImage else { return nil }
			return slow
		}()
		guard let cgSrc = cg else { return nil }
		
		let ci = CIImage(cgImage: cgSrc)
			.applyingFilter("CIColorControls", parameters: [
				kCIInputSaturationKey: 0.0,
				kCIInputBrightnessKey: 0.0,
				kCIInputContrastKey:   1.05
			])
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
			.applyingFilter("CILineOverlay", parameters: [
				"inputNRNoiseLevel": 0.01,
				"inputNRSharpness": 0.6,
				"inputEdgeIntensity": 1.0,
				"inputThreshold": 0.1,
				"inputContrast": 50.0
			])
		
		let ctx = CIContext()
		guard let edgeCG = ctx.createCGImage(ci, from: ci.extent) else { return nil }
		let mask = localPercentileMask(from: edgeCG, keepTopFraction: 0.06)
		let bands = localRowBands(from: mask)
		return (bands, CGFloat(mask.height))
	}
	
	var body: some View {
		let result = computeBands()
		let bands  = result?.bands ?? []
		let maskH  = result?.maskH  ?? 1
		
		ZStack(alignment: .topLeading) {
			ForEach(Array(bands.enumerated()), id: \.offset) { idx, band in
				let y0Mask = band.lowerBound
				let y1Mask = band.upperBound
				let y0View = oy + (y0Mask / maskH) * fitted.height
				let y1View = oy + (y1Mask / maskH) * fitted.height
				let hView  = max(1, y1View - y0View)
				
				let hue = Double((idx * 53) % 360) / 360.0
				
				Rectangle()
					.fill(Color(hue: hue, saturation: 0.6, brightness: 0.9))
					.opacity(0.18)
					.frame(width: fitted.width, height: hView)
					.position(x: fitted.midX, y: y0View + hView * 0.5)
				
				Text("Band \(idx)")
					.font(.caption2).bold()
					.foregroundColor(.white.opacity(0.85))
					.padding(.horizontal, 4)
					.background(Color.black.opacity(0.35))
					.clipShape(RoundedRectangle(cornerRadius: 3))
					.position(x: fitted.minX + 42, y: max(fitted.minY, y0View) + 10)
			}
		}
		.allowsHitTesting(false)
	}
}
