//
//  Series500ChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI
import AppKit

struct Series500ChassisSlotView: View {
    let index: Int
    let instance: DeviceInstance?
    @Binding var slots: [DeviceInstance?]
    
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    @Binding var hoveredIndex: Int?
    @Binding var hoveredRange: Range<Int>?
    @Binding var hoveredValid: Bool
	
	@State private var slotHover = false

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
		let units = device.slotWidth ?? 1
		let moduleSize = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)
		
		return ZStack(alignment: .topLeading) {
			EditableDeviceView(device: .constant(device))
				.frame(width: moduleSize.width, height: moduleSize.height)
				.padding(.vertical, 4)
				.overlay(
					RoundedRectangle(cornerRadius: 6)
						.stroke(highlightColor(), lineWidth: 3)
				)
			// NOTE: no `.onDrop` here — occupied slots should not accept drops
		}
		// include the vertical padding in the container height so top/bottom overlays align
		.frame(width: moduleSize.width, height: moduleSize.height + 8)
		
		// TOP rail
		.overlay(alignment: .top) {
			RailH()
				.frame(width: moduleSize.width)
				.contentShape(Rectangle())
				.opacity(slotHover ? 1 : 0.35)
				.onHover { inside in
					slotHover = inside
					if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
				}
				.onDrag { deviceDragProvider(instance: instance, device: device) }
				.contextMenu {
					Button(role: .destructive) {
						removeInstance(instance, of: device)
					} label: {
						Label("Remove from Chassis", systemImage: "trash")
					}
				}
				.padding(.top, 1)
		}
		
		// BOTTOM rail
		.overlay(alignment: .bottom) {
			RailH()
				.frame(width: moduleSize.width)
				.contentShape(Rectangle())
				.opacity(slotHover ? 1 : 0.35)
				.onHover { inside in
					slotHover = inside
					if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
				}
				.onDrag { deviceDragProvider(instance: instance, device: device) }
				.contextMenu {
					Button(role: .destructive) {
						removeInstance(instance, of: device)
					} label: {
						Label("Remove from Chassis", systemImage: "trash")
					}
				}
				.padding(.bottom, 1)
		}
	}

	private func emptySlotView(units: Int = 1) -> some View {
		let moduleSize = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)
		
		return Rectangle()
		// tiny alpha keeps it in the hit-testing tree but is visually identical
			.fill(Color.white.opacity(0.03))
			.frame(width: moduleSize.width, height: moduleSize.height)
			.overlay(
				Rectangle()
					.stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
			)
			.contentShape(Rectangle()) // <- important for drops
			.onDrop(
				of: [UTType.deviceDragPayload],
				delegate: ChassisDropDelegate(
					currentIndex: index,
					slots: $slots,
					hoveredIndex: $hoveredIndex,
					hoveredValid: $hoveredValid,
					hoveredRange: $hoveredRange,
					library: library,
					measure: { $0.slotWidth ?? 1 },
					kind: .series500
				)
			)
	}

    private func highlightColor() -> Color {
        if let range = hoveredRange, range.contains(index) {
            return hoveredValid ? .green : .red
        }
        return .clear
    }

	private func removeInstance(_ instance: DeviceInstance, of device: Device) {
		guard let start = slots.firstIndex(where: { $0?.id == instance.id }) else { return }
		let count = max(1, device.slotWidth ?? 1)
		let end = min(start + count, slots.count)
		for i in start..<end { slots[i] = nil }
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
	
	private struct RailH: View {
		var body: some View {
			RoundedRectangle(cornerRadius: 3)
				.fill(.ultraThinMaterial)
				.overlay(
					RoundedRectangle(cornerRadius: 3)
						.stroke(.secondary.opacity(0.35), lineWidth: 1)
				)
				.frame(height: 6)
				.opacity(0.9)
				.help("Drag to move this module")
				.overlay( // screw dots
					RailScrewsH()
				)
		}
	}
	
	private struct RailScrewsH: View {
		var body: some View {
			HStack(spacing: 10) {
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
				Circle().fill(.secondary).frame(width: 3.5, height: 3.5)
			}
			.padding(.horizontal, 6)
		}
	}
}
