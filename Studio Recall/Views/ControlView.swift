//
//  ControlView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct ControlView: View {
    @Binding var control: Control
    
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 40, height: 40)
            .overlay(Text(control.name.prefix(1)).foregroundColor(.white))
            .help(control.name)
    }
}

struct DemoView: View {
    @State private var knobValue: Double = 0.4
    @State private var stepIndex: Int = 2
    @State private var switchIndex: Int = 0
    @State private var buttonOn: Bool = false
    
    var body: some View {
        VStack(spacing: 40) {
            Knob(value: $knobValue, label: "Gain")
            SteppedKnob(index: $stepIndex,
                        steps: 5,
                        label: "Frequency",
                        stepLabels: ["50Hz", "100Hz", "200Hz", "500Hz", "1kHz"])
            MultiSwitch(selectedIndex: $switchIndex,
                        options: ["Mic", "Line", "Inst"],
                        label: "Input")
            GearButton(isPressed: $buttonOn, label: "Bypass")
        }
        .padding()
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}


