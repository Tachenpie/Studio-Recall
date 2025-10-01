//
//  DeviceView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct DeviceView: View {
    let device: Device
	var isThumbnail: Bool = false
	var metrics: FaceRenderMetrics? = nil
	
	@Environment(\.displayScale) private var displayScale
	@Environment(\.renderStyle)  private var renderStyle
	
	var body: some View {
		Group {
			if let m = metrics {
				let w = (m.size.width  * displayScale).rounded() / displayScale
				let h = (m.size.height * displayScale).rounded() / displayScale
				
				ZStack(alignment: .topLeading) {
					if renderStyle == .photoreal {
						if let data = device.imageData, let nsImage = NSImage(data: data) {
							Image(nsImage: nsImage)
								.resizable()
								.interpolation(.high)
								.antialiased(true)
								.frame(width: w, height: h)
								.allowsHitTesting(false)
								.clipped()
						} else {
							drawnDevice
								.frame(width: w, height: h)
						}
					} else {
						RepresentativeFaceplate(device: device, size: CGSize(width: w, height: h))
							.allowsHitTesting(false)
					}
				}
			} else {
				GeometryReader { geo in
					// Compute the same fit metrics the overlay will use
					let fm = DeviceMetrics.faceRenderMetrics(
						faceWidthPts: geo.size.width,
						slotHeightPts: geo.size.height,
						imageData: device.imageData
					)
					ZStack(alignment: .topLeading) {
						if renderStyle == .photoreal {
							if let data = device.imageData,
							   let nsImage = NSImage(data: data) {
								// Render the face at the exact fitted size, then letterbox vertically
								Image(nsImage: nsImage)
									.resizable()
									.interpolation(.high)
									.antialiased(true)
									.aspectRatio(nsImage.size, contentMode: .fit)
									.frame(width: fm.size.width, height: fm.size.height)
									.offset(y: fm.vOffset)
									.allowsHitTesting(false)
							} else {
								drawnDevice
									.frame(width: fm.size.width, height: fm.size.height)
									.offset(y: fm.vOffset)
							}
						} else {
							RepresentativeFaceplate(device: device, size: CGSize(width: fm.size.width, height: fm.size.height))
						}
					}
					.frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
				}
			}
		}
		.background(deviceBackground)
//		.modifier(_DeviceViewSizer(isThumbnail: isThumbnail))
		.modifier(_DeviceViewSizer(shouldFill: metrics == nil && !isThumbnail))
	}
    
    private var drawnDevice: some View {
        VStack(spacing: 16) {
            if device.isFiller {
                Spacer()
            } else {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 20) {
                    ForEach(device.controls) { control in
                        ControlView(control: .constant(control))
                    }
                }
            }
        }
        .background(deviceBackground)
        .cornerRadius(4)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deviceBackground: some View {
        if device.isFiller {
            return AnyView(Color.black.opacity(0.3))
        }
        
        switch device.type {
        case .rack:
            return AnyView(
                LinearGradient(colors: [.gray.opacity(0.9), .black],
                               startPoint: .top,
                               endPoint: .bottom)
            )
        case .series500:
            return AnyView(
                LinearGradient(colors: [.black, .gray.opacity(0.6)],
                               startPoint: .leading,
                               endPoint: .trailing)
            )
        @unknown default:
            return AnyView(Color.gray)
        }
    }
}

struct EditableDeviceView: View {
    @Binding var device: Device
    @State private var editorModel: EditableDevice? = nil   // for sheet

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Faceplate image or gradient fallback
                if let data = device.imageData {
                    #if os(macOS)
                    if let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                    #else
                    if let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                    #endif
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [.black, .gray],
                                             startPoint: .top,
                                             endPoint: .bottom))
                        .cornerRadius(8)
                }

                // Draggable controls
                ForEach($device.controls, id: \.id) { $control in
                    ControlView(control: $control)
                        .position(x: control.x * geo.size.width,
                                  y: control.y * geo.size.height)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    control.x = min(max(0, value.location.x / geo.size.width), 1)
                                    control.y = min(max(0, value.location.y / geo.size.height), 1)
                                }
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // open full editor with a class-wrapped copy
                editorModel = EditableDevice(device: device)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers, location in
                if let provider = providers.first {
                    provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                        if let data = item as? Data,
                           let typeString = String(data: data, encoding: .utf8),
                           let type = ControlType(rawValue: typeString) {

                            let new = Control(
                                name: type.rawValue,
                                type: type,
                                x: location.x / geo.size.width,
                                y: location.y / geo.size.height
                            )
                            DispatchQueue.main.async {
                                device.controls.append(new)
                            }
                        }
                    }
                    return true
                }
                return false
            }
        }
        // Present the full editor
        .sheet(item: $editorModel) { editable in
            DeviceEditorView(
                        editableDevice: editable,
                        onCommit: { updated in
                            editorModel = nil
                        },
                        onCancel: {
                            editorModel = nil
                        }
                    )
        }
    }
}

//private struct _DeviceViewSizer: ViewModifier {
//	let isThumbnail: Bool
//	func body(content: Content) -> some View {
//		if isThumbnail {
//			content.clipped()               // respect outer frame
//		} else {
//			content
//				.frame(maxWidth: .infinity, maxHeight: .infinity)
//		}
//	}
//}

private struct _DeviceViewSizer: ViewModifier {
	let shouldFill: Bool
	func body(content: Content) -> some View {
		if shouldFill {
			// editor/thumbnail paths that should fill their container
			content.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			// runtime path (metrics provided): respect the exact frame we were given
			content.clipped()
		}
	}
}
