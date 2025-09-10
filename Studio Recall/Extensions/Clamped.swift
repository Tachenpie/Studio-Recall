//
//  Clamped.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
