import SwiftUI
import UIKit
import PhotosUI

// UIViewControllerRepresentable for PHPickerViewController
struct PHPickerRepresentable: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerRepresentable
        
        init(_ parent: PHPickerRepresentable) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    if let error = error {
                        print("Error loading image: \(error)")
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

// UIViewControllerRepresentable for UIImagePickerController (camera capture)
struct CameraPickerRepresentable: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerRepresentable
        
        init(_ parent: CameraPickerRepresentable) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// A wrapper view that can show either the photo library picker or camera picker
struct ImagePickerView: View {
    @Binding var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var sourceType: SourceType = .photoLibrary
    @State private var showTip = false
    
    enum SourceType {
        case photoLibrary
        case camera
    }
    
    var body: some View {
        VStack {
            // Top spacing to push content down slightly
            Spacer().frame(height: 20)
            
            // Option buttons in a horizontal row
            HStack(spacing: 60) {
                // Gallery Button
                Button(action: {
                    sourceType = .photoLibrary
                    showImagePicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.blue)
                            .clipShape(Circle())
                        
                        Text("Gallery")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                
                // Camera Button
                Button(action: {
                    sourceType = .camera
                    showCameraPicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.blue)
                            .clipShape(Circle())
                        
                        Text("Camera")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.top, 20)
            
            // Image Preview Area (centered in the screen)
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 40)
            } else {
                Spacer().frame(height: 60)
                
                Image(systemName: "photo.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.secondary.opacity(0.3))
                    .padding(.bottom, 12)
                
                Text("No Image Selected")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                    
                Text("Take a photo or select an image of your attendance list")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Upload Attendance")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showTip.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            PHPickerRepresentable(image: $selectedImage)
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerRepresentable(image: $selectedImage)
        }
        .alert(isPresented: $showTip) {
            Alert(
                title: Text("Tips for Best Results"),
                message: Text("Ensure the list is clear, well-lit, and student names are legible for best recognition results."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
} 