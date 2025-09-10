//
//  FaceplatePreview.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct FaceplatePreview: View {
    let device: Device
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let data = device.imageData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit() // preserve proportions
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        placeholder
                    }
                    #else
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit() // preserve proportions
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        placeholder
                    }
                    #endif
                } else {
                    placeholder
                }
            }
        }
    }
    
    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Text("No Image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
