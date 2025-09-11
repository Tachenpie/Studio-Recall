//
//  SessionCanvasLayer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//
import SwiftUI

@MainActor
struct SessionCanvasLayer: View {
    @Binding var session: Session
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    let canvasSize: CGSize

    var body: some View {
        // Precompute locals; avoid heavy inline expressions
        let racks = session.racks
        let chassis = session.series500Chassis

        ZStack {
            // Racks
            ForEach(racks.indices, id: \.self) { idx in
				RackChassisView(rack: $session.racks[idx])
                .position(session.racks[idx].position)
            }

            // Series 500 chassis
            ForEach(chassis.indices, id: \.self) { idx in
				Series500ChassisView(chassis: $session.series500Chassis[idx])
                .position(session.series500Chassis[idx].position)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
