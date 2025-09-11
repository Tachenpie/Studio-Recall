//
//  ControlEditorView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import SwiftUI

struct ControlEditorView: View {
    @Binding var control: Control
    
    var body: some View {
        Form {
            TextField("Name", text: $control.name)
            
            Picker("Type", selection: $control.type) {
                ForEach(ControlType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            
            if control.type == .multiSwitch {
                TextField("Options (comma separated)", text: Binding(
                    get: { control.options?.joined(separator: ", ") ?? "" },
                    set: { control.options = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                ))
            }
        }
        .padding()
    }
}
