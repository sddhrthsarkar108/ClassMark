import SwiftUI

struct ImageProcessingView: View {
    @ObservedObject var viewModel: AttendanceViewModel
    @State private var navigateToAttendanceList = false
    
    var body: some View {
        VStack {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding()
            }
            
            if viewModel.isProcessing {
                ProgressView("Processing image...")
                    .padding()
            } else if viewModel.showOpenAIOption {
                VStack(spacing: 16) {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Text("Local text recognition may not have captured all names. Would you like to try OpenAI for better accuracy?")
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    HStack(spacing: 20) {
                        Button("Use OpenAI") {
                            viewModel.processWithOpenAI()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Continue with Current Results") {
                            viewModel.showOpenAIOption = false
                            viewModel.processingComplete = true
                            navigateToAttendanceList = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            } else if viewModel.errorMessage != nil {
                Text(viewModel.errorMessage ?? "An error occurred")
                    .foregroundColor(.red)
                    .padding()
                
                Button("Try Again") {
                    viewModel.selectedImage = nil
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.bordered)
                .padding()
            } else {
                // Show process button when image is selected but not yet processed
                if viewModel.selectedImage != nil && !navigateToAttendanceList {
                    Button(action: {
                        viewModel.processImage()
                    }) {
                        Text("Process Image")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding()
                    
                    Button("Choose Different Image") {
                        viewModel.selectedImage = nil
                        viewModel.errorMessage = nil
                    }
                    .padding()
                }
            }
            
            NavigationLink(
                destination: AttendanceListView(viewModel: viewModel),
                isActive: $navigateToAttendanceList
            ) {
                EmptyView()
            }
            .hidden()
        }
        .onChange(of: viewModel.useOpenAI) { useOpenAI in
            if !useOpenAI && viewModel.errorMessage == nil && viewModel.processingComplete {
                print("OpenAI processing complete, navigating to attendance list")
                navigateToAttendanceList = true
            }
        }
        .onChange(of: viewModel.processingComplete) { complete in
            if complete && !viewModel.showOpenAIOption && viewModel.errorMessage == nil {
                print("Processing complete, navigating to attendance list")
                // Add a slight delay to ensure UI updates complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigateToAttendanceList = true
                }
            }
        }
        // Add this onReceive to automatically navigate after successful processing
        .onAppear {
            // Debug print to verify this view is appearing
            print("ImageProcessingView appeared")
        }
        .onReceive(viewModel.$isProcessing) { isProcessing in
            print("Processing status changed: \(isProcessing)")
            if !isProcessing && !viewModel.showOpenAIOption && viewModel.errorMessage == nil && viewModel.selectedImage != nil && viewModel.processingComplete {
                print("Navigating to attendance list")
                // Add a slight delay to ensure UI updates complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigateToAttendanceList = true
                }
            }
        }
        .navigationTitle("Process Attendance")
    }
}

#Preview {
    NavigationView {
        ImageProcessingView(viewModel: AttendanceViewModel())
    }
} 