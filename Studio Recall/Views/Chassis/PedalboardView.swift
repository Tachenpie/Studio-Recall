//
//  PedalboardView.swift
//  Studio Recall
//
//  View for pedalboard with free-form pedal placement
//

import SwiftUI
import UniformTypeIdentifiers

struct PedalboardView: View {
	@Binding var pedalboard: Pedalboard
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var sessionManager: SessionManager

	@Environment(\.canvasZoom) private var canvasZoom
	@Environment(\.isInteracting) private var isInteracting
	@Environment(\.collisionRects) private var collisionRects

	@ObservedObject private var dragContext = DragContext.shared

	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editWidth: Double = 24
	@State private var editHeight: Double = 12
	@State private var editName: String = ""
	@State private var draggingPedal: UUID? = nil  // Track which pedal is being repositioned

	var onDelete: (() -> Void)? = nil

	private let boardPadding: CGFloat = 16
	private let dragStripHeight: CGFloat = 32

	var body: some View {
		let ppi = settings.pointsPerInch
		let boardWidthPts = CGFloat(pedalboard.widthInches) * ppi
		let boardHeightPts = CGFloat(pedalboard.heightInches) * ppi
		let faceW = boardWidthPts + boardPadding * 2
		let faceH = boardHeightPts + boardPadding * 2
		let totalHeight = dragStripHeight + faceH

		VStack(spacing: 0) {
			// Drag strip for moving the entire pedalboard
			DragStrip(
				title: (pedalboard.name?.isEmpty == false ? pedalboard.name : "Pedalboard"),
				onBegan: { if dragStart == nil { dragStart = pedalboard.position } },
				onDrag: { screenDelta, _ in
					let origin = dragStart ?? pedalboard.position
					let z = max(canvasZoom, 0.0001)
					let worldDelta = CGSize(width: screenDelta.width / z,
											height: screenDelta.height / z)
					pedalboard.position = CGPoint(x: origin.x + worldDelta.width,
												  y: origin.y + worldDelta.height)
				},
				onEnded: { dragStart = nil },
				onEditRequested: {
					editWidth = pedalboard.widthInches
					editHeight = pedalboard.heightInches
					editName = pedalboard.name ?? ""
					showEdit = true
				},
				onClearRequested: { pedalboard.pedals.removeAll() },
				onDeleteRequested: { onDelete?() },
				newLabelAnchor: .pedalboard(pedalboard.id),
				defaultLabelOffset: CGPoint(x: 32, y: 28)
			)
			.frame(width: faceW)
			.zIndex(2)

			// Pedalboard surface
			ZStack(alignment: .topLeading) {
				// Background
				Rectangle()
					.fill(Color.gray.opacity(0.3))
					.overlay(
						// Grid lines to show inches
						GeometryReader { geo in
							Path { path in
								// Vertical lines every inch
								for i in 1..<Int(pedalboard.widthInches) {
									let x = boardPadding + CGFloat(i) * ppi
									path.move(to: CGPoint(x: x, y: boardPadding))
									path.addLine(to: CGPoint(x: x, y: boardPadding + boardHeightPts))
								}
								// Horizontal lines every inch
								for i in 1..<Int(pedalboard.heightInches) {
									let y = boardPadding + CGFloat(i) * ppi
									path.move(to: CGPoint(x: boardPadding, y: y))
									path.addLine(to: CGPoint(x: boardPadding + boardWidthPts, y: y))
								}
							}
							.stroke(Color.white.opacity(0.1), lineWidth: 1)
						}
					)

				// Render pedals
				ForEach(pedalboard.pedals.indices, id: \.self) { idx in
					let pedal = pedalboard.pedals[idx].instance
					if let device = library.device(for: pedal.deviceID) {
						PedalView(
							placement: $pedalboard.pedals[idx],
							device: device,
							pedalboard: pedalboard,
							isDragging: draggingPedal == pedalboard.pedals[idx].id,
							onDragBegan: { draggingPedal = pedalboard.pedals[idx].id },
							onDragEnded: { draggingPedal = nil }
						)
					}
				}

				// Labels
				if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
					let session = $sessionManager.sessions[i]
					LabelCanvas(
						labels: session.labels,
						anchor: .pedalboard(pedalboard.id),
						parentOrigin: CGPoint(x: boardPadding, y: boardPadding)
					)
					.allowsHitTesting(true)
				}
			}
			.frame(width: faceW, height: faceH)
			.background(Color.black.opacity(0.8))
			.cornerRadius(8)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.85), lineWidth: 1))
			.zIndex(1)
		}
		.sheet(isPresented: $showEdit) { editSheet }
	}

	// MARK: - Edit Sheet
	@ViewBuilder
	private var editSheet: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit Pedalboard").font(.headline)

			TextField("Pedalboard Name (optional)", text: $editName)
				.textFieldStyle(.roundedBorder)

			HStack {
				Text("Width (inches):")
				TextField("Width", value: $editWidth, format: .number)
					.textFieldStyle(.roundedBorder)
					.frame(width: 60)
				Stepper("", value: $editWidth, in: 12...48, step: 1)
			}

			HStack {
				Text("Height (inches):")
				TextField("Height", value: $editHeight, format: .number)
					.textFieldStyle(.roundedBorder)
					.frame(width: 60)
				Stepper("", value: $editHeight, in: 8...24, step: 1)
			}

			HStack {
				Spacer()
				Button("Cancel") {
					showEdit = false
				}
				Button("Save") {
					let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
					pedalboard.name = trimmedName.isEmpty ? nil : trimmedName
					pedalboard.widthInches = editWidth
					pedalboard.heightInches = editHeight
					sessionManager.saveSessions()
					showEdit = false
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 320)
	}
}

/// View for an individual pedal on the pedalboard
struct PedalView: View {
	@Binding var placement: PedalPlacement
	let device: Device
	let pedalboard: Pedalboard
	let isDragging: Bool
	let onDragBegan: () -> Void
	let onDragEnded: () -> Void

	@EnvironmentObject var settings: AppSettings
	@Environment(\.canvasZoom) private var canvasZoom

	@State private var dragStartPosition: CGPoint? = nil

	var body: some View {
		let ppi = settings.pointsPerInch
		let pedalWidthPts = CGFloat(device.pedalWidthInches ?? 3.0) * ppi
		let pedalHeightPts = CGFloat(device.pedalHeightInches ?? 5.0) * ppi

		// Convert pedal position (in inches) to points, relative to board top-left
		let boardPadding: CGFloat = 16
		let posX = boardPadding + CGFloat(placement.position.x) * ppi
		let posY = boardPadding + CGFloat(placement.position.y) * ppi

		ZStack {
			// Pedal faceplate
			if let imageData = device.imageData, let nsImage = NSImage(data: imageData) {
				Image(nsImage: nsImage)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: pedalWidthPts, height: pedalHeightPts)
			} else {
				// Placeholder if no image
				Rectangle()
					.fill(Color.gray.opacity(0.5))
					.frame(width: pedalWidthPts, height: pedalHeightPts)
					.overlay(
						Text(device.name)
							.font(.system(size: 10))
							.foregroundColor(.white)
					)
			}
		}
		.position(x: posX + pedalWidthPts / 2, y: posY + pedalHeightPts / 2)
		.opacity(isDragging ? 0.7 : 1.0)
		.gesture(
			DragGesture(coordinateSpace: .named("pedalboard"))
				.onChanged { value in
					if dragStartPosition == nil {
						dragStartPosition = placement.position
						onDragBegan()
					}

					// Convert screen delta to inches
					let z = max(canvasZoom, 0.0001)
					let deltaInches = CGPoint(
						x: value.translation.width / (z * ppi),
						y: value.translation.height / (z * ppi)
					)

					var newPos = CGPoint(
						x: (dragStartPosition?.x ?? 0) + deltaInches.x,
						y: (dragStartPosition?.y ?? 0) + deltaInches.y
					)

					// Light snapping to inch grid
					let snapThreshold: Double = 0.25  // Snap within 0.25"
					newPos.x = snapToGrid(newPos.x, threshold: snapThreshold)
					newPos.y = snapToGrid(newPos.y, threshold: snapThreshold)

					// Constrain to board bounds
					let maxX = pedalboard.widthInches - (device.pedalWidthInches ?? 3.0)
					let maxY = pedalboard.heightInches - (device.pedalHeightInches ?? 5.0)
					newPos.x = max(0, min(maxX, newPos.x))
					newPos.y = max(0, min(maxY, newPos.y))

					placement.position = newPos
				}
				.onEnded { _ in
					dragStartPosition = nil
					onDragEnded()
				}
		)
	}

	/// Snap to nearest inch grid if within threshold
	private func snapToGrid(_ value: Double, threshold: Double) -> Double {
		let rounded = round(value)
		if abs(value - rounded) < threshold {
			return rounded
		}
		return value
	}
}
