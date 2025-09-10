//
//  Snapped.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import SwiftUI

extension CGFloat {
    func snapped(to step: CGFloat) -> CGFloat {
        (self / step).rounded() * step
    }
}
