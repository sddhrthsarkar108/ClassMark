import SwiftUI
import Combine
import Vision
import UIKit

// Remove the exported imports as they're causing issues
// Instead we'll make sure all Swift files are included in the build

struct ContentView: View {
    @StateObject private var viewModel = AttendanceViewModel()
    @State private var selectedTab = 0
    @State private var extractedText: [String] = []
    @State private var previousTab: Int = 0
    @State private var showingClearRecordsAlert = false
    @State private var recordsCleared = false
    
    // Create a computed property for the image binding to simplify the complex expression
    private var imageBinding: Binding<UIImage?> {
        Binding(
            get: { viewModel.selectedImage },
            set: { 
                // Use our new handler method to properly reset state
                viewModel.handleNewImageSelection($0)
                // Post notification when a new image is selected
                if $0 != nil {
                    print("New image selected - posting notification")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NewImageSelected"),
                        object: nil
                    )
                }
            }
        )
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                VStack {
                    if viewModel.selectedImage == nil {
                        // Use the computed property instead of inline binding
                        ImagePickerView(selectedImage: imageBinding)
                        .navigationTitle("Upload Attendance")
                    } else {
                        ImageProcessingView(viewModel: viewModel)
                    }
                }
            }
            .tabItem {
                Label("Take Attendance", systemImage: "camera")
            }
            .tag(0)
            
            NavigationView {
                AttendanceListView(viewModel: viewModel)
            }
            .tabItem {
                Label("Current Session", systemImage: "list.bullet")
            }
            .tag(1)
            
            NavigationView {
                AttendanceHistoryView()
            }
            .tabItem {
                Label("History", systemImage: "calendar")
            }
            .tag(2)
            
            // Debug tab to show extracted text
            NavigationView {
                VStack {
                    Text("Debug Information")
                        .font(.headline)
                        .padding()
                    
                    List {
                        Section(header: Text("Extracted Names")) {
                            if extractedText.isEmpty {
                                Text("No names extracted yet")
                                    .foregroundColor(.gray)
                            } else {
                                ForEach(extractedText, id: \.self) { text in
                                    Text(text)
                                }
                            }
                        }
                        
                        Section(header: Text("Recognition Status")) {
                            Text("Processing: \(viewModel.isProcessing ? "Yes" : "No")")
                            Text("Error: \(viewModel.errorMessage ?? "None")")
                            Text("OpenAI Option Shown: \(viewModel.showOpenAIOption ? "Yes" : "No")")
                            Text("Processing Complete: \(viewModel.processingComplete ? "Yes" : "No")")
                        }
                        
                        Section(header: Text("Debug Actions")) {
                            Button("Force Navigation to List") {
                                selectedTab = 1
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            Button(action: {
                                showingClearRecordsAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                    Text("Delete All Attendance Records")
                                        .foregroundColor(.red)
                                }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            if recordsCleared {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("All attendance records deleted!")
                                        .foregroundColor(.green)
                                }
                                .onAppear {
                                    // Auto-hide the success message after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        recordsCleared = false
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Debug")
                .alert("Delete All Attendance Records?", isPresented: $showingClearRecordsAlert) {
                    Button("Yes, Delete All", role: .destructive) {
                        let dataManager = DataManager.shared
                        dataManager.clearAllAttendanceRecords()
                        recordsCleared = true
                        
                        // Reset the view model's state to reflect no records exist
                        viewModel.resetAttendance()
                        viewModel.isUpdatingExistingRecords = false
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will permanently delete ALL attendance records from the app. You cannot undo this action.")
                }
            }
            .tabItem {
                Label("Debug", systemImage: "terminal")
            }
            .tag(3)
        }
        .onChange(of: selectedTab) { newTab in
            // Reset the image when user navigates TO the snapshot tab (index 0)
            // but only if coming from a different tab
            if newTab == 0 && previousTab != 0 {
                print("Navigated back to Take Attendance tab - resetting to upload screen")
                viewModel.selectedImage = nil
                viewModel.processingComplete = false
                viewModel.errorMessage = nil
                viewModel.showOpenAIOption = false
            }
            previousTab = newTab
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExtractedText"))) { notification in
            if let extractedNames = notification.object as? [String] {
                self.extractedText = extractedNames
                print("Received extracted text notification: \(extractedNames)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MatchedStudents"))) { notification in
            if let matchedStudents = notification.object as? [String] {
                print("Received matched students notification: \(matchedStudents)")
                // Auto-navigate to the attendance list when students are matched
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if viewModel.processingComplete {
                        selectedTab = 1
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUploadAttendance"))) { notification in
            print("Navigating to Upload Attendance screen")
            // Reset the attendance state and image before navigating
            DispatchQueue.main.async {
                // Check if we have a specific date to set for attendance
                if let userInfo = notification.object as? [String: Any],
                   let date = userInfo["date"] as? Date {
                    print("Setting attendance date to: \(date)")
                    viewModel.setAttendanceDate(date)
                } else {
                    viewModel.resetAttendance()
                }
                
                viewModel.selectedImage = nil
                viewModel.processingComplete = false
                viewModel.errorMessage = nil
                viewModel.showOpenAIOption = false
                
                // Navigate to the upload attendance tab
                selectedTab = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            print("Navigating to History screen")
            // Navigate to the history tab
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AttendanceSaved"))) { _ in
            print("Attendance was saved successfully")
            // You could add additional logic here if needed
        }
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Classroom Management Made Easy")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
    }
}

struct DashboardView: View {
    @ObservedObject var attendanceViewModel: AttendanceViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Take Attendance Card
            NavigationLink(destination: CaptureAttendanceView(viewModel: attendanceViewModel)) {
                DashboardCard(
                    title: "Take Attendance",
                    description: "Capture or select an image of attendance list",
                    iconName: "camera.fill",
                    color: .blue
                )
            }
            
            // View History Card
            NavigationLink(destination: AttendanceHistoryView()) {
                DashboardCard(
                    title: "View History",
                    description: "Check past attendance records",
                    iconName: "calendar",
                    color: .green
                )
            }
            
            // Manual Entry Card
            NavigationLink(destination: AttendanceListView(viewModel: attendanceViewModel)) {
                DashboardCard(
                    title: "Manual Entry",
                    description: "Manually mark attendance",
                    iconName: "pencil",
                    color: .orange
                )
            }
        }
        .onAppear {
            // Reset attendance when returning to dashboard
            attendanceViewModel.resetAttendance()
            attendanceViewModel.selectedImage = nil
            attendanceViewModel.errorMessage = nil
        }
    }
}

struct DashboardCard: View {
    let title: String
    let description: String
    let iconName: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.system(size: 30))
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.2))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct CaptureAttendanceView: View {
    @ObservedObject var viewModel: AttendanceViewModel
    
    var body: some View {
        VStack {
            if viewModel.selectedImage == nil {
                // Show image picker
                ImagePickerView(selectedImage: $viewModel.selectedImage)
            } else {
                // Show image processing view
                ImageProcessingView(viewModel: viewModel)
            }
        }
        .navigationTitle("Capture Attendance")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 