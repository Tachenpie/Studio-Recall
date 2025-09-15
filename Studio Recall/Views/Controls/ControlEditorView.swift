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
			// Shape selector (Circle vs Rectangle)
			Picker("Shape", selection: Binding(
				get: { control.region?.shape ?? .circle },
				set: { newShape in
					if control.region == nil {
						// Create a default region if one doesn't exist yet
						control.region = ImageRegion(
							rect: .init(x: 0, y: 0, width: ImageRegion.defaultSize, height: ImageRegion.defaultSize),
							mapping: nil,
							shape: newShape
						)
					} else {
						control.region?.shape = newShape
					}
				}
			)) {
				Text("Circle").tag(ImageRegionShape.circle)
				Text("Rectangle").tag(ImageRegionShape.rect)
			}
			.pickerStyle(SegmentedPickerStyle())

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
