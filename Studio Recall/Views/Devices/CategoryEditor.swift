//
//  CategoryEditor.swift
//  Studio Recall
//
//  Created by True Jackie on 9/3/25.
//
import SwiftUI

struct CategoryEditor: View {
    @ObservedObject var editableDevice: EditableDevice
    @EnvironmentObject var library: DeviceLibrary
    @State private var categoryQuery = ""

    var body: some View {
        Section() {
            VStack(alignment: .leading) {
                TextField("Add or search categories", text: $categoryQuery)
                    .onSubmit {
                        addCategory(categoryQuery)
                        categoryQuery = "change this?"
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                List {
                    ForEach(library.allCategories.filter {
                        categoryQuery.isEmpty ? true: $0.localizedCaseInsensitiveContains(categoryQuery)
                    }, id: \.self) { category in
                        HStack {
							if editableDevice.device.categories.contains(category) {
								Image(systemName: "checkmark")
							}
                            Text(category)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleCategory(category)
                        }
                    }
                }
				.alternatingRowBackgrounds()
				.border(Color.gray)
            }
			.frame(maxWidth: 300, minHeight: 150)
        }
    }

    private func addCategory(_ category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !editableDevice.device.categories.contains(trimmed) {
            editableDevice.device.categories.append(trimmed)
        }
    }
    
    private func toggleCategory(_ category: String) {
        if let idx = editableDevice.device.categories.firstIndex(of: category) {
            editableDevice.device.categories.remove(at: idx)
        } else {
            editableDevice.device.categories.append(category)
        }
    }
}
