//
//  CanvasZoomKey.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//

import SwiftUI

private struct CanvasZoomKey: EnvironmentKey { static let defaultValue: CGFloat = 1.0 }
extension EnvironmentValues {
    var canvasZoom: CGFloat {
        get { self[CanvasZoomKey.self] }
        set { self[CanvasZoomKey.self] = newValue }
    }
}
