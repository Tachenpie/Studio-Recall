//
//  RackChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI
import AppKit

struct RackChassisSlotView: View {
    let index: Int
    let instance: DeviceInstance?
    @Binding var slots: [DeviceInstance?]
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    @Binding var hoveredIndex: Int?
    @Binding var hoveredRange: Range<Int>?
    @Binding var hoveredValid: Bool
	
	@State private var railHover = false

    var body: some View {
        Group {
            if let instance, let device = library.device(for: instance.deviceID) {
                deviceView(device, instance: instance)
            } else {
                emptySlotView()
            }
        }
    }

	private func deviceView(_ device: Device, instance: DeviceInstance) -> some View {
		let units = device.rackUnits ?? 1
		let rackSize = DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch)
		let topIndex = indexOfInstance(instance)
		
		return ZStack(alignment: .topLeading) {
			DeviceView(device: device)
				.frame(width: rackSize.width, height: rackSize.height)
				.overlay(
					RoundedRectangle(cornerRadius: 6)
						.stroke(highlightColor(forTopIndex: topIndex), lineWidth: 3)
				)
			// NOTE: no `.onDrop` here — occupied slots should not accept drops
		}
		.frame(width: rackSize.width, height: rackSize.height) // needed for overlay placement
		
		// LEFT rail
		.overlay(alignment: .leading) {
			RailV()
				.frame(height: rackSize.height)
				.contentShape(Rectangle())
				.opacity(railHover ? 1 : 0.35)
				.onHover { inside in
					railHover = inside
					if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
				}
				.onDrag { deviceDragProvider(instance: instance, device: device) }
				.contextMenu {
					Button(role: .destructive) {
						removeInstance(instance, of: device)
					} label: {
						Label("Remove from Rack", systemImage: "trash")
					}
				}

				.padding(.leading, 2)
		}
		
		// RIGHT rail
		.overlay(alignment: .trailing) {
			RailV()
				.frame(height: rackSize.height)
				.contentShape(Rectangle())
				.opacity(railHover ? 1 : 0.35)
				.onHover { inside in
					railHover = inside
					if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
				}
				.onDrag { deviceDragProvider(instance: instance, device: device) }
				.contextMenu {
					Button(role: .destructive) {
						removeInstance(instance, of: device)
					} label: {
						Label("Remove from Rack", systemImage: "trash")
					}
				}

				.padding(.trailing, 2)
		}
	}


	private func emptySlotView(units: Int = 1) -> some View {
		let rackSize = DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch)
		
		return Rectangle()
			.fill(Color.white.opacity(0.03))   // must be in hit-test tree
			.frame(width: rackSize.width, height: rackSize.height)
			.contentShape(Rectangle())
			.overlay(
				Rectangle()
					.stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4]))
			)
			.onDrop(
				of: [UTType.deviceDragPayload],
				delegate: ChassisDropDelegate(
					currentIndex: index,
					slots: $slots,
					hoveredIndex: $hoveredIndex,
					hoveredValid: $hoveredValid,
					hoveredRange: $hoveredRange,
					library: library,
					measure: { $0.rackUnits ?? 1 },
					kind: .rack
				)
			)
	}

    private func indexOfInstance(_ instance: DeviceInstance) -> Int? {
        slots.firstIndex(where: { $0?.id == instance.id })
    }

	private func removeInstance(_ instance: DeviceInstance, of device: Device) {
		guard let start = indexOfInstance(instance) else { return }
		let count = max(1, device.rackUnits ?? 1)
		let end = min(start + count, slots.count)
		for i in start..<end { slots[i] = nil }
	}

    private func highlightColor(forTopIndex topIndex: Int?) -> Color {
        if let range = hoveredRange, range.contains(index) {
            return hoveredValid ? .green : .red
        }
        return .clear
    }
	
	private func deviceDragProvider(instance: DeviceInstance, device: Device) -> NSItemProvider {
		let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
		DragContext.shared.beginDrag(payload: payload)
		let provider = NSItemProvider()
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.deviceDragPayload.identifier,
			visibility: .all
		) { completion in
			completion(try? JSONEncoder().encode(payload), nil)
			return nil
		}
		return provider
	}
	
	private struct RailV: View {
		var body: some View {
			RoundedRectangle(cornerRadius: 3)
				.fill(.ultraThinMaterial)
				.overlay(
					RoundedRectangle(cornerRadius: 3)
						.stroke(.secondary.opacity(0.35), lineWidth: 1)
				)
				.frame(width: 12)
				.opacity(0.9)
				.help("Drag to move this device")
				.overlay( // screw dots
					RailScrewsV()
				)
		}
	}
	
	private struct RailScrewsV: View {
		var body: some View {
			VStack(spacing: 8) {
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
			}
			.padding(.vertical, 6)
		}
	}
}

