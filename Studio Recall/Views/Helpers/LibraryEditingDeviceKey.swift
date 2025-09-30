//
//  LibraryEditingDeviceKey.swift
//  Studio Recall
//
//  Created by True Jackie on 9/29/25.
//
import SwiftUI

struct LibraryEditingDeviceKey: PreferenceKey {
	static let defaultValue: Bool = false
	static func reduce(value: inout Bool, nextValue: () -> Bool) {
		value = value || nextValue()
	}
}
