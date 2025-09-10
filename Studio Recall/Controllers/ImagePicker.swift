import SwiftUI
import UniformTypeIdentifiers

struct ImagePicker: View {
	@EnvironmentObject var settings: AppSettings
	@Binding var imageData: Data?        // ← stores ORIGINAL image data
	let isRack: Bool
	@Binding var rackUnits: Int          // ← live-edited from either view
	@Binding var slotWidth: Int
	let ppi: CGFloat
	
	var body: some View {
#if os(macOS)
		Button {
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.image]
			panel.allowsMultipleSelection = false
			if panel.runModal() == .OK,
			   let url = panel.url,
			   let data = try? Data(contentsOf: url) {
				imageData = data
			}
		} label: {
			Label("Choose Faceplate Image", systemImage: "photo")
		}
#else
		ImagePickerButton_iOS(imageData: $imageData)
#endif
	}
}

#if os(iOS)
/// Wrapper button that presents the real picker
struct ImagePickerButton_iOS: View {
	@Binding var imageData: Data?
	@State private var isPresenting = false
	
	var body: some View {
		Button {
			isPresenting = true
		} label: {
			Label("Choose Faceplate Image", systemImage: "photo")
		}
		.sheet(isPresented: $isPresenting) {
			ImagePicker_iOS(imageData: $imageData)
		}
	}
}

/// The actual UIKit image picker
struct ImagePicker_iOS: UIViewControllerRepresentable {
	@Binding var imageData: Data?
	
	func makeUIViewController(context: Context) -> UIImagePickerController {
		let picker = UIImagePickerController()
		picker.delegate = context.coordinator
		picker.mediaTypes = [UTType.image.identifier]
		return picker
	}
	
	func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
	
	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}
	
	class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
		let parent: ImagePicker_iOS
		init(_ parent: ImagePicker_iOS) {
			self.parent = parent
		}
		
		func imagePickerController(_ picker: UIImagePickerController,
								   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
			if let image = info[.originalImage] as? UIImage,
			   let data = image.pngData() {
				parent.imageData = data
			}
			picker.dismiss(animated: true)
		}
		
		func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
			picker.dismiss(animated: true)
		}
	}
}
#endif
