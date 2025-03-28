import SwiftUI
import Combine
import Vision
import UIKit
import Foundation

// Remove the exported imports as they're causing issues
// Instead we'll make sure all Swift files are included in the build

// Enum to track API key status
enum APIKeyStatus {
    case notSet
    case set
}

struct ContentView: View {
    @StateObject private var viewModel = AttendanceViewModel()
    @State private var selectedTab = 0
    @State private var extractedText: [String] = []
    @State private var previousTab: Int = 0
    @State private var showingClearRecordsAlert = false
    @State private var recordsCleared = false
    @State private var selectedTimePeriod: AttendanceTimePeriod = .month
    @State private var enableOpenAI = false
    @State private var showingAPIKeyInput = false
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: APIKeyStatus = .notSet
    @State private var showingRemoveKeyAlert = false
    @State private var apiKeySaved = false
    
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
    
    // List of available OpenAI models
    private let openAIModels = ["gpt-4-turbo", "gpt-4-vision-preview", "gpt-4o"]
    @State private var selectedModel = "gpt-4-turbo" // Default to match Python script
    
    // Method to handle saving the API key
    private func saveAPIKey() {
        do {
            try OpenAIService.shared.saveAPIKey(apiKeyInput)
            apiKeyStatus = .set
            apiKeyInput = ""
            apiKeySaved = true
            
            // Save selected model to UserDefaults
            UserDefaults.standard.set(selectedModel, forKey: "openai_model")
            
            // Auto-dismiss success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                apiKeySaved = false
            }
        } catch {
            print("Failed to save API key: \(error)")
            // Handle error - perhaps show an alert
        }
    }
    
    // Method to remove the API key
    private func removeAPIKey() {
        OpenAIService.shared.deleteAPIKey()
        apiKeyStatus = .notSet
        apiKeyInput = ""
    }
    
    // Method to check if API key exists and set status appropriately
    private func checkAPIKeyStatus() {
        apiKeyStatus = OpenAIService.shared.hasAPIKey() ? .set : .notSet
        
        // Load saved model preference
        if let savedModel = UserDefaults.standard.string(forKey: "openai_model"),
           openAIModels.contains(savedModel) {
            selectedModel = savedModel
        }
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
            
            // Settings tab (replacing Debug tab)
            NavigationView {
                VStack {
                    List {
                        Section(header: Text("History View Settings")
                                .padding(.top, 4), 
                               footer: Text("Select how much history you want to see by default when opening the History tab.")) {
                            HStack {
                                Text("Default Time Period")
                                Spacer()
                                Picker("Default Time Period", selection: $selectedTimePeriod) {
                                    ForEach(AttendanceTimePeriod.allCases) { period in
                                        Text(period.rawValue).tag(period)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 120, alignment: .trailing)
                                .onChange(of: selectedTimePeriod) { newValue in
                                    // Save to UserDefaults for persistence
                                    UserDefaults.standard.set(newValue.rawValue, forKey: "defaultTimePeriod")
                                    
                                    // Notify the history view of the change
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("TimePreferenceChanged"),
                                        object: newValue
                                    )
                                }
                            }
                        }
                        
                        Section(header: Text("OCR Settings")
                                .padding(.top, 4), 
                               footer: Text("When enabled, OpenAI will be used automatically to improve recognition when the built-in text recognition doesn't perform well.")) {
                            Toggle("Use OpenAI for OCR", isOn: $enableOpenAI)
                                .onChange(of: enableOpenAI) { newValue in
                                    viewModel.setOpenAIEnabled(newValue)
                                    
                                    // If OpenAI is being enabled, check if we need to set an API key
                                    if newValue && !OpenAIService.shared.hasAPIKey() {
                                        showingAPIKeyInput = true
                                    }
                                }
                            
                            if enableOpenAI {
                                VStack(alignment: .leading, spacing: 10) {
                                    // Model selector dropdown
                                    HStack {
                                        Text("Model")
                                        Spacer()
                                        Picker("Model", selection: $selectedModel) {
                                            ForEach(openAIModels, id: \.self) { model in
                                                Text(model).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .frame(width: 200, alignment: .trailing)
                                    }
                                    .padding(.vertical, 4)
                                    
                                    // If no API key is set, show input field
                                    if apiKeyStatus == .notSet {
                                        Text("Enter your OpenAI API Key")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        SecureField("API Key", text: $apiKeyInput)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .padding(.vertical, 4)
                                        
                                        HStack {
                                            Button("Save API Key") {
                                                saveAPIKey()
                                            }
                                            .disabled(apiKeyInput.isEmpty)
                                            .buttonStyle(.borderedProminent)
                                            
                                            Spacer()
                                            
                                            Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                                .font(.footnote)
                                                .foregroundColor(.blue)
                                        }
                                    } else {
                                        // If API key is already set
                                        HStack {
                                            Text("API Key: ")
                                                .foregroundColor(.secondary)
                                            
                                            Text("•••••••••••••••••••")
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                showingAPIKeyInput = true
                                                apiKeyStatus = .notSet
                                                apiKeyInput = ""
                                            }) {
                                                Text("Change")
                                                    .font(.footnote)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        
                                        Button(action: {
                                            showingRemoveKeyAlert = true
                                        }) {
                                            HStack {
                                                Image(systemName: "key.slash.fill")
                                                    .font(.system(size: 12))
                                                Text("Remove API Key")
                                                    .font(.subheadline)
                                            }
                                            .foregroundColor(.red)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    
                                    // Success message when API key is saved
                                    if apiKeySaved {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("API Key saved successfully!")
                                                .foregroundColor(.green)
                                                .font(.footnote)
                                        }
                                        .padding(.top, 4)
                                        .padding(.bottom, 2)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                        }
                        
                        Section(header: Text("Data Management")
                                .padding(.top, 4)) {
                            Button(action: {
                                showingClearRecordsAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                    Text("Delete All Attendance Records")
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
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
                        
                        Section(header: Text("About")
                                .padding(.top, 4)) {
                            HStack {
                                Text("Version")
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Settings")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
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
                .alert("Remove API Key?", isPresented: $showingRemoveKeyAlert) {
                    Button("Yes, Remove", role: .destructive) {
                        removeAPIKey()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will remove your OpenAI API key. You'll need to enter it again to use OpenAI for text recognition.")
                }
                .onAppear {
                    // Load saved time period preference
                    if let savedPeriod = UserDefaults.standard.string(forKey: "defaultTimePeriod"),
                       let period = AttendanceTimePeriod.allCases.first(where: { $0.rawValue == savedPeriod }) {
                        selectedTimePeriod = period
                    }
                    
                    // Load OpenAI setting
                    enableOpenAI = viewModel.isOpenAIEnabled
                    
                    // Check if API key exists
                    checkAPIKeyStatus()
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSettings"))) { _ in
            print("Navigating to Settings screen")
            // Navigate to the settings tab
            selectedTab = 3
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