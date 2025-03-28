import SwiftUI

struct ImageProcessingView: View {
    @ObservedObject var viewModel: AttendanceViewModel
    @State private var navigateToAttendanceList = false
    
    var body: some View {
        VStack {
            // Top spacing
            Spacer().frame(height: 20)
            
            // Image Preview Area
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
            
            // Processing States
            if viewModel.isProcessing {
                // Processing state
                VStack(spacing: 16) {
                    ProgressView("Processing image...")
                        .padding(.top, 24)
                    
                    Text("Please wait while we analyze the image...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 20)
            } else if viewModel.showOpenAIOption {
                // OpenAI option
                VStack(spacing: 16) {
                    Text("Recognition Results")
                        .font(.headline)
                        .padding(.top, 20)
                    
                    if viewModel.isOpenAIEnabled {
                        Text("Using OpenAI for better text recognition...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        ProgressView()
                            .padding(.vertical, 10)
                    } else {
                        Text("Local text recognition may not have captured all names. Would you like to try OpenAI for better accuracy?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        HStack(spacing: 20) {
                            Button("Use OpenAI") {
                                viewModel.processWithOpenAI()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Continue with Current Results") {
                                viewModel.showOpenAIOption = false
                                viewModel.processingComplete = true
                                
                                // Simple navigation without animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    navigateToAttendanceList = true
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                    
                    Text("Enable OpenAI for OCR in Settings to use automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
            } else if viewModel.errorMessage != nil {
                // Error state
                VStack(spacing: 16) {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.top, 20)
                    
                    Text(viewModel.errorMessage ?? "Unknown error occurred")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Button("Try Again") {
                        viewModel.selectedImage = nil
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                }
            } else if !navigateToAttendanceList {
                // Default state - show process button
                VStack(spacing: 16) {
                    Text("Ready to Process")
                        .font(.headline)
                        .padding(.top, 20)
                    
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
                    .padding(.horizontal, 20)
                    
                    Button("Choose Different Image") {
                        viewModel.selectedImage = nil
                        viewModel.errorMessage = nil
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.bottom, 20)
                }
            }
            
            Spacer()
            
            NavigationLink(
                destination: AttendanceListView(viewModel: viewModel),
                isActive: $navigateToAttendanceList
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Process Attendance")
                    .font(.title2)
                    .fontWeight(.bold)
            }
        }
        .onChange(of: viewModel.useOpenAI) { useOpenAI in
            if !useOpenAI && viewModel.errorMessage == nil && viewModel.processingComplete {
                // Simple navigation without animation delays
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigateToAttendanceList = true
                }
            }
        }
        .onChange(of: viewModel.processingComplete) { complete in
            if complete && !viewModel.showOpenAIOption && viewModel.errorMessage == nil {
                // Simple navigation without animation delays
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigateToAttendanceList = true
                }
            }
        }
        .onAppear {
            // Reset navigation state when view appears
            navigateToAttendanceList = false
        }
        .onReceive(viewModel.$isProcessing) { isProcessing in
            if !isProcessing && !viewModel.showOpenAIOption && viewModel.errorMessage == nil && viewModel.selectedImage != nil && viewModel.processingComplete {
                // Simple navigation without animation delays
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigateToAttendanceList = true
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ImageProcessingView(viewModel: AttendanceViewModel())
    }
} 