//
//  Session.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

struct Session: Identifiable, Codable {
    var id = UUID()
    var name: String
    var date: Date
    var devices: [Device]
}
