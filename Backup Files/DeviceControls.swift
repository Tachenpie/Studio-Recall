//
//  DeviceControls.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

protocol DeviceControl {
    var label: String { get }
}

class SmoothKnob: DeviceControl {
    let label: String
    let minValue: Float
    let maxValue: Float
    private(set) var currentValue: Float
    
    init(label: String, minValue: Float, maxValue: Float, initialValue: Float? = nil) {
        self.label = label
        self.minValue = minValue
        self.maxValue = maxValue
        
        let startingValue = initialValue ?? minValue
        self.currentValue = SmoothKnob.clamp(startingValue, min: minValue, max: maxValue)
    }
    
    // Set the knob's value
    func setValue(_ value: Float) {
        currentValue = SmoothKnob.clamp(value, min: minValue, max: maxValue)
    }
    
    func increment(by step: Float = 1.0) {
        setValue(currentValue + step)
    }
    
    func decrement(by step: Float = 1.0) {
        setValue(currentValue - step)
    }
    
    func getCurrentValue() -> Float {
        return currentValue
    }
    
    private static func clamp(_ value: Float, min: Float, max: Float) -> Float {
        return Swift.max(min, Swift.min(max, value))
    }
}

class SteppedKnob: DeviceControl {
    let label: String
    let steps: [String]
    private(set) var selectedStep: String
    
    init(label: String, steps: [String], defaultStep: String? = nil) {
        self.label = label
        self.steps = steps
        
        if let defaultStep = defaultStep, steps.contains(defaultStep) {
            self.selectedStep = defaultStep
        } else {
            self.selectedStep = steps.first ?? ""
        }
    }
    
    func setStep(_ step: String) {
        if steps.contains(step) {
            selectedStep = step
        }
    }
    
    func nextStep() {
        guard let index = steps.firstIndex(of: selectedStep), index < steps.count - 1 else { return }
        selectedStep = steps[index + 1]
    }
    
    func previousStep() {
        guard let index = steps.firstIndex(of: selectedStep), index > 0 else { return }
        selectedStep = steps[index - 1]
    }
}

class Button: DeviceControl {
    let label: String
    let state1: String
    let state2: String
    private(set) var currentState: String
    
    init(label: String, state1: String, state2: String, initialState: String? = nil) {
        self.label = label
        self.state1 = state1
        self.state2 = state2
        self.currentState = initialState ?? state1
    }
    
    func toggle() {
        currentState = (currentState == state1) ? state2 : state1
    }
    
    func setState(to state: String) {
        if state == state1 || state == state2 {
            currentState = state
        }
    }
    
    func getCurrentState() -> String {
        return currentState
    }
}

class Switch: DeviceControl {
    let label: String
    private var values: [String]
    private(set) var currentValue: String
    
    init(label: String, values: [String], initialValue: String? = nil) {
        self.label = label
        self.values = values
        
        if let initialValue = initialValue, values.contains(initialValue) {
            self.currentValue = initialValue
        } else {
            self.currentValue = values.first ?? ""
        }
    }
    
    func setValue(_ value: String) {
        if values.contains(value) {
            currentValue = value
        }
    }
    
    func getCurrentValue() -> String {
        return currentValue
    }
    
    func nextValue() {
        if let currentIndex = values.firstIndex(of: currentValue) {
            let nextIndex = (currentIndex + 1) % values.count
            currentValue = values[nextIndex]
        }
    }
    
    func previousValue() {
        if let currentIndex = values.firstIndex(of: currentValue) {
            let previousIndex = (currentIndex - 1 + values.count) % values.count
            currentValue = values[previousIndex]
        }
    }
}
