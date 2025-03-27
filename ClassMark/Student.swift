import Foundation

struct Student: Identifiable, Codable, Equatable {
    var id: String { rollNumber }
    let name: String
    let rollNumber: String
    
    static func == (lhs: Student, rhs: Student) -> Bool {
        return lhs.rollNumber == rhs.rollNumber
    }
}

// Sample data for testing
extension Student {
    static let sampleData: [Student] = [
        Student(name: "John Doe", rollNumber: "101"),
        Student(name: "Jane Smith", rollNumber: "102"),
        Student(name: "Bob Johnson", rollNumber: "103"),
        Student(name: "Emily Davis", rollNumber: "104"),
        Student(name: "Michael White", rollNumber: "105")
    ]
} 