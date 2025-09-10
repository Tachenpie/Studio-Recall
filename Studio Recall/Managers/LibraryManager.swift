//
//  LibraryManager.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct LibraryCommands: Commands {
    @Binding var showingLibraryEditor: Bool
    
    var body: some Commands {
        CommandMenu("Library") {
            Button("Edit Library…") { showingLibraryEditor = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
