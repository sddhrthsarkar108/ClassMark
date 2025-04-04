import Foundation

class DataManager {
    static let shared = DataManager()
    
    private let studentsKey = "students"
    private let attendanceRecordsKey = "attendanceRecords"
    
    private init() {
        // Initialize with sample data if nothing exists
        if getStudents().isEmpty {
            loadStudentsFromJSON()
        }
    }
    
    // MARK: - Student Management
    
    private func loadStudentsFromJSON() {
        if let path = Bundle.main.path(forResource: "students", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let students = try JSONDecoder().decode([Student].self, from: data)
                saveStudents(students)
                print("Loaded \(students.count) students from JSON file")
            } catch {
                print("Error loading students from JSON: \(error)")
                // Fallback to sample data if JSON loading fails
                saveStudents(Student.sampleData)
            }
        } else {
            print("Students JSON file not found, using sample data")
            saveStudents(Student.sampleData)
        }
    }
    
    func getStudents() -> [Student] {
        guard let data = UserDefaults.standard.data(forKey: studentsKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([Student].self, from: data)
        } catch {
            print("Error decoding students: \(error)")
            return []
        }
    }
    
    func saveStudents(_ students: [Student]) {
        do {
            let data = try JSONEncoder().encode(students)
            UserDefaults.standard.set(data, forKey: studentsKey)
        } catch {
            print("Error encoding students: \(error)")
        }
    }
    
    // MARK: - Attendance Management
    
    // Clear all attendance records - for debugging purposes
    func clearAllAttendanceRecords() {
        print("DataManager: Clearing all attendance records from UserDefaults")
        UserDefaults.standard.removeObject(forKey: attendanceRecordsKey)
        UserDefaults.standard.synchronize()
        print("DataManager: All attendance records have been cleared")
    }
    
    func getAttendanceRecords() -> [AttendanceRecord] {
        guard let data = UserDefaults.standard.data(forKey: attendanceRecordsKey) else {
            print("No attendance records found in UserDefaults")
            return []
        }
        
        do {
            let records = try JSONDecoder().decode([AttendanceRecord].self, from: data)
            print("Retrieved \(records.count) attendance records from UserDefaults")
            return records
        } catch {
            print("Error decoding attendance records: \(error)")
            return []
        }
    }
    
    func saveAttendanceRecords(_ records: [AttendanceRecord]) {
        print("DataManager: Saving \(records.count) new attendance records")
        
        // Get existing records
        var existingRecords = getAttendanceRecords()
        print("DataManager: Found \(existingRecords.count) existing records")
        
        // Group records by date for better logging
        let calendar = Calendar.current
        let newRecordsByDate = Dictionary(grouping: records) { record -> String in
            return getDateString(from: record.date)
        }
        
        // Get the unique dates being updated
        let updatingDates = Set(records.map { calendar.startOfDay(for: $0.date) })
        print("DataManager: Updating records for dates: \(updatingDates.map { getDateString(from: $0) })")
        
        // Keep records for dates not being updated
        let recordsToKeep = existingRecords.filter { record in
            !updatingDates.contains(calendar.startOfDay(for: record.date))
        }
        print("DataManager: Keeping \(recordsToKeep.count) records that are for other dates")
        
        // Add the new/updated records
        let finalRecords = recordsToKeep + records
        print("DataManager: Final record count: \(finalRecords.count)")
        
        // Keep only the last 30 days of records
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let filteredRecords = finalRecords.filter { $0.date >= thirtyDaysAgo }
        print("DataManager: After filtering for last 30 days, keeping \(filteredRecords.count) records")
        
        do {
            let data = try JSONEncoder().encode(filteredRecords)
            print("DataManager: Successfully encoded records, saving to UserDefaults")
            UserDefaults.standard.set(data, forKey: attendanceRecordsKey)
            
            // Force synchronize to ensure data is saved immediately
            UserDefaults.standard.synchronize()
            print("DataManager: UserDefaults synchronized")
            
            // Verify records were properly saved
            let savedRecords = getAttendanceRecords()
            print("DataManager: Verified \(savedRecords.count) total records saved")
            
            // Verify each updated date
            for date in updatingDates {
                let dateRecords = savedRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
                print("DataManager: Verified \(dateRecords.count) records for date \(getDateString(from: date))")
            }
            
        } catch {
            print("Error encoding attendance records: \(error)")
        }
    }
    
    func getAttendanceForDate(_ date: Date) -> [AttendanceRecord] {
        let records = getAttendanceRecords()
        let calendar = Calendar.current
        
        let filteredRecords = records.filter { record in
            calendar.isDate(record.date, inSameDayAs: date)
        }
        
        print("Found \(filteredRecords.count) records for date \(getDateString(from: date))")
        return filteredRecords
    }
    
    // Get dates that have attendance records within a range
    func getDatesWithRecords(in range: ClosedRange<Date>) -> [Date] {
        let records = getAttendanceRecords()
        let calendar = Calendar.current
        
        // Group records by date
        let recordsByDate = Dictionary(grouping: records) { record -> Date in
            return calendar.startOfDay(for: record.date)
        }
        
        // Filter dates within the range
        return recordsByDate.keys.filter { date in
            date >= range.lowerBound && date <= range.upperBound
        }.sorted()
    }
    
    // Get attendance records within a date range
    func getAttendanceRecordsInRange(_ range: ClosedRange<Date>) -> [AttendanceRecord] {
        let records = getAttendanceRecords()
        
        return records.filter { record in
            let date = record.date
            return date >= range.lowerBound && date <= range.upperBound
        }
    }
    
    // Check if a date has attendance records
    func hasAttendanceRecords(for date: Date) -> Bool {
        let records = getAttendanceForDate(date)
        return !records.isEmpty
    }
    
    // MARK: - Utility Methods
    
    private func getDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func exportAttendanceAsCSV(filterByDateRange dateRange: ClosedRange<Date>? = nil) -> String {
        let records: [AttendanceRecord]
        
        // If date range is provided, filter the records
        if let range = dateRange {
            records = getAttendanceRecords().filter { record in
                return record.date >= range.lowerBound && record.date <= range.upperBound
            }
            print("Exporting CSV for date range: \(getDateString(from: range.lowerBound)) to \(getDateString(from: range.upperBound))")
        } else {
            records = getAttendanceRecords()
            print("Exporting CSV for all records")
        }
        
        let students = getStudents()
        
        // Create a dictionary for faster student lookup
        let studentDict = Dictionary(uniqueKeysWithValues: students.map { ($0.rollNumber, $0.name) })
        
        // Group records by date
        let groupedByDate = Dictionary(grouping: records) { record -> String in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return dateFormatter.string(from: record.date)
        }
        
        // Create CSV header
        var csv = "Name,Roll Number"
        
        // Add dates to header
        let sortedDates = groupedByDate.keys.sorted()
        for dateStr in sortedDates {
            csv += ",\(dateStr)"
        }
        csv += "\n"
        
        // Add data for each student
        for student in students {
            csv += "\(student.name),\(student.rollNumber)"
            
            for dateStr in sortedDates {
                let dateRecords = groupedByDate[dateStr] ?? []
                let studentRecord = dateRecords.first { $0.studentRollNumber == student.rollNumber }
                let status = studentRecord?.isPresent == true ? "Present" : "Absent"
                csv += ",\(status)"
            }
            csv += "\n"
        }
        
        return csv
    }
    
    // Export student attendance report summary as CSV
    func exportStudentReportAsCSV(reportData: [[String: Any]], dateRange: ClosedRange<Date>) -> String {
        // Get formatted date range for the report header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let startDateStr = dateFormatter.string(from: dateRange.lowerBound)
        let endDateStr = dateFormatter.string(from: dateRange.upperBound)
        
        // Create CSV header with metadata
        var csv = "Student Attendance Report\n"
        csv += "Period:,\(startDateStr) to \(endDateStr)\n"
        csv += "Generated:,\(dateFormatter.string(from: Date()))\n\n"
        
        // Column headers
        csv += "Name,Roll Number,Present Days,Absent Days,Total Days,Attendance Rate (%)\n"
        
        // Add data for each student report
        for report in reportData {
            guard 
                let name = report["name"] as? String,
                let rollNumber = report["rollNumber"] as? String,
                let presentDays = report["presentDays"] as? Int,
                let totalDays = report["totalDays"] as? Int,
                let attendanceRate = report["attendanceRate"] as? Double
            else { continue }
            
            let absentDays = totalDays - presentDays
            let attendancePercentage = Int(attendanceRate * 100)
            
            csv += "\(name),"
            csv += "\(rollNumber),"
            csv += "\(presentDays),"
            csv += "\(absentDays),"
            csv += "\(totalDays),"
            csv += "\(attendancePercentage)\n"
        }
        
        return csv
    }
    
    func saveCSVToFile(filterByDateRange dateRange: ClosedRange<Date>? = nil) -> URL? {
        let csv = exportAttendanceAsCSV(filterByDateRange: dateRange)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "attendance_\(dateFormatter.string(from: Date())).csv"
        
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentDirectory.appendingPathComponent(filename)
        
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving CSV: \(error)")
            return nil
        }
    }
    
    // Save student report CSV to file
    func saveStudentReportCSV(reportData: [[String: Any]], dateRange: ClosedRange<Date>) -> URL? {
        let csv = exportStudentReportAsCSV(reportData: reportData, dateRange: dateRange)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "student_report_\(dateFormatter.string(from: Date())).csv"
        
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentDirectory.appendingPathComponent(filename)
        
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving student report CSV: \(error)")
            return nil
        }
    }
} 
