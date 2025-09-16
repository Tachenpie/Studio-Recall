//
//  SpriteLibrary.swift
//  Studio Recall
//
//  Created by True Jackie on 9/9/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import CryptoKit

struct SpriteAsset: Codable, Identifiable, Equatable {
	enum Source: String, Codable { case atlasGrid, frames }
	let id: UUID
	var name: String
	var source: Source
	// Storage-relative paths
	var atlasPath: String?      // when source == .atlasGrid
	var framePaths: [String]?   // when source == .frames
	// Grid meta (atlas mode)
	var cols: Int
	var rows: Int
	// Defaults (can be overridden per-control)
	var spritePivot: CGPoint = CGPoint(x: 0.5, y: 0.9)
	var defaultScale: Double = 1.0
	// For deduplication / debugging
	var digestHex: String
	// Optional tags for the “bank”
	var tags: [String] = []
	var isBuiltin: Bool = false
}

final class SpriteLibrary {
	static let shared = SpriteLibrary()
	
	private let fm = FileManager.default
	private let root: URL
	private let imagesDir: URL
	private let indexURL: URL
	
	private var index: [UUID: SpriteAsset] = [:]
	
	private init() {
		let support = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
								  appropriateFor: nil, create: true)
		root = support.appendingPathComponent("StudioRecall/Sprites", isDirectory: true)
		imagesDir = root.appendingPathComponent("img", isDirectory: true)
		indexURL = root.appendingPathComponent("index.json")
		try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
		loadIndex()
	}
	
	// MARK: Public API
	
	func allAssets() -> [SpriteAsset] { Array(index.values).sorted { $0.name < $1.name } }
	
	func asset(_ id: UUID) -> SpriteAsset? { index[id] }
	
	func cgImage(forFrame indexNum: Int, in assetId: UUID) -> CGImage? {
		guard let a = index[assetId] else { return nil }
		switch a.source {
			case .frames:
				guard let paths = a.framePaths, indexNum < paths.count else { return nil }
				let url = root.appendingPathComponent(paths[indexNum])
				return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
			case .atlasGrid:
				guard let atlasRel = a.atlasPath else { return nil }
				let url = root.appendingPathComponent(atlasRel)
				guard let cg = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
				guard a.cols > 0, a.rows > 0 else { return cg }
				let fw = cg.width / a.cols, fh = cg.height / a.rows
				let clamped = max(0, min(indexNum, a.cols * a.rows - 1))
				let col = clamped % a.cols, row = clamped / a.cols
				let crop = CGRect(x: col * fw, y: (a.rows - 1 - row) * fh, width: fw, height: fh)
				return cg.cropping(to: crop)
		}
	}
	
	/// Update an existing SpriteAsset in the index and save to disk
	func update(_ asset: SpriteAsset) {
		// Replace or insert
		index[asset.id] = asset
		
		// Save back to disk
		do {
			let url = indexURL
			let data = try JSONEncoder().encode(index)
			try data.write(to: url, options: [.atomic])
		} catch {
			print("❌ Failed to update asset \(asset.id): \(error)")
		}
	}

	/// Import a grid atlas; returns existing asset if identical content is already present.
	func importAtlas(name: String, data: Data, cols: Int, rows: Int,
					 spritePivot: CGPoint = CGPoint(x: 0.5, y: 0.9),
					 defaultScale: Double = 1.0,
					 tags: [String] = [], isBuiltin: Bool = false) throws -> SpriteAsset
	{
		let digest = Self.sha256Hex(data)
		if let existing = index.values.first(where: { $0.digestHex == digest }) { return existing }
		let id = UUID()
		let filename = "\(id.uuidString).png"
		let url = imagesDir.appendingPathComponent(filename)
		try data.write(to: url, options: .atomic)
		
		let a = SpriteAsset(id: id, name: name, source: .atlasGrid,
							atlasPath: "img/\(filename)", framePaths: nil,
							cols: cols, rows: rows,
							spritePivot: spritePivot, defaultScale: defaultScale,
							digestHex: digest, tags: tags, isBuiltin: isBuiltin)
		index[id] = a
		saveIndex()
		return a
	}
	
	/// Import N frames; de-duplicates using combined hash.
	func importFrames(
		name: String,
		frames: [Data],
		spritePivot: CGPoint? = nil,
		defaultScale: Double = 1.0,
		tags: [String] = [],
		isBuiltin: Bool = false
	) throws -> SpriteAsset {
		guard !frames.isEmpty else {
			throw NSError(domain: "SpriteLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: "No frames provided"])
		}
		
		// Write files to disk
		var relPaths: [String] = []
		for (_, data) in frames.enumerated() {
			let idStr = UUID().uuidString
			let filename = "\(idStr).png"
			let url = imagesDir.appendingPathComponent(filename)
			try data.write(to: url, options: .atomic)
			relPaths.append("img/\(filename)")
		}
		
		// Compute digest over all frame data concatenated
		let digest = frames.reduce(into: Data()) { $0.append($1) }
		let digestHex = Self.sha256Hex(digest)
		
		// Auto-detect pivot if not provided
		var autoPivot = spritePivot
		if spritePivot == nil {
			var commonRect: CGRect?
			for data in frames {
				if let nsImage = NSImage(data: data),
				   let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
				   let bbox = opaqueBoundingBox(cgImage: cgImage) {
					commonRect = commonRect.map { $0.intersection(bbox) } ?? bbox
				}
			}
			if let rect = commonRect,
			   let nsImage = NSImage(data: frames[0]),
			   let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
				autoPivot = CGPoint(x: rect.midX / CGFloat(cgImage.width),
									y: rect.midY / CGFloat(cgImage.height))
				print("Auto-detected pivot: \(autoPivot!) for \(name)")
			}
		}
		print("Auto-detected pivot for \(name): \(autoPivot ?? .zero)")

		
		// Create asset
		let id = UUID()
		let asset = SpriteAsset(
			id: id,
			name: name,
			source: .frames,
			atlasPath: nil,
			framePaths: relPaths,
			cols: 1,
			rows: frames.count,
			spritePivot: autoPivot ?? CGPoint(x: 0.5, y: 0.9),
			defaultScale: defaultScale,
			digestHex: digestHex,
			tags: tags,
			isBuiltin: isBuiltin
		)
		
		index[id] = asset
		saveIndex()
		return asset
	}


	private func opaqueBoundingBox(cgImage: CGImage) -> CGRect? {
		guard let data = cgImage.dataProvider?.data,
			  let ptr = CFDataGetBytePtr(data) else { return nil }
		
		let bytesPerPixel = cgImage.bitsPerPixel / 8
		let width = cgImage.width
		let height = cgImage.height
		
		var minX = width, maxX = 0, minY = height, maxY = 0
		
		for y in 0..<height {
			for x in 0..<width {
				let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
				let alpha = ptr[offset + (bytesPerPixel - 1)]
				if alpha > 0 {
					minX = min(minX, x)
					maxX = max(maxX, x)
					minY = min(minY, y)
					maxY = max(maxY, y)
				}
			}
		}
		
		if minX <= maxX && minY <= maxY {
			return CGRect(x: minX, y: minY,
						  width: maxX - minX + 1,
						  height: maxY - minY + 1)
		}
		return nil
	}

	
	/// Migrate embedded sprite data from a mapping into the library and rewrite the mapping to reference it.
	func migrateEmbeddedSprites(in mapping: inout VisualMapping, suggestedName: String) {
		if mapping.spriteAssetId != nil { return }
		if let atlas = mapping.spriteAtlasPNG, let cols = mapping.spriteCols, let rows = mapping.spriteRows {
			if let asset = try? importAtlas(name: suggestedName, data: atlas, cols: cols, rows: rows) {
				mapping.spriteAssetId = asset.id
				mapping.spriteAtlasPNG = nil
			}
		} else if let frames = mapping.spriteFrames, !frames.isEmpty {
			if let asset = try? importFrames(name: suggestedName, frames: frames) {
				mapping.spriteAssetId = asset.id
				mapping.spriteFrames = nil
			}
		}
	}
	
	// MARK: - Built-ins seeding
	
	/// Call once on app launch (idempotent). Looks for a manifest or scans a "SpriteBuiltins" bundle folder.
	func registerBuiltinsIfNeeded() {
		let defaultsKey = "SpriteLibraryBuiltinsSeeded_v1"
		let defaults = UserDefaults.standard
		if defaults.bool(forKey: defaultsKey) { return }
		
#if os(macOS)
		let bundle = Bundle.main
		
		// 1) Try a JSON manifest first (recommended for complex sets)
		if let manifestURL = bundle.url(forResource: "SpriteBuiltins", withExtension: "json"),
		   let data = try? Data(contentsOf: manifestURL) {
			seedFromManifest(data: data, in: bundle)
			defaults.set(true, forKey: defaultsKey)
			return
		}
		
		// 2) Fallback: auto-scan a "SpriteBuiltins" subfolder for PNG atlases
		//    Filename convention: Name_CxR.png  (e.g. "ChromeToggle_2x1.png")
		let pngs = bundle.urls(forResourcesWithExtension: "png", subdirectory: "SpriteBuiltins") ?? []
		for url in pngs {
			guard let data = try? Data(contentsOf: url) else { continue }
			let name = url.deletingPathExtension().lastPathComponent
			let (cols, rows) = parseColsRows(from: name) ?? (2, 1)
			_ = try? importAtlas(name: name, data: data, cols: cols, rows: rows,
								 spritePivot: CGPoint(x: 0.5, y: 0.9),
								 defaultScale: 1.0,
								 tags: ["builtin"], isBuiltin: true)
		}
#endif
		
		defaults.set(true, forKey: defaultsKey)
	}

#if os(macOS)
	// Manifest format (optional). Place "SpriteBuiltins.json" alongside your images in the bundle.
	private struct BuiltinManifest: Codable {
		struct Atlas: Codable {
			let name: String
			let file: String
			let cols: Int
			let rows: Int
			let tags: [String]?
			let spritePivotX: Double?
			let spritePivotY: Double?
			let scale: Double?
		}
		struct Frames: Codable {
			let name: String
			let files: [String]
			let tags: [String]?
			let spritePivotX: Double?
			let spritePivotY: Double?
			let scale: Double?
		}
		let atlases: [Atlas]?
		let frames: [Frames]?
	}
	
	private func seedFromManifest(data: Data, in bundle: Bundle) {
		guard let m = try? JSONDecoder().decode(BuiltinManifest.self, from: data) else { return }
		
		if let atlases = m.atlases {
			for a in atlases {
				guard let url = bundle.url(forResource: a.file, withExtension: nil, subdirectory: "SpriteBuiltins"),
					  let d = try? Data(contentsOf: url) else { continue }
				_ = try? importAtlas(name: a.name, data: d, cols: a.cols, rows: a.rows,
									 spritePivot: CGPoint(x: a.spritePivotX ?? 0.5, y: a.spritePivotY ?? 0.9),
									 defaultScale: a.scale ?? 1.0,
									 tags: (a.tags ?? []) + ["builtin"], isBuiltin: true)
			}
		}
		
		if let sets = m.frames {
			for s in sets {
				var framesData: [Data] = []
				for f in s.files {
					guard let url = bundle.url(forResource: f, withExtension: nil, subdirectory: "SpriteBuiltins"),
						  let d = try? Data(contentsOf: url) else { continue }
					framesData.append(d)
				}
				guard !framesData.isEmpty else { continue }
				_ = try? importFrames(name: s.name, frames: framesData,
									  spritePivot: CGPoint(x: s.spritePivotX ?? 0.5, y: s.spritePivotY ?? 0.9),
									  defaultScale: s.scale ?? 1.0,
									  tags: (s.tags ?? []) + ["builtin"], isBuiltin: true)
			}
		}
	}
#endif
	
	/// Parse trailing "_CxR" (e.g., "ChromeToggle_2x1") → (2,1). Returns nil if not present.
	private func parseColsRows(from name: String) -> (Int, Int)? {
		guard let underscore = name.lastIndex(of: "_") else { return nil }
		let suffix = name[name.index(after: underscore)...]
		let parts = suffix.split(separator: "x")
		guard parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]) else { return nil }
		return (c, r)
	}

	// MARK: persistence
	private func loadIndex() {
		if let data = try? Data(contentsOf: indexURL),
		   let raw = try? JSONDecoder().decode([UUID: SpriteAsset].self, from: data) {
			index = raw
		}
	}
	private func saveIndex() {
		if let data = try? JSONEncoder().encode(index) {
			try? data.write(to: indexURL, options: .atomic)
		}
	}
	
	private static func sha256Hex(_ data: Data) -> String {
		let digest = SHA256.hash(data: data)
		return digest.compactMap { String(format: "%02x", $0) }.joined()
	}
}

extension SpriteLibrary {
	/// Convenience wrapper for importing a grid atlas.
	func importAtlasGrid(
		name: String,
		data: Data,
		cols: Int = 1,
		rows: Int = 1,
		spritePivot: CGPoint = CGPoint(x: 0.5, y: 0.9),
		defaultScale: Double = 1.0,
		tags: [String] = [],
		isBuiltin: Bool = false
	) throws -> SpriteAsset {
		return try importAtlas(
			name: name,
			data: data,
			cols: cols,
			rows: rows,
			spritePivot: spritePivot,
			defaultScale: defaultScale,
			tags: tags,
			isBuiltin: isBuiltin
		)
	}
}

extension SpriteLibrary {
	/// Load raw frame data for a given asset
	func loadFrameData(for asset: SpriteAsset) -> [Data]? {
		guard let paths = asset.framePaths else { return nil }
		return paths.compactMap {
			let filename = URL(fileURLWithPath: $0).lastPathComponent
			let url = imagesDir.appendingPathComponent(filename)
			return try? Data(contentsOf: url)
		}
	}
}

