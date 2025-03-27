import Foundation
import SwiftUI
import Combine

class AttendanceViewModel: ObservableObject {
    @Published var students: [Student] = []
    @Published var attendanceDate: Date = Date()
    @Published var attendanceStatus: [String: Bool] = [:]
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var selectedImage: UIImage?
    @Published var showOpenAIOption: Bool = false
    @Published var useOpenAI: Bool = false
    @Published var processingComplete: Bool = false
    @Published var saveSuccessful: Bool = false
    @Published var isUpdatingExistingRecords: Bool = false
    
    private var dataManager = DataManager.shared
    private var textRecognitionService = TextRecognitionService.shared
    private var openAIService = OpenAIService.shared
    // Don't use CalendarHelper at this point
    private var calendarHelper: Any? = nil
    
    init() {
        loadStudents()
        resetAttendance()
        checkExistingRecords()
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
                    attendanceStatus[record.studentRollNumber] = record.isPresent
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // Reset all state for a fresh attendance session
    func resetAttendance() {
        // Reset attendance statuses to all absent
        attendanceStatus = Dictionary(uniqueKeysWithValues: students.map { ($0.rollNumber, false) })
        
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
        
        textRecognitionService.recognizeText(from: image) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let extractedText):
                    print("Extracted text: \(extractedText)")
                    let matchResult = self.textRecognitionService.matchNamesWithStudents(extractedTexts: extractedText)
                    
                    // Update attendance status
                    for (rollNumber, confidence) in matchResult {
                        self.attendanceStatus[rollNumber] = true
                    }
                    
                    // Post notification with matched students
                    let presentStudentNames = self.students
                        .filter { self.attendanceStatus[$0.rollNumber] == true }
                        .map { $0.name }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MatchedStudents"),
                        object: presentStudentNames
                    )
                    
                    self.processingComplete = !self.showOpenAIOption
                    
                    // Check if we should suggest using OpenAI
                    self.showOpenAIOption = self.textRecognitionService.shouldUseFallback(matchResult: matchResult)
                    
                    // Check if we're updating existing records
                    self.checkExistingRecordsForDate(self.attendanceDate)
                    
                case .failure(let error):
                    print("Text recognition error: \(error)")
                    self.errorMessage = "Failed to recognize text: \(error)"
                    self.showOpenAIOption = true
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
        
        isProcessing = true
        errorMessage = nil
        useOpenAI = true
        processingComplete = false
        
        openAIService.recognizeNamesFromImage(image) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let names):
                    print("OpenAI extracted names: \(names)")
                    
                    // Match names with students
                    let studentNames = self.students.map { $0.name }
                    
                    for name in names {
                        if let bestMatch = StringMatching.findBestMatch(for: name, in: studentNames),
                           bestMatch.score > 0.6,
                           let student = self.students.first(where: { $0.name == bestMatch.string }) {
                            self.attendanceStatus[student.rollNumber] = true
                        }
                    }
                    
                    self.processingComplete = true
                    
                    // Post notification with matched students from OpenAI
                    let presentStudentNames = self.students
                        .filter { self.attendanceStatus[$0.rollNumber] == true }
                        .map { $0.name }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MatchedStudents"),
                        object: presentStudentNames
                    )
                    
                    // Check if we're updating existing records
                    self.checkExistingRecordsForDate(self.attendanceDate)
                    
                case .failure(let error):
                    print("OpenAI error: \(error)")
                    self.errorMessage = "Failed to recognize names with OpenAI: \(error)"
                }
                
                self.useOpenAI = false
            }
        }
    }
    
    // Save attendance records
    func saveAttendance() {
        print("Creating attendance records for \(students.count) students for date: \(formatDate(attendanceDate))")
        
        let presentStudents = students.filter { attendanceStatus[$0.rollNumber] == true }
        print("Present students: \(presentStudents.count)")
        
        let absentStudents = students.filter { attendanceStatus[$0.rollNumber] == false }
        print("Absent students: \(absentStudents.count)")
        
        let records = students.map { student in
            let isPresent = attendanceStatus[student.rollNumber] ?? false
            print("Student: \(student.name), RollNumber: \(student.rollNumber), Present: \(isPresent)")
            
            return AttendanceRecord(
                date: attendanceDate,
                studentRollNumber: student.rollNumber,
                isPresent: isPresent
            )
        }
        
        // Force a UI update to provide visual feedback
        DispatchQueue.main.async {
            // Save the records
            self.dataManager.saveAttendanceRecords(records)
            print("Saved \(records.count) attendance records")
            
            // Check if we updated existing records
            let operationType = self.isUpdatingExistingRecords ? "updated" : "created"
            print("Successfully \(operationType) attendance records for \(self.formatDate(self.attendanceDate))")
            
            // Verify records were saved
            let savedRecords = self.dataManager.getAttendanceForDate(self.attendanceDate)
            print("Verified \(savedRecords.count) records for \(self.formatDate(self.attendanceDate))")
            
            // Set save successful flag
            self.saveSuccessful = true
            
            // Make sure we know we're updating records next time
            self.isUpdatingExistingRecords = true
            
            // Post notification that save was successful
            NotificationCenter.default.post(
                name: NSNotification.Name("AttendanceSaved"),
                object: [
                    "count": records.count,
                    "isUpdate": self.isUpdatingExistingRecords,
                    "date": self.attendanceDate
                ]
            )
            
            // Add a small delay and reset the flag
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.saveSuccessful = false
            }
        }
    }
    
    // Toggle attendance for a student manually
    func toggleAttendance(for rollNumber: String) {
        attendanceStatus[rollNumber]?.toggle()
        print("Toggled attendance for student with roll number: \(rollNumber), now \(attendanceStatus[rollNumber] ?? false ? "Present" : "Absent")")
    }
    
    // Mark all students as present
    func markAllPresent() {
        for student in students {
            attendanceStatus[student.rollNumber] = true
        }
        print("Marked all \(students.count) students as present")
    }
    
    // Mark all students as absent
    func markAllAbsent() {
        for student in students {
            attendanceStatus[student.rollNumber] = false
        }
        print("Marked all \(students.count) students as absent")
    }
    
    // Export attendance records to CSV
    func exportAttendance() -> URL? {
        return dataManager.saveCSVToFile()
    }
} 