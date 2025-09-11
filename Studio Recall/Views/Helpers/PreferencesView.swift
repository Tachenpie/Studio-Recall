//
//  PreferencesView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        Form {
            Section(header: Text("Rack Behavior")) {
                Toggle("Enable Size Validation", isOn: $settings.rackValidationEnabled)
                Toggle("Auto-expand Rack", isOn: $settings.rackAutoExpand)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

