import Foundation
import SwiftUI
import Combine

// Define attendance state 
enum AttendanceState {
    case present
    case absent
    
    var isPresent: Bool {
        switch self {
        case .present:
            return true
        case .absent:
            return false
        }
    }
}

class AttendanceViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var attendanceDate: Date = Date()
    // Changed to simple present/absent state
    @Published var attendanceStatus: [String: AttendanceState] = [:]
    // Removed uncertainStudents array
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var selectedImage: UIImage?
    @Published var showOpenAIOption: Bool = false
    @Published var useOpenAI: Bool = false
    @Published var processingComplete: Bool = false
    @Published var saveSuccessful: Bool = false
    @Published var isUpdatingExistingRecords: Bool = false
    // We'll use a boolean instead of a Class model
    @Published var isClassLoaded: Bool = false
    // Track the number of detected names in the image
    @Published var detectedNamesCount: Int = 0
    // Track if OpenAI has been used for processing
    @Published var hasUsedOpenAI: Bool = false
    
    // Single confidence threshold - above this is present, below is absent
    private let confidenceThreshold: Double = 0.75
    
    private var dataManager = DataManager.shared
    private var textRecognitionService = TextRecognitionService.shared
    private var openAIService = OpenAIService.shared
    // Don't use CalendarHelper at this point
    private var calendarHelper: Any? = nil
    
    // Key for UserDefaults
    private let openAIEnabledKey = "openAIEnabled"
    
    // Check if OpenAI is enabled in settings
    var isOpenAIEnabled: Bool {
        UserDefaults.standard.bool(forKey: openAIEnabledKey)
    }
    
    // Check if there's a mismatch between detection and attendance counts
    var hasDetectionMismatch: Bool {
        // Only check when we have processed an image and have some detected names
        guard processingComplete && detectedNamesCount > 0 else { return false }
        
        let presentCount = students.filter { attendanceStatus[$0.rollNumber] == .present }.count
        
        // Check specifically for cases where detected > present as this indicates likely missed matches
        // For detected < present, we need a larger threshold as it might be due to manual overrides
        if detectedNamesCount > presentCount {
            // Even a small difference when detected > present is significant
            return (detectedNamesCount - presentCount) >= 1
        } else {
            // For present > detected, we use a larger threshold
            let significantDifference = 3
            return (presentCount - detectedNamesCount) > significantDifference
        }
    }
    
    init() {
        loadStudents()
        resetAttendance()
        checkExistingRecords()
        isClassLoaded = true // For UI purposes
    }
    
    private func loadStudents() {
        students = dataManager.getStudents()
    }
    
    // Set a specific date for attendance taking
    func setAttendanceDate(_ date: Date) {
        attendanceDate = date
        checkExistingRecordsForDate(date)
    }
    
    // Check if records already exist for today
    private func checkExistingRecords() {
        checkExistingRecordsForDate(Date())
    }
    
    // Check if records exist for a specific date
    private func checkExistingRecordsForDate(_ date: Date) {
        let records = dataManager.getAttendanceForDate(date)
        isUpdatingExistingRecords = !records.isEmpty
        
        if isUpdatingExistingRecords {
            print("Found \(records.count) existing records for \(formatDate(date)). Will update them.")
            
            // Pre-populate attendance status from existing records
            for record in records {
                if let student = students.first(where: { $0.rollNumber == record.studentRollNumber }) {
                    attendanceStatus[record.studentRollNumber] = record.isPresent ? .present : .absent
                }
            }
        }
    }
    
    // Helper function to reset all attendance statuses to absent
    private func resetAllAttendanceToAbsent() {
        // Reset all attendance statuses to absent
        attendanceStatus = Dictionary(uniqueKeysWithValues: students.map { ($0.rollNumber, AttendanceState.absent) })
        print("Reset all attendance statuses to absent")
    }
    
    // Reset attendance status for all students (alias for consistency)
    private func resetAttendanceStatus() {
        resetAllAttendanceToAbsent()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // Reset all state for a fresh attendance session
    func resetAttendance() {
        // Reset attendance statuses to all absent
        attendanceStatus = Dictionary(uniqueKeysWithValues: students.map { ($0.rollNumber, AttendanceState.absent) })
        
        // Reset date to current date
        attendanceDate = Date()
        
        // Reset all processing state
        isProcessing = false
        errorMessage = nil
        selectedImage = nil
        showOpenAIOption = false
        useOpenAI = false
        processingComplete = false
        saveSuccessful = false
        detectedNamesCount = 0
        hasUsedOpenAI = false
        
        // Check if we're updating existing records
        checkExistingRecords()
        
        print("AttendanceViewModel: All state reset for new attendance session")
    }
    
    // Process selected image with local Vision framework
    func processImage() {
        guard let image = selectedImage else {
            errorMessage = "No image selected"
            return
        }
        
        isProcessing = true
        errorMessage = nil
        processingComplete = false
        
        // Always reset all attendance statuses to absent before processing
        resetAllAttendanceToAbsent()
        print("Reset all attendance statuses before processing new image")
        
        // Mark if we're updating existing records
        let isUpdating = dataManager.hasAttendanceRecords(for: attendanceDate)
        if isUpdating {
            print("Processing image for date with existing records - will override previous attendance")
        }
        
        textRecognitionService.recognizeText(from: image) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let extractedText):
                    print("Extracted text: \(extractedText)")
                    
                    // Update detected names count
                    self.detectedNamesCount = extractedText.count
                    print("Detected \(self.detectedNamesCount) potential names in the image")
                    
                    let matchResult = self.textRecognitionService.matchNamesWithStudents(extractedTexts: extractedText)
                    
                    // Apply simplified attendance logic
                    self.processMatchResults(matchResult)
                    
                    // Post notification with matched students
                    let presentStudentNames = self.students
                        .filter { self.attendanceStatus[$0.rollNumber] == .present }
                        .map { $0.name }
                    
                    print("Students marked present from image: \(presentStudentNames)")
                    print("Total students marked present: \(presentStudentNames.count)")
                    print("Total students marked absent: \(self.students.count - presentStudentNames.count)")
                    
                    // Log if there's a detection mismatch
                    if self.hasDetectionMismatch {
                        print("WARNING: Detection mismatch detected. Extracted \(self.detectedNamesCount) names, but only matched \(presentStudentNames.count) students.")
                    }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MatchedStudents"),
                        object: presentStudentNames
                    )
                    
                    // Check if we should suggest using OpenAI
                    let shouldUseFallback = self.textRecognitionService.shouldUseFallback(matchResult: matchResult)
                    self.showOpenAIOption = shouldUseFallback && self.isOpenAIEnabled
                    
                    // If OpenAI is enabled and we should use fallback, automatically use it
                    if shouldUseFallback && self.isOpenAIEnabled {
                        // Auto-use OpenAI without prompting, since it's enabled in settings
                        self.processWithOpenAI()
                    } else {
                        // Otherwise, just complete with current results
                        self.processingComplete = !self.showOpenAIOption
                    }
                    
                    // We're definitely updating records for this date now
                    self.isUpdatingExistingRecords = isUpdating
                    
                case .failure(let error):
                    print("Text recognition error: \(error)")
                    self.errorMessage = "Failed to recognize text: \(error)"
                    
                    // Reset detected names count on failure
                    self.detectedNamesCount = 0
                    
                    // Only show OpenAI option if enabled in settings
                    self.showOpenAIOption = self.isOpenAIEnabled
                    
                    // If OpenAI is enabled, automatically use it on failure
                    if self.isOpenAIEnabled {
                        self.processWithOpenAI()
                    }
                }
            }
        }
    }
    
    // Simplified match results processing based on single confidence threshold
    private func processMatchResults(_ matchResult: [String: Double]) {
        for (rollNumber, confidence) in matchResult {
            if confidence >= confidenceThreshold {
                // High confidence - mark present
                attendanceStatus[rollNumber] = .present
                print("Student with roll number \(rollNumber) marked PRESENT with confidence score: \(String(format: "%.2f", confidence * 100))%")
            } else {
                // Low confidence - keep as absent
                print("Student with roll number \(rollNumber) kept as ABSENT due to low confidence score: \(String(format: "%.2f", confidence * 100))%")
            }
        }
    }
    
    // Process image with completion handler - used from ImageProcessingView
    func processImage(_ image: UIImage, completion: @escaping () -> Void) {
        print("Processing image in AttendanceViewModel")
        self.selectedImage = image
        self.isProcessing = true
        self.processingComplete = false
        self.useOpenAI = false
        
        // Clear existing records
        resetAllAttendanceToAbsent()
        
        let attendanceDate = Date()
        self.attendanceDate = attendanceDate
        
        // Check if we already have records for today
        let existingRecords = dataManager.hasAttendanceRecords(for: attendanceDate)
            
        // Set flag if we are updating existing records
        self.isUpdatingExistingRecords = existingRecords
        
        // Use Vision and Face Detection for local processing
        self.textRecognitionService.recognizeText(from: image) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let extractedText):
                    print("Extracted text: \(extractedText)")
                    
                    // Update detected names count
                    self.detectedNamesCount = extractedText.count
                    print("Detected \(self.detectedNamesCount) potential names in the image")
                    
                    let matchResult = self.textRecognitionService.matchNamesWithStudents(extractedTexts: extractedText)
                    
                    // Apply simplified attendance logic
                    self.processMatchResults(matchResult)
                    
                    // Mark processing as complete
                    self.processingComplete = true
                    completion()
                    
                case .failure(let error):
                    print("Text recognition error: \(error)")
                    self.errorMessage = "Failed to recognize text: \(error)"
                    self.detectedNamesCount = 0
                    self.processingComplete = true
                    completion()
                }
            }
        }
    }
    
    // Process with OpenAI as fallback
    func processWithOpenAI() {
        guard let image = selectedImage else {
            errorMessage = "No image selected"
            return
        }
        
        // Check if API key is set before attempting to use OpenAI
        if !OpenAIService.shared.hasAPIKey() {
            errorMessage = "OpenAI API key is not set. Please add your API key in Settings."
            
            // Post notification about failure
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenAIProcessingFailed"),
                object: "OpenAI API key is not set. Please add your API key in Settings."
            )
            
            // Prompt to navigate to settings
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToSettings"),
                object: nil
            )
            
            return
        }
        
        isProcessing = true
        errorMessage = nil
        useOpenAI = true
        hasUsedOpenAI = true
        processingComplete = false
        
        // Reset attendance status for all students
        resetAttendanceStatus()
        
        // Get the list of current student names (marked as absent by default)
        let absentStudentNames = students.map { $0.name }
        print("Processing \(absentStudentNames.count) students with OpenAI, all initially marked absent")
        
        // Mark if we're updating existing records
        let isUpdating = dataManager.hasAttendanceRecords(for: attendanceDate)
        if isUpdating {
            print("Processing image with OpenAI for date with existing records - will preserve present students")
        }
        
        openAIService.recognizeNamesFromImage(image, absentStudents: absentStudentNames) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.useOpenAI = false
                
                switch result {
                case .success(let names):
                    print("OpenAI extracted names: \(names)")
                    
                    // Update detected names count
                    self.detectedNamesCount = names.count
                    print("Found \(self.detectedNamesCount) names in the image")
                    
                    // Clean up names by removing numbering and special characters
                    let cleanedNames = names.map { name -> String in
                        let cleaned = StringMatching.cleanName(name)
                        print("OpenAI: Cleaning name from '\(name)' to '\(cleaned)'")
                        return cleaned
                    }
                    
                    // Match names with students using cleaned names
                    let matchResults = self.textRecognitionService.matchNamesWithStudents(extractedTexts: cleanedNames)
                    
                    // Apply matched students to attendance
                    var matchedStudentNames: [String] = []
                    
                    // Mark students present based on matched names
                    for (rollNumber, confidence) in matchResults {
                        if confidence >= self.confidenceThreshold {
                            self.attendanceStatus[rollNumber] = .present
                            if let student = self.students.first(where: { $0.rollNumber == rollNumber }) {
                                matchedStudentNames.append(student.name)
                                print("Student \(student.name) (roll number \(rollNumber)) marked PRESENT with confidence score: \(String(format: "%.2f", confidence * 100))%")
                            }
                        } else {
                            print("Name matched to roll number \(rollNumber) but kept as ABSENT due to low confidence score: \(String(format: "%.2f", confidence * 100))%")
                        }
                    }
                    
                    // Log if there's a detection mismatch
                    if self.hasDetectionMismatch {
                        print("WARNING: Detection mismatch detected. OpenAI extracted \(self.detectedNamesCount) names, but only matched \(matchedStudentNames.count) students.")
                    }
                    
                    // Post notification with matched students
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MatchedStudents"),
                        object: matchedStudentNames
                    )
                    
                    // Show processing completion
                    self.processingComplete = true
                    
                    // We're definitely updating records for this date now
                    self.isUpdatingExistingRecords = isUpdating
                    
                case .failure(let error):
                    print("OpenAI recognition error: \(error)")
                    
                    switch error {
                    case .apiKeyMissing:
                        self.errorMessage = "OpenAI API key is not set. Please add your API key in Settings."
                    case .imageEncodingFailed:
                        self.errorMessage = "Failed to process image. Please try another image."
                    case .networkError(let netError):
                        self.errorMessage = "Network error: \(netError.localizedDescription)"
                    case .invalidResponse:
                        self.errorMessage = "Invalid response from OpenAI. Please try again."
                    case .noNamesFound:
                        self.errorMessage = "No names were found in the image."
                    case .keychainError:
                        self.errorMessage = "Error accessing API key. Please re-enter your API key in Settings."
                    }
                    
                    self.processingComplete = true
                    
                    // Post notification about failure
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenAIProcessingFailed"),
                        object: self.errorMessage
                    )
                }
            }
        }
    }
    
    // Handle new image selection with proper state reset
    func handleNewImageSelection(_ newImage: UIImage?) {
        selectedImage = newImage
        
        if newImage != nil {
            // Reset processing state when a new image is selected
            isProcessing = false
            errorMessage = nil
            processingComplete = false
            showOpenAIOption = false
            useOpenAI = false
            detectedNamesCount = 0
            
            // Always reset all attendance statuses to absent when a new image is selected
            // This ensures any previous records don't interfere with the new image processing
            resetAllAttendanceToAbsent()
            
            // Check if we're updating existing records
            isUpdatingExistingRecords = dataManager.hasAttendanceRecords(for: attendanceDate)
            if isUpdatingExistingRecords {
                print("New image selected for date with existing records - status reset, existing records will be updated")
            }
        }
    }
    
    // Save attendance records to database
    func saveAttendance() {
        print("Creating attendance records for \(students.count) students for date: \(formatDate(attendanceDate))")
        
        let presentStudents = students.filter { 
            self.attendanceStatus[$0.rollNumber] == .present
        }
        print("Present students: \(presentStudents.count)")
        
        let absentStudents = students.filter { 
            self.attendanceStatus[$0.rollNumber] != .present
        }
        print("Absent students: \(absentStudents.count)")
        
        let records = students.map { student in
            let isPresent = attendanceStatus[student.rollNumber]?.isPresent ?? false
            print("Student: \(student.name), RollNumber: \(student.rollNumber), Present: \(isPresent)")
            
            return AttendanceRecord(
                date: attendanceDate,
                studentRollNumber: student.rollNumber,
                isPresent: isPresent
            )
        }
        
        // Force a UI update to provide visual feedback
        DispatchQueue.main.async {
            self.isUpdatingExistingRecords = true
        }
        
        // Save records to database
        dataManager.saveAttendanceRecords(records)
        
        // Since we don't have a completion closure anymore, simulate success
        DispatchQueue.main.async {
            self.saveSuccessful = true
            print("Successfully saved \(records.count) attendance records")
            
            // Auto-reset to prepare for next attendance session
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.saveSuccessful = false
            }
            
            // Post notification for successful save
            NotificationCenter.default.post(
                name: NSNotification.Name("AttendanceSaved"),
                object: nil
            )
        }
    }
    
    // Toggle a student's attendance status directly (manual override)
    func toggleAttendance(for rollNumber: String) {
        switch attendanceStatus[rollNumber] {
        case .present:
            attendanceStatus[rollNumber] = .absent
        case .absent, nil:
            attendanceStatus[rollNumber] = .present
        }
        
        print("Toggled attendance for student with roll number: \(rollNumber), now \(attendanceStatus[rollNumber]?.isPresent ?? false ? "Present" : "Absent")")
    }
    
    // Mark all students as present
    func markAllPresent() {
        for student in students {
            attendanceStatus[student.rollNumber] = .present
        }
        print("Marked all \(students.count) students as present")
    }
    
    // Mark all students as absent
    func markAllAbsent() {
        for student in students {
            attendanceStatus[student.rollNumber] = .absent
        }
        print("Marked all \(students.count) students as absent")
    }
    
    // Export attendance records to CSV
    func exportAttendance() -> URL? {
        return dataManager.saveCSVToFile()
    }
    
    // Set OpenAI enabled/disabled setting
    func setOpenAIEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: openAIEnabledKey)
    }
    
    // Process with OpenAI specifically for absent students only
    func processAbsentStudentsWithOpenAI() {
        guard let image = selectedImage else {
            errorMessage = "No image selected"
            return
        }
        
        // Check if API key is set before attempting to use OpenAI
        if !OpenAIService.shared.hasAPIKey() {
            errorMessage = "OpenAI API key is not set. Please add your API key in Settings."
            
            // Post notification about failure
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenAIProcessingFailed"),
                object: "OpenAI API key is not set. Please add your API key in Settings."
            )
            
            // Prompt to navigate to settings
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToSettings"),
                object: nil
            )
            
            return
        }
        
        isProcessing = true
        errorMessage = nil
        useOpenAI = true
        hasUsedOpenAI = true
        processingComplete = false
        
        // Get the list of currently absent students (without resetting attendance)
        let absentStudents = students.filter { 
            attendanceStatus[$0.rollNumber] != .present
        }
        
        let absentStudentNames = absentStudents.map { $0.name }
        print("Processing \(absentStudents.count) absent students with OpenAI")
        
        // Mark if we're updating existing records
        let isUpdating = dataManager.hasAttendanceRecords(for: attendanceDate)
        if isUpdating {
            print("Processing image with OpenAI for date with existing records - will preserve present students")
        }
        
        openAIService.recognizeNamesFromImage(image, absentStudents: absentStudentNames) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.useOpenAI = false
                
                switch result {
                case .success(let names):
                    print("OpenAI extracted names: \(names)")
                    
                    // Update detected names count for OpenAI (keep previous count since we're only processing absent)
                    // But at minimum, it should be the number of extracted names
                    if names.count > self.detectedNamesCount {
                        self.detectedNamesCount = names.count
                        print("OpenAI updated detected count to \(self.detectedNamesCount) names in the image")
                    }
                    
                    // Match names with students, but only consider the absent ones
                    let absentStudentRollNumbers = absentStudents.map { $0.rollNumber }
                    
                    var newlyFoundStudents: [String] = []
                    
                    for name in names {
                        // Clean up name by removing numbering and special characters
                        let cleanedName = StringMatching.cleanName(name)
                        
                        print("OpenAI: Cleaning name from '\(name)' to '\(cleanedName)'")
                        
                        if let bestMatch = StringMatching.findBestMatch(for: cleanedName, in: absentStudentNames) {
                            // Apply confidence threshold
                            if bestMatch.score >= self.confidenceThreshold {
                                // High confidence - mark present
                                if let student = self.students.first(where: { $0.name == bestMatch.string }) {
                                    if absentStudentRollNumbers.contains(student.rollNumber) {
                                        self.attendanceStatus[student.rollNumber] = .present
                                        newlyFoundStudents.append(student.name)
                                        print("OpenAI: Student \(student.name) (roll number \(student.rollNumber)) marked PRESENT with confidence score: \(String(format: "%.2f", bestMatch.score * 100))%")
                                    }
                                }
                            } else {
                                // Low confidence - log but keep as absent
                                print("OpenAI: Name '\(cleanedName)' best matched to '\(bestMatch.string)' but kept as ABSENT due to low confidence score: \(String(format: "%.2f", bestMatch.score * 100))%")
                            }
                        }
                    }
                    
                    // Log newly found students
                    if newlyFoundStudents.isEmpty {
                        print("OpenAI processing did not find any additional present students")
                    } else {
                        print("OpenAI found \(newlyFoundStudents.count) additional present students: \(newlyFoundStudents.joined(separator: ", "))")
                    }
                    
                    // Post notification with all present students
                    let presentStudentNames = self.students
                        .filter { self.attendanceStatus[$0.rollNumber] == .present }
                        .map { $0.name }
                    
                    print("Total students marked present after OpenAI processing: \(presentStudentNames.count)")
                    print("Total students still absent: \(self.students.count - presentStudentNames.count)")
                    
                    // Log if there's a detection mismatch
                    if self.hasDetectionMismatch {
                        print("WARNING: Detection mismatch detected. OpenAI extracted \(self.detectedNamesCount) names, but only matched \(presentStudentNames.count) students.")
                    }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MatchedStudents"),
                        object: presentStudentNames
                    )
                    
                    // Add feedback notification about completion
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenAIProcessingComplete"),
                        object: nil
                    )
                    
                    self.processingComplete = true
                    
                    // We're definitely updating records for this date now
                    self.isUpdatingExistingRecords = isUpdating
                    
                case .failure(let error):
                    print("OpenAI recognition error: \(error)")
                    
                    switch error {
                    case .apiKeyMissing:
                        self.errorMessage = "OpenAI API key is not set. Please add your API key in Settings."
                    case .imageEncodingFailed:
                        self.errorMessage = "Failed to process image. Please try another image."
                    case .networkError(let netError):
                        self.errorMessage = "Network error: \(netError.localizedDescription)"
                    case .invalidResponse:
                        self.errorMessage = "Invalid response from OpenAI. Please try again."
                    case .noNamesFound:
                        self.errorMessage = "No names were found in the image."
                    case .keychainError:
                        self.errorMessage = "Error accessing API key. Please re-enter your API key in Settings."
                    }
                    
                    self.processingComplete = true
                    
                    // Post notification about failure
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenAIProcessingFailed"),
                        object: self.errorMessage
                    )
                }
            }
        }
    }
} 