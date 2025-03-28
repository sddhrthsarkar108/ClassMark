import SwiftUI

struct AttendanceListView: View {
    @ObservedObject var viewModel: AttendanceViewModel
    @State private var showingSaveConfirmation = false
    @State private var saveButtonTapped = false
    @State private var showingCompletionOptions = false
    @State private var isViewFullyLoaded = false
    @State private var pendingSaveCompletion = false
    @State private var showingOpenAIConfirmation = false
    @State private var isProcessingWithOpenAI = false
    @State private var showingOpenAIDisabledAlert = false
    
    var body: some View {
        mainListContent
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .confirmationDialog(
                viewModel.isUpdatingExistingRecords ? 
                    "Attendance Updated Successfully" : 
                    "Attendance Saved Successfully",
                isPresented: $showingCompletionOptions,
                titleVisibility: .visible
            ) {
                confirmationDialogButtons
            } message: {
                Text(viewModel.isUpdatingExistingRecords ? 
                    "You have updated today's attendance records. What would you like to do next?" : 
                    "What would you like to do next?")
            }
            .alert(isPresented: $showingSaveConfirmation) {
                Alert(
                    title: Text(viewModel.isUpdatingExistingRecords ? "Attendance Updated" : "Attendance Saved"),
                    message: Text(viewModel.isUpdatingExistingRecords ? 
                        "Today's attendance records have been updated successfully." : 
                        "Attendance has been recorded successfully."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Process Absent Students with OpenAI?",
                isPresented: $showingOpenAIConfirmation,
                titleVisibility: .visible
            ) {
                Button("Process with OpenAI") {
                    print("User chose to process absent students with OpenAI")
                    startOpenAIProcessingForAbsentStudents()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("OpenAI will analyze the image again and check only for students currently marked as absent. This may improve recognition results.")
            }
            .alert("OpenAI Processing Disabled", isPresented: $showingOpenAIDisabledAlert) {
                Button("Go to Settings", role: .none) {
                    // Navigate to settings tab
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToSettings"),
                        object: nil
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.selectedImage == nil ? 
                     "Please process an image first before using OpenAI. Go to the Take Attendance tab to select an image." : 
                     "OpenAI processing is currently disabled. Please enable it in the Settings tab to use this feature.")
            }
            .onAppear(perform: onViewAppear)
            .onChange(of: pendingSaveCompletion, perform: handlePendingSaveCompletionChange)
            .onDisappear(perform: onViewDisappear)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AttendanceSaved"))) { _ in
                pendingSaveCompletion = true
            }
            .onReceive(viewModel.$isProcessing) { isProcessing in
                // Update our local processing state based on the ViewModel
                isProcessingWithOpenAI = isProcessing && viewModel.useOpenAI
                
                // When processing completes with OpenAI, update the hasUsedOpenAI flag
                if !isProcessing && viewModel.useOpenAI {
                    // The processing just completed, hasUsedOpenAI has already been set in the ViewModel
                    print("OpenAI processing completed")
                }
            }
            .onReceive(viewModel.$processingComplete) { complete in
                // When processing is complete, reset our local state
                if complete {
                    isProcessingWithOpenAI = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAIProcessingComplete"))) { _ in
                isProcessingWithOpenAI = false
                
                // Show feedback to user
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Show toast message
                var banner = NotificationBanner(title: "OpenAI Processing Complete", style: .success)
                banner.duration = 2.0
                banner.show()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAIProcessingFailed"))) { notification in
                isProcessingWithOpenAI = false
                
                // Show feedback to user
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                
                // Show error message
                let errorMessage = notification.object as? String ?? "Failed to process with OpenAI"
                var banner = NotificationBanner(title: "Processing Failed", subtitle: errorMessage, style: .danger)
                banner.duration = 3.0
                banner.show()
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Attendance")
                .font(.headline)
                .fontWeight(.bold)
        }
        
        // Replace Save/Update button with brain icon for OpenAI processing
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                // First check if an image is selected
                guard viewModel.selectedImage != nil else {
                    // Show a toast notification instead of an alert for better UX
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    
                    var banner = NotificationBanner(
                        title: "No Image Available",
                        subtitle: "Please process an image first before using OpenAI",
                        style: .warning
                    )
                    banner.duration = 2.0
                    banner.show()
                    
                    // Guide the user to the Take Attendance tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToUploadAttendance"),
                            object: nil
                        )
                    }
                    return
                }
                
                // Only then check if OpenAI is enabled
                if viewModel.isOpenAIEnabled {
                    showingOpenAIConfirmation = true
                } else {
                    showingOpenAIDisabledAlert = true
                }
            }) {
                // Use the dedicated animated brain icon view
                if isProcessingWithOpenAI {
                    ProcessingBrainIcon()
                } else {
                    Image(systemName: "brain")
                        .foregroundColor(viewModel.selectedImage != nil ? .blue : .gray.opacity(0.5))
                        .font(.system(size: 16))
                }
            }
            .disabled(isProcessingWithOpenAI)
            // Add tooltip to explain why button is disabled
            .help(viewModel.selectedImage == nil ? "Process an image first to use OpenAI" : "Process with OpenAI")
        }
    }
    
    @ViewBuilder
    private var confirmationDialogButtons: some View {
        Button("Take New Attendance") {
            print("User chose to take new attendance")
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToUploadAttendance"),
                object: nil
            )
        }
        
        Button("View Saved History") {
            print("User chose to view history")
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToHistory"),
                object: nil
            )
        }
        
        Button("Continue Editing", role: .cancel) {
            print("User chose to continue editing")
            // Just stay on current screen
        }
    }
    
    private var mainListContent: some View {
        List {
            if viewModel.isClassLoaded {
                // Header with class name and processing indicator
                Section {
                    if isProcessingWithOpenAI {
                        HStack {
                            ProcessingBrainIcon()
                                .frame(width: 32, height: 32)
                                .padding(.trailing, 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Processing with OpenAI...")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Text("Analyzing attendance data...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Summary section
            Section {
                AttendanceSummaryView(
                    totalCount: viewModel.students.count,
                    presentCount: presentStudentsCount,
                    absentCount: absentStudentsCount,
                    detectedCount: viewModel.detectedNamesCount,
                    showMismatchWarning: viewModel.hasDetectionMismatch,
                    isUpdatingExistingRecords: viewModel.isUpdatingExistingRecords,
                    isAfterAIProcessing: viewModel.hasUsedOpenAI
                )
            }
            
            // Processing with OpenAI indicator (simplified)
            if isProcessingWithOpenAI {
                Section {
                    VStack(spacing: 12) {
                        ProcessingBrainIcon()
                            .frame(width: 44, height: 44)
                            .padding(.top, 4)
                        
                        Text("OpenAI is analyzing your attendance data")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("This may take a few moments...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            
            Section(header: HStack {
                Text("Date: \(formattedDate)")
                
                Spacer()
                
                // Select All radio button (without label)
                Button(action: {
                    // Check if all students are present
                    let allPresent = viewModel.students.allSatisfy { 
                        viewModel.attendanceStatus[$0.rollNumber] == .present 
                    }
                    
                    // If all are present, mark all absent; otherwise mark all present
                    if allPresent {
                        viewModel.markAllAbsent()
                    } else {
                        viewModel.markAllPresent()
                    }
                    
                    // Add haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    // Radio style: circle with checkmark when selected
                    let allPresent = viewModel.students.allSatisfy { 
                        viewModel.attendanceStatus[$0.rollNumber] == .present 
                    }
                    
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        
                        if allPresent {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 22, height: 22)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }) {
                ForEach(viewModel.students) { student in
                    StudentAttendanceRow(
                        student: student,
                        attendanceState: viewModel.attendanceStatus[student.rollNumber] ?? .absent,
                        toggleAction: {
                            viewModel.toggleAttendance(for: student.rollNumber)
                        }
                    )
                }
            }
            
            // Add a section for the Save button to make it more accessible
            Section {
                Button(action: {
                    print("Save button tapped")
                    saveButtonTapped = true
                    
                    // Add haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    
                    // Save attendance records
                    viewModel.saveAttendance()
                    print("Attendance saved")
                    
                    // Set the pending flag to show the dialog once it's safe
                    pendingSaveCompletion = true
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: viewModel.isUpdatingExistingRecords ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                        Text(viewModel.isUpdatingExistingRecords ? "Update Attendance" : "Save Attendance")
                            .bold()
                        Spacer()
                    }
                    .padding()
                    .background(viewModel.isUpdatingExistingRecords ? Color.orange : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 8)
            }
        }
    }
    
    // New method to process only absent students with OpenAI
    private func startOpenAIProcessingForAbsentStudents() {
        guard let _ = viewModel.selectedImage else {
            // Show error notification
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            
            var banner = NotificationBanner(
                title: "No Image Available",
                subtitle: "Please process an image first before using OpenAI",
                style: .warning
            )
            banner.duration = 2.0
            banner.show()
            
            // Guide the user to the Take Attendance tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToUploadAttendance"),
                    object: nil
                )
            }
            return
        }
        
        // Set processing state
        isProcessingWithOpenAI = true
        
        // Use ViewModel to process with OpenAI
        viewModel.processAbsentStudentsWithOpenAI()
    }
    
    // Existing method (needed for backward compatibility)
    private func startOpenAIProcessing() {
        guard let _ = viewModel.selectedImage else {
            // Show error notification
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            
            var banner = NotificationBanner(
                title: "No Image Available",
                subtitle: "Please process an image first before using OpenAI",
                style: .warning
            )
            banner.duration = 2.0
            banner.show()
            return
        }
        
        // Set processing state
        isProcessingWithOpenAI = true
        
        // Use ViewModel to process with OpenAI
        viewModel.processWithOpenAI()
    }
    
    private func onViewAppear() {
        print("AttendanceListView appeared")
        // Reset the save button state
        saveButtonTapped = false
        
        // Mark that the view is fully loaded after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isViewFullyLoaded = true
            
            // If there's a pending save completion, show the dialog now
            if pendingSaveCompletion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCompletionOptions = true
                    pendingSaveCompletion = false
                }
            }
        }
    }
    
    private func onViewDisappear() {
        // Reset view state when disappearing
        isViewFullyLoaded = false
    }
    
    private func handlePendingSaveCompletionChange(_ isPending: Bool) {
        if isPending && isViewFullyLoaded {
            // Only show the completion dialog if the view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showingCompletionOptions = true
                pendingSaveCompletion = false
            }
        }
    }
    
    private var presentStudentsCount: Int {
        viewModel.students.filter { 
            viewModel.attendanceStatus[$0.rollNumber] == .present
        }.count
    }
    
    private var absentStudentsCount: Int {
        viewModel.students.count - presentStudentsCount
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: viewModel.attendanceDate)
    }
}

struct AttendanceSummaryView: View {
    let totalCount: Int
    let presentCount: Int
    let absentCount: Int
    let detectedCount: Int
    let showMismatchWarning: Bool
    let isUpdatingExistingRecords: Bool
    let isAfterAIProcessing: Bool
    
    init(totalCount: Int, presentCount: Int, absentCount: Int, detectedCount: Int, 
         showMismatchWarning: Bool, isUpdatingExistingRecords: Bool, isAfterAIProcessing: Bool = false) {
        self.totalCount = totalCount
        self.presentCount = presentCount
        self.absentCount = absentCount
        self.detectedCount = detectedCount
        self.showMismatchWarning = showMismatchWarning
        self.isUpdatingExistingRecords = isUpdatingExistingRecords
        self.isAfterAIProcessing = isAfterAIProcessing
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                // Total students
                VStack {
                    Text("\(totalCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Detected names
                VStack {
                    Text("\(detectedCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(showMismatchWarning ? .orange : .primary)
                    Text("Detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Present students
                VStack {
                    Text("\(presentCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                    Text("Present")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Absent students
                VStack {
                    Text("\(absentCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                    Text("Absent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            
            // Display both messages side by side if both are visible
            // Otherwise show whichever one is visible
            if showMismatchWarning || isUpdatingExistingRecords {
                VStack(spacing: 8) {
                    // Show warning when there's a significant mismatch
                    if showMismatchWarning {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            // Change message based on whether AI processing has been done
                            Text(isAfterAIProcessing 
                                ? "Detection mismatch. Verify manually." 
                                : "Detection mismatch. Reprocess with AI.")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                    
                    // Show updating message
                    if isUpdatingExistingRecords {
                        HStack(alignment: .center) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("You are updating today's attendance.")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(10)
    }
}

struct StudentAttendanceRow: View {
    let student: Student
    let attendanceState: AttendanceState
    let toggleAction: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(student.name)
                    .font(.headline)
                Text("Roll No: \(student.rollNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Radio button style attendance indicator
            Button(action: toggleAction) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    
                    if attendanceState == .present {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 22, height: 22)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// Simple banner notification class to show feedback
struct NotificationBanner {
    enum BannerStyle {
        case success
        case warning
        case danger
        
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .danger: return .red
            }
        }
    }
    
    let title: String
    let subtitle: String?
    let style: BannerStyle
    var duration: TimeInterval = 2.0
    
    init(title: String, subtitle: String? = nil, style: BannerStyle = .success) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }
    
    func show() {
        // Create the banner view
        let bannerView = UIHostingController(
            rootView: BannerView(title: title, subtitle: subtitle, style: style)
        )
        
        // Configure the banner
        bannerView.view.backgroundColor = .clear
        bannerView.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to key window - updated for iOS 15+
        var keyWindow: UIWindow?
        if #available(iOS 15.0, *) {
            // Get the connected scenes
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                keyWindow = windowScene.windows.first { $0.isKeyWindow }
            }
        } else {
            // Fallback for older iOS versions
            keyWindow = UIApplication.shared.windows.first { $0.isKeyWindow }
        }
        
        if let keyWindow = keyWindow {
            keyWindow.addSubview(bannerView.view)
            
            // Constraints
            NSLayoutConstraint.activate([
                bannerView.view.leadingAnchor.constraint(equalTo: keyWindow.leadingAnchor, constant: 16),
                bannerView.view.trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor, constant: -16),
                bannerView.view.topAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 8),
                bannerView.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
            ])
            
            // Animate in
            bannerView.view.alpha = 0
            bannerView.view.transform = CGAffineTransform(translationX: 0, y: -80)
            
            UIView.animate(withDuration: 0.3, animations: {
                bannerView.view.alpha = 1
                bannerView.view.transform = .identity
            })
            
            // Dismiss after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                UIView.animate(withDuration: 0.3, animations: {
                    bannerView.view.alpha = 0
                    bannerView.view.transform = CGAffineTransform(translationX: 0, y: -80)
                }, completion: { _ in
                    bannerView.view.removeFromSuperview()
                })
            }
        }
    }
    
    // Banner view
    struct BannerView: View {
        let title: String
        let subtitle: String?
        let style: BannerStyle
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: style == .success ? "checkmark.circle.fill" : 
                                       style == .warning ? "exclamationmark.triangle.fill" : 
                                       "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            .padding()
            .background(style.color)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        }
    }
}

// Custom animated brain icon for OpenAI processing
struct ProcessingBrainIcon: View {
    @State private var isPulsing = false
    @State private var rotationDegrees = 0.0
    @State private var rotationTimer: Timer?
    @State private var colorPulse = 0.0
    
    // Computed color properties that cycle between blue and white
    private var iconColor: Color {
        // Sine wave oscillation between 0 and 1
        let sineValue = (sin(colorPulse) + 1) / 2
        
        // When sineValue is near 1, color is white; when near 0, color is blue
        return sineValue > 0.5 
            ? Color.white.opacity(0.9) 
            : Color.blue.opacity(0.9)
    }
    
    private var gradientColors: [Color] {
        // Create contrasting gradient colors based on the sine wave
        let sineValue = (sin(colorPulse) + 1) / 2
        
        return sineValue > 0.5 
            ? [Color.blue.opacity(0.9), Color.white.opacity(0.7)]
            : [Color.white.opacity(0.7), Color.blue.opacity(0.9)]
    }
    
    var body: some View {
        ZStack {
            // Outer rotating circle with alternating gradient
            Circle()
                .stroke(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading, 
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 32, height: 32)
                .rotationEffect(Angle(degrees: rotationDegrees))
            
            // Background pulsing circle
            Circle()
                .fill(Color.blue.opacity(0.1 + (0.3 * sin(colorPulse))))
                .frame(width: 28, height: 28)
            
            // Pulsing brain icon with alternating color
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .scaleEffect(isPulsing ? 1.2 : 0.9)
        }
        .onAppear {
            // Start animations when view appears
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            
            // Use a timer for continuous rotation and color pulsing
            rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
                withAnimation {
                    rotationDegrees += 3
                    if rotationDegrees >= 360 {
                        rotationDegrees = 0
                    }
                    
                    // Update color pulse value - slower to make color change more noticeable
                    colorPulse += 0.04
                    if colorPulse >= .pi * 2 {
                        colorPulse = 0
                    }
                }
            }
            
            // Store the timer to ensure it's accessible for cleanup
            if let timer = rotationTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
    }
}

#Preview {
    NavigationView {
        AttendanceListView(viewModel: AttendanceViewModel())
    }
} 