//
//  Rack.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import Foundation

struct Rack: Identifiable, Codable {
	var id: UUID = UUID()
	var name: String?
	var rows: Int                           // number of U (rows of cells)
	var slots: [[DeviceInstance?]]          // rows × 6 columns grid
	var position: CGPoint = .zero
	
	init(name: String, rows: Int) {
		self.name = name
		self.rows = max(1, rows)
		self.slots = Array(
			repeating: Array<DeviceInstance?>(repeating: nil, count: RackGrid.columnsPerRow),
			count: self.rows
		)
	}
	
	init(rows: Int) {
		self.rows = max(1, rows)
		self.slots = Array(
			repeating: Array<DeviceInstance?>(repeating: nil, count: RackGrid.columnsPerRow),
			count: self.rows
		)
	}
}
