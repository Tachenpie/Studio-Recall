//
//  SessionCanvasLayer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SessionCanvasLayer: View {
    @Binding var session: Session
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
	let canvasSize: CGSize
	
	var rackRects: [RackRect] = []
	
    var body: some View {
        // Precompute locals; avoid heavy inline expressions
        let racks = session.racks
        let chassis = session.series500Chassis

		ZStack(alignment: .topLeading) {
            // Racks
            ForEach(racks.indices, id: \.self) { idx in
				RackChassisView(
					rack: $session.racks[idx],
					onDelete: {
						let id = session.racks[idx].id
						session.racks.removeAll { $0.id == id }
					}
				)
                .position(session.racks[idx].position)
            }

            // Series 500 chassis
            ForEach(chassis.indices, id: \.self) { idx in
				Series500ChassisView(
					chassis: $session.series500Chassis[idx],
					onDelete: {
						let id = session.series500Chassis[idx].id
						session.series500Chassis.removeAll { $0.id == id }
					}
				)
                .position(session.series500Chassis[idx].position)
            }
			
			// Labels
			LabelCanvas(
				labels: $session.labels,
				anchor: .session,
				parentOrigin: .zero,
				rackRects: rackRects
			)
        }
//#if os(macOS)
//		.overlay(
//			DropCatcher(
//				name: "ROOT-CANVAS",
//				types: [UTType.deviceDragPayload, .item, .data, .utf8PlainText],
//				onEnter: { loc, types in
//					print("🧲[ROOT-CANVAS] ENTER @\(loc) types=\(types)")
//				},
//				onUpdate: { loc in
//					print("🧲[ROOT-CANVAS] UPDATE @\(loc)")
//				},
//				onExit: {
//					print("🧲[ROOT-CANVAS] EXIT")
//				},
//				onDrop: { pb, loc in
//					print("🧲[ROOT-CANVAS] DROP types=\(pb.types?.map(\.rawValue) ?? []) @\(loc)")
//				},
//				debugTint: true  // temporarily paint a faint pink so you *see* it covers the layer
//			)
//		)
//#endif

    }
}
