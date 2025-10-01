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
	
	let rackRectsCG: [CGRect]
	let chassisRectsCG: [CGRect]
	
	var rackRects: [RackRect] = []
	let visibleRect: CGRect
	
	private let preload: CGFloat = 120
	
    var body: some View {
        // Precompute locals; avoid heavy inline expressions
//        let racks = session.racks
//        let chassis = session.series500Chassis
		let padded = visibleRect.insetBy(dx: -preload, dy: -preload)
		
		let visibleRacks: [Int] = rackRectsCG.enumerated().compactMap { i, r in
			r.intersects(padded) ? i : nil
		}
		let visibleChassis: [Int] = chassisRectsCG.enumerated().compactMap { i, r in
			r.intersects(padded) ? i : nil
		}
		
		ZStack(alignment: .topLeading) {
            // Racks
//            ForEach(racks.indices, id: \.self) { idx in
			ForEach(visibleRacks, id: \.self) { idx in
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
//            ForEach(chassis.indices, id: \.self) { idx in
			ForEach(visibleChassis, id: \.self) { idx in
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
    }
	
	private func filteredRackIndices(_ rect: CGRect) -> [Int] {
		rackRects.enumerated().compactMap { i, rr in
			rr.frame.intersects(rect) ? i : nil
		}
	}
}
