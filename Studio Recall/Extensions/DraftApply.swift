//
//  DraftApply.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//

import Foundation
import AppKit
import SwiftUI

extension Array where Element == ControlDraft {
	func makeControlsForDevice(imageSize: CGSize) -> [Control] {
		func norm(_ r: CGRect) -> CGRect {
			CGRect(x: r.minX / imageSize.width,
				   y: r.minY / imageSize.height,
				   width:  r.width / imageSize.width,
				   height: r.height / imageSize.height)
		}
		
		return self.map { d in
			// Guess ControlType from draft kind
			let type: ControlType = {
				switch d.kind {
					case .knob:            return .knob
					case .steppedKnob:     return .steppedKnob
					case .multiSwitch:     return .multiSwitch
					case .button:          return .button
					case .light:           return .light
					case .litButton:       return .litButton
					case .concentricKnob:  return .concentricKnob
				}
			}()
			
			// Initial center (normalized) for Control.x/y; region is the visual patch
			let cx = d.center.x / imageSize.width
			let cy = d.center.y / imageSize.height
			
			var control = Control(
				name: d.label,
				type: type,
				x: cx, y: cy
			)
			
			// Make one circular or rectangular region from the rect guess
			let region = ImageRegion(
				rect: norm(d.rect),
				mapping: nil,
				shape: (d.radius != nil ? .circle : .rect)
			)
			control.regions = [region]
			return control
		}
	}
}
