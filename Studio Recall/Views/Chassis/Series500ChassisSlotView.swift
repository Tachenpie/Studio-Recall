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
		
		guard let topIndex = indexOfInstance(instance) else {
			return AnyView(EmptyView())
		}
		
		let instanceBinding = Binding<DeviceInstance>(
			get: { slots[topIndex]! },
			set: { newVal in
				let span = topIndex ..< min(topIndex + max(1, units), slots.count)
				for i in span { slots[i] = newVal }
			}
		)
		
		let body = ZStack(alignment: .topLeading) {
			EditableDeviceView(device: .constant(device))
				.frame(width: moduleSize.width, height: moduleSize.height)
				.allowsHitTesting(false)
			
			RuntimeControlsOverlay(device: device, instance: instanceBinding)
				.frame(width: moduleSize.width, height: moduleSize.height)
				.zIndex(1)
		}
			.frame(width: moduleSize.width, height: moduleSize.height)
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.padding(.vertical, 4)
			.onDrag {
				let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
				DragContext.shared.beginDrag(payload: payload)
				if let data = try? JSONEncoder().encode(payload) {
					return NSItemProvider(item: data as NSData,
										  typeIdentifier: UTType.deviceDragPayload.identifier)
				}
				return NSItemProvider()
			} preview: {
				DeviceView(device: device).frame(width: 60, height: 80).shadow(radius: 4)
			}
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(highlightColor(), lineWidth: 3)
					.allowsHitTesting(false)
			)
		
		return AnyView(body)
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
	
	private func indexOfInstance(_ instance: DeviceInstance) -> Int? {
		slots.firstIndex(where: { $0?.id == instance.id })
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
