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
        
        // Check for duplicates (same student, same date)
        let newRecordsSet = Set(records.map { record -> String in
            let dateStr = getDateString(from: record.date)
            return "\(record.studentRollNumber)-\(dateStr)"
        })
        
        // Filter out existing records that would be duplicates
        existingRecords = existingRecords.filter { record -> Bool in
            let dateStr = getDateString(from: record.date)
            let key = "\(record.studentRollNumber)-\(dateStr)"
            return !newRecordsSet.contains(key)
        }
        
        print("DataManager: After removing potential duplicates, keeping \(existingRecords.count) existing records")
        
        // Add new records
        existingRecords.append(contentsOf: records)
        print("DataManager: Total records after adding new ones: \(existingRecords.count)")
        
        // Keep only the last 30 days of records (updated from 7 days)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let filteredRecords = existingRecords.filter { $0.date >= thirtyDaysAgo }
        print("DataManager: After filtering for last 30 days, keeping \(filteredRecords.count) records")
        
        do {
            let data = try JSONEncoder().encode(filteredRecords)
            print("DataManager: Successfully encoded records, saving to UserDefaults")
            UserDefaults.standard.set(data, forKey: attendanceRecordsKey)
            
            // Force synchronize to ensure data is saved immediately
            UserDefaults.standard.synchronize()
            print("DataManager: UserDefaults synchronized")
            
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
    
    func exportAttendanceAsCSV() -> String {
        let records = getAttendanceRecords()
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
    
    func saveCSVToFile() -> URL? {
        let csv = exportAttendanceAsCSV()
        
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
} 
