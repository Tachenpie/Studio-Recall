//
//  DragContext.swift
//  Studio Recall
//
//  Created by True Jackie on 9/3/25.
//

import Foundation

@MainActor
final class DragContext: ObservableObject {
    static let shared = DragContext()
    private init() {}

    /// The payload of the item currently being dragged (if any).
    @Published var currentPayload: DragPayload? = nil

    /// Call this in `.onDrag {}` when starting a drag.
    func beginDrag(payload: DragPayload) {
        currentPayload = payload
    }

    /// Clear after drop finishes or cancels.
    func endDrag() {
        currentPayload = nil
    }
}
