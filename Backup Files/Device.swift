//
//  Device.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import Foundation

class Device {
    enum DeviceType {
        case rack
        case series500
    }
    
    let name: String
    let type: DeviceType
    private(set) var controls: [DeviceControl]
    
    init(name: String, type: DeviceType) {
        self.name = name
        self.type = type
        self.controls = []
    }
    
    func addControl(_ control: DeviceControl) {
        controls.append(control)
    }
    
    func getControl(named controlName: String) -> DeviceControl? {
        return controls.first { $0.label == controlName }
    }
    
    func getControl<T: DeviceControl>(named controlName: String, as type: T.Type) -> T? {
        return controls.first { $0.label == controlName } as? T
    }
}
