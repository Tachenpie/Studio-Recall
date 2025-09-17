//
//  HoverTest.swift
//  Studio Recall
//
//  Created by True Jackie on 9/17/25.
//

import SwiftUI
struct HoverTest: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 200, height: 200)
                    .offset(x: 100, y: 100)
                    .onHover { inside in
                        print("🔵 Hover blue: \(inside)")
                    }
            }
        }
    }
}
