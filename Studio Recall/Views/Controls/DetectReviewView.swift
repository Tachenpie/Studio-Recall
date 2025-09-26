//
//  DetectReviewView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


//  DetectReviewView.swift
//  Studio Recall

import SwiftUI
import AppKit
import AVFoundation

struct DetectReviewView: View {
    let image: NSImage
    let imagePixelSize: CGSize
	@Binding var drafts: [ControlDraft]

	// External control (when embedded in the Editor Detect tab)
	var selectedIDs: Binding<Set<UUID>>? = nil
	var selectedID:  Binding<UUID?>?      = nil
	var lassoMode:   Binding<Bool>?       = nil
	@Binding var focusedDraftID: UUID?

//	@State private var layoutPref: LayoutPref = .auto
	@State private var sensitivity: Double = 0.65 // 0..1, higher = more edges
	@State private var showEdgesPreview = false
	@State private var debugOverlay = false
	@State private var limitToBands = false
	
	// Debug overlays
	@State private var showBands: Bool = false                 // <-- fixes $showBands binding
	@State private var edgesPreview: NSImage? = nil            // cached edge overlay image
	
	// Detection state
	@State private var ranInitialDetect = false
	@State private var isDetecting = false
	@State private var detectToken = 0
	@State private var detectTask: Task<Void, Never>? = nil

    // Selection / edits
	enum FocusField: Hashable { case label }
	@FocusState private var focus: FocusField?
	@FocusState private var listFocusID: UUID?
	
	// multi-select / lasso
	@State private var lassoRect: CGRect? = nil
	// Local fallback (used when the editor doesn’t inject bindings)
	@State private var _selectedIDs: Set<UUID> = []
	@State private var _selectedID: UUID? = nil
	@State private var _lassoMode: Bool = false
	
	// Proxies that use external bindings when provided
	private var selectedIDsProxy: Binding<Set<UUID>> {
		selectedIDs ?? Binding(get: { _selectedIDs }, set: { _selectedIDs = $0 })
	}
	private var selectedIDProxy: Binding<UUID?> {
		selectedID ?? Binding(get: { _selectedID }, set: { _selectedID = $0 })
	}
	private var lassoModeProxy: Binding<Bool> {
		lassoMode ?? Binding(get: { _lassoMode }, set: { _lassoMode = $0 })
	}
	
	// Output
	var onCancel: () -> Void
	var onAccept: (_ drafts: [ControlDraft]) -> Void
	
	var isWideFaceplate: Bool

	var body: some View {
		ZStack {
			NavigationStack {
				Group {
					sidebar
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				}
				.navigationTitle("Review Detections")
				.onAppear {
					guard !ranInitialDetect else { return }
					ranInitialDetect = true
					runDetect()
				}
			}
			
			if isDetecting {
				VStack(spacing: 12) {
					ProgressView().progressViewStyle(.circular)
					Text("Analyzing...").font(.callout).foregroundStyle(.secondary)
				}
				.padding(18)
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
		}
	}
	
	private var sidebar: some View {
			VStack(alignment: .leading, spacing: 14) {
				// Controls row
				if isWideFaceplate {
					HStack(spacing: 12) {
						Text("Sensitivity")
						Slider(value: $sensitivity, in: 0.15...0.95, step: 0.01)
							.help("Higher → more detections (lower threshold).")
						
						//					Toggle("Edges", isOn: $showEdgesPreview)
						//						.toggleStyle(.switch)
						//						.help("Preview detected edges on the image")
						//
						//					Toggle("Rows", isOn: $showBands)
						//						.toggleStyle(.switch)
						//						.help("Show the row bands used for grouping")
						
						Button {
							detectToken &+= 1
							runDetect()
						} label: { Label("Re-Detect", systemImage: "arrow.clockwise") }
							.buttonStyle(.bordered)
							.disabled(isDetecting)
						
						Spacer(minLength: 0)
						
						Toggle("Lasso", isOn: lassoModeProxy)
							.toggleStyle(.checkbox)
							.help("Drag on the faceplate to select by rectangle")
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 26)
				} else {
					VStack(spacing: 12) {
						Text("Sensitivity")
						Slider(value: $sensitivity, in: 0.15...0.95, step: 0.01)
							.help("Higher → more detections (lower threshold).")
						
						// Debug edges
						//					Toggle("Edges", isOn: $showEdgesPreview)
						//						.toggleStyle(.switch)
						//						.help("Preview detected edges on the image")
						//
						//					Toggle("Rows", isOn: $showBands)
						//						.toggleStyle(.switch)
						//						.help("Show the row bands used for grouping")
						HStack {
							Button {
								detectToken &+= 1
								runDetect()
							} label: { Label("Re-Detect", systemImage: "arrow.clockwise") }
								.buttonStyle(.bordered)
								.disabled(isDetecting)
							
							Spacer(minLength: 0)
							
							Toggle("Lasso", isOn: lassoModeProxy)
								.toggleStyle(.checkbox)
								.help("Drag on the faceplate to select by rectangle")
							
							if !selectedIDsProxy.wrappedValue.isEmpty {
								Button(role: .destructive) {
									let ids = selectedIDsProxy.wrappedValue
									drafts.removeAll { ids.contains($0.id) }
									selectedIDsProxy.wrappedValue.removeAll()
									if let cur = selectedIDProxy.wrappedValue, ids.contains(cur) {
										selectedIDProxy.wrappedValue = nil
									}
									listFocusID = nil
								} label: { Label("Delete Selected (\(selectedIDsProxy.wrappedValue.count))", systemImage: "trash") }
							}
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				Divider()
				
				// List of detections
				ScrollView {
					LazyVStack(spacing: 8) {
						ForEach(drafts, id: \.id) { d in
							// stable binding for this row
							let row = binding(for: d.id, fallback: d)
							
							HStack(spacing: 8) {
								// Select checkbox
								Toggle("", isOn: Binding(
									get: { selectedIDsProxy.wrappedValue.contains(d.id) },
									set: { v in
										var cur = selectedIDsProxy.wrappedValue
										if v { cur.insert(d.id) } else { cur.remove(d.id) }
										selectedIDsProxy.wrappedValue = cur
									}
								))
								.toggleStyle(.checkbox)
								
								// Kind tint chip
								Circle()
									.fill(row.wrappedValue.kind.tint)
									.frame(width: 10, height: 10)
								
								// Kind picker
								Picker("", selection: row.kind) {
									ForEach(ControlType.allCases, id: \.self) { k in
										Text(k.displayName).tag(k)
									}
								}
								.labelsHidden()
								.frame(width: 130)
								
								// Label text field (compact width, single line)
								TextField("", text: row.label)
									.textFieldStyle(.roundedBorder)
									.focused($listFocusID, equals: d.id)
									.onChange(of: listFocusID) { _, new in
										focusedDraftID = new
									}
									.frame(minWidth: isWideFaceplate ? 120 : 80, maxWidth: 140)
									.lineLimit(1)
									.truncationMode(.tail)
									.disableAutocorrection(true)
								
								if !isWideFaceplate {
									Spacer(minLength: 0)
								}
								
								Button {
									// delete this row safely
									remove(d.id)
									var cur = selectedIDsProxy.wrappedValue
									cur.remove(d.id)
									selectedIDsProxy.wrappedValue = cur
									if selectedIDProxy.wrappedValue == d.id { selectedIDProxy.wrappedValue = nil }
									if listFocusID == d.id { listFocusID = nil }
								} label: { Image(systemName: "trash") }
									.buttonStyle(.borderless)
									.help("Delete this detected control")
								
								// Confidence
//								Text(String(format: "%.0f%%", row.wrappedValue.confidence*100))
//									.foregroundStyle(.secondary)
//									.frame(width: 48, alignment: .trailing)
							}
							.tag(d.id)
							.padding(.horizontal, 4)
							.frame(maxWidth: .infinity, alignment: .leading)
							.contentShape(Rectangle())
							.onTapGesture {
#if os(macOS)
								if NSEvent.modifierFlags.contains(.command) {
									var cur = selectedIDsProxy.wrappedValue
									if cur.contains(d.id) { cur.remove(d.id) } else { cur.insert(d.id) }
									selectedIDsProxy.wrappedValue = cur
									selectedIDProxy.wrappedValue  = d.id
								} else {
									selectedIDsProxy.wrappedValue = [d.id]
									selectedIDProxy.wrappedValue  = d.id
								}
#else
								selectedIDsProxy.wrappedValue = [d.id]
								selectedIDProxy.wrappedValue  = d.id
#endif
							}
							.contextMenu {
								Button("Delete") {
									remove(d.id)
									var cur = selectedIDsProxy.wrappedValue
									cur.remove(d.id)
									selectedIDsProxy.wrappedValue = cur
									if selectedIDProxy.wrappedValue == d.id { selectedIDProxy.wrappedValue = nil }
									if listFocusID == d.id { listFocusID = nil }
								}
							}
						}
					}
					.padding(.vertical, 4)
				}
				
				Divider()
				
				HStack {
					Button {
						let ids = !selectedIDsProxy.wrappedValue.isEmpty
						? selectedIDsProxy.wrappedValue
						: (selectedIDProxy.wrappedValue.map { Set([$0]) } ?? Set<UUID>())
						
						drafts.removeAll { ids.contains($0.id) }
						selectedIDsProxy.wrappedValue.removeAll()
						if let cur = selectedIDProxy.wrappedValue, ids.contains(cur) {
							selectedIDProxy.wrappedValue = nil
						}
						listFocusID = nil
					} label: { Label("Delete", systemImage: "trash") }
						.disabled(selectedIDsProxy.wrappedValue.isEmpty && selectedIDProxy.wrappedValue == nil)
					if !selectedIDsProxy.wrappedValue.isEmpty {
						Text("\(selectedIDsProxy.wrappedValue.count) selected")
							.font(.caption)
					}
					Spacer()
					
					Button("Cancel") { onCancel() }
					Button("Accept") { onAccept(drafts) }
						.keyboardShortcut(.defaultAction)
						.buttonStyle(.borderedProminent)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.layoutPriority(1)
			.padding()
	}

	private func baseName(for kind: ControlType) -> String {
		switch kind {
			case .knob, .steppedKnob, .concentricKnob: return "Knob"
			case .light: return "Lamp"
			case .button, .litButton: return "Button"
			case .multiSwitch: return "Switch"
		}
	}
	private func displayName(for d: ControlDraft) -> String {
		let base = baseName(for: d.kind)
		let tolY: CGFloat = 16
		let peers = drafts.filter { $0.kind == d.kind }.sorted {
			if abs($0.center.y - $1.center.y) > tolY { return $0.center.y < $1.center.y }
			return $0.center.x < $1.center.x
		}
		if let i = peers.firstIndex(where: { $0.id == d.id }) { return "\(base) \(i+1)" }
		return base
	}
	
	private func index(for id: UUID?) -> Int? {
		guard let id else { return nil }
		return drafts.firstIndex { $0.id == id }
	}
	
	// Create a stable binding to a draft by id, with a safe fallback while rows are disappearing.
	private func binding(for id: UUID, fallback v: ControlDraft) -> Binding<ControlDraft> {
		Binding(
			get: {
				// During deletion SwiftUI can still ask this row to render; fall back to the
				// captured value so we never crash on a nil unwrap.
				drafts.first(where: { $0.id == id }) ?? v
			},
			set: { newValue in
				if let i = drafts.firstIndex(where: { $0.id == id }) {
					drafts[i] = newValue
				}
				// If the row was already removed, just ignore the set.
			}
		)
	}

	private func remove(_ id: UUID) {
		drafts.removeAll { $0.id == id }
		if drafts.isEmpty { selectedIDProxy.wrappedValue = nil }
	}
	
	private func bulkChange(_ k: ControlType) {
		if let id = selectedIDProxy.wrappedValue, let i = index(for: id) {
			drafts[i].kind = k
		} else {
			for i in drafts.indices { drafts[i].kind = k }
		}
	}
	
	private func nudge(dx: CGFloat, dy: CGFloat) {
		guard let i = index(for: selectedIDProxy.wrappedValue) else { return }
		drafts[i].rect = drafts[i].rect.offsetBy(dx: dx, dy: dy)
		drafts[i].center = CGPoint(x: drafts[i].center.x + dx, y: drafts[i].center.y + dy)
	}
	
	private func runDetect() {
		guard !isDetecting else { return }
		isDetecting = true
		detectToken &+= 1
		let token = detectToken
		let nsimg = image
		var cfg = ControlAutoDetect.Config.fromSensitivity(Double(sensitivity))
		cfg.limitSearchToBands = limitToBands
		
		detectTask?.cancel()
		detectTask = Task.detached(priority: .userInitiated) {
			let results = ControlAutoDetect.detect(on: nsimg, config: cfg)
			await MainActor.run {
				if token == detectToken {        // publish only newest
					drafts = results             // NMS already applied
					selectedIDProxy.wrappedValue = drafts.first?.id
				}
				isDetecting = false
			}
		}
	}
}

private extension ControlType {
	var tint: Color {
		switch self {
			case .knob: .green
			case .steppedKnob: .teal
			case .concentricKnob: .mint
			case .button: .blue
			case .litButton: .purple
			case .multiSwitch: .orange
			case .light: .red
		}
	}
}

private enum EdgePreview {
	static func generate(from nsImage: NSImage) -> NSImage? {
		guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
		let ci = CIImage(cgImage: cg)
			.applyingFilter("CIColorControls", parameters: [
				kCIInputSaturationKey: 0.0,
				kCIInputBrightnessKey: 0.0,
				kCIInputContrastKey:   1.05
			])
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
		// A very legible edge stylizer that works well on faceplates:
			.applyingFilter("CILineOverlay", parameters: [
				"inputNRNoiseLevel": 0.01,    // denoise a touch
				"inputNRSharpness": 0.6,
				"inputEdgeIntensity": 1.0,
				"inputThreshold": 0.1,
				"inputContrast": 50.0
			])
		
		let ctx = CIContext()
		guard let out = ctx.createCGImage(ci, from: ci.extent) else { return nil }
		return NSImage(cgImage: out, size: .zero)
	}
}

