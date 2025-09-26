//
//  SessionTemplate.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


// SessionTemplate.swift
import Foundation

struct SessionTemplate: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var session: Session  // a skeleton Session (no recordings, usually no control state)
	
	static func == (lhs: SessionTemplate, rhs: SessionTemplate) -> Bool {
		lhs.id == rhs.id
	}
}
