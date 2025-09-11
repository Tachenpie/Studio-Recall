//
//  DeviceInstance.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//

import Foundation

/// Represents a physical unit of a device placed in a rack/chassis.
/// References a `Device` from the library, but has its own unique ID.
struct DeviceInstance: Identifiable, Codable, Equatable {
	let id: UUID         // unique per instance
	let deviceID: UUID   // points to the library Device
	
	// NEW: Stores current values for each control in the device
	var controlStates: [UUID: ControlValue] = [:]
	
	init(deviceID: UUID, device: Device? = nil) {
		self.id = UUID()
		self.deviceID = deviceID
		
		// initialize defaults from the device definition
		if let d = device {
			self.controlStates = Dictionary(uniqueKeysWithValues:
												d.controls.map { ($0.id, ControlValue.initialValue(for: $0)) }
			)
		}
	}
}

// Represent the value for any control type
enum ControlValue: Codable, Equatable, CustomStringConvertible {
	case knob(Double)
	case steppedKnob(Int)
	case multiSwitch(Int)
	case button(Bool)
	case light(Bool)
	case concentricKnob(outer: Double, inner: Double)
	case litButton(isPressed: Bool, isLit: Bool)
	
	static func initialValue(for control: Control) -> ControlValue {
		switch control.type {
			case .knob:           return .knob(0.0)
			case .steppedKnob:    return .steppedKnob(0)
			case .multiSwitch:    return .multiSwitch(0)
			case .button:         return .button(false)
			case .light:          return .light(false)
			case .concentricKnob: return .concentricKnob(outer: 0.0, inner: 0.0)
			case .litButton:      return .litButton(isPressed: false, isLit: false)
		}
	}
	
	// MARK: - Readable display for UI & logs
	var description: String {
		switch self {
			case .knob(let v):
				return String(format: "Knob %.2f", v)
			case .steppedKnob(let step):
				return "Stepped \(step)"
			case .multiSwitch(let pos):
				return "Switch pos \(pos)"
			case .button(let pressed):
				return pressed ? "Button ON" : "Button OFF"
			case .light(let lit):
				return lit ? "Light ON" : "Light OFF"
			case .concentricKnob(let outer, let inner):
				return String(format: "Concentric outer %.2f / inner %.2f", outer, inner)
			case .litButton(let pressed, let lit):
				return "LitButton [pressed: \(pressed ? "ON" : "OFF"), light: \(lit ? "ON" : "OFF")]"
		}
	}
}

struct ControlDiff {
	var controlID: UUID
	var name: String
	var before: ControlValue
	var after: ControlValue
}

extension DeviceInstance {
	/// Compare this instance's stored control values against the library device defaults.
	func diffs(vs libraryDevice: Device) -> [ControlDiff] {
		libraryDevice.controls.compactMap { def in
			guard let stored = controlStates[def.id] else { return nil }
			let defaultValue = ControlValue.initialValue(for: def)
			
			return stored != defaultValue
			? ControlDiff(
				controlID: def.id,
				name: def.name.isEmpty ? def.type.rawValue.capitalized : def.name,
				before: defaultValue,
				after: stored
			)
			: nil
		}
	}
}
