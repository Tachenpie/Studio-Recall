//
//  AppSettings.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("rackValidationEnabled") var rackValidationEnabled: Bool = false
    @AppStorage("rackAutoExpand") var rackAutoExpand: Bool = true
	@AppStorage("useMetalRenderer") var useMetalRenderer: Bool = false
	@Published var parentInteracting: Bool = false
}

extension AppSettings {
    var pointsPerInch: CGFloat { 80 }  // tweak for UI density
}
