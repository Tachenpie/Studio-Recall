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
	
	@Binding var selectedCategories: Set<String>
    
	@State private var categoryQuery = ""

	@Environment(\.dismiss) private var dismiss
	
	private var visibleCategories: [String] {
		let source = library.allCategories.isEmpty
		? Array(library.categories).sorted()
		: library.allCategories
		
		let filtered = categoryQuery.isEmpty
		? source
		: source.filter { $0.localizedCaseInsensitiveContains(categoryQuery) }
		return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}
	
//	init() {
//		self.selectedCategories = Set(editableDevice.device.categories)
//	}
	
    var body: some View {
		VStack(alignment: .leading, spacing: 10) {
				VStack {
					TextField("Add or search categories", text: $categoryQuery)
						.onSubmit {
							addCategory(categoryQuery)
							categoryQuery = ""
						}
						.textFieldStyle(RoundedBorderTextFieldStyle())
					HStack {
						Button("Add") {
							addCategory(categoryQuery)
							categoryQuery = ""
						}
						.disabled(categoryQuery.isEmpty)
						
						Button("Clear") {
							categoryQuery = ""
						}
						.disabled(categoryQuery.isEmpty)
					}
				}
				
//                List {
//                    ForEach(library.allCategories.filter {
//                        categoryQuery.isEmpty ? true: $0.localizedCaseInsensitiveContains(categoryQuery)
//                    }, id: \.self) { category in
//                        HStack {
//							if editableDevice.device.categories.contains(category) {
//								Image(systemName: "checkmark")
//							}
//                            Text(category)
//                        }
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            toggleCategory(category)
//                        }
//                    }
//                }
				List(visibleCategories, id: \.self, selection: $selectedCategories) { category in
						Text(category)
						.lineLimit(1)
						.truncationMode(.tail)
						.tag(category)
				}
				.listStyle(.inset)
				.frame(minHeight: 180)
				.alternatingRowBackgrounds()
				.border(Color.gray)
				.environment(\.defaultMinListRowHeight, 22)
				.scrollContentBackground(.visible)
            }
			.frame(maxWidth: 300, minHeight: 150)
		.onAppear {
			selectedCategories = Set(editableDevice.device.categories)
		}
		.onChange(of: editableDevice.device.categories) { _, newCategories in
			selectedCategories = Set(newCategories)
		}
    }

    private func addCategory(_ category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
		selectedCategories.insert(trimmed)
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
