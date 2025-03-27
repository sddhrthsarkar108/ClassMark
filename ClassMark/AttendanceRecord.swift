import Foundation

struct AttendanceRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let studentRollNumber: String
    let isPresent: Bool
    
    init(id: UUID = UUID(), date: Date, studentRollNumber: String, isPresent: Bool) {
        self.id = id
        self.date = date
        self.studentRollNumber = studentRollNumber
        self.isPresent = isPresent
    }
}

// For convenience
extension AttendanceRecord {
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    static func createRecordsForDate(_ date: Date = Date(), students: [Student], presentRollNumbers: [String]) -> [AttendanceRecord] {
        return students.map { student in
            AttendanceRecord(
                date: date,
                studentRollNumber: student.rollNumber,
                isPresent: presentRollNumbers.contains(student.rollNumber)
            )
        }
    }
} 