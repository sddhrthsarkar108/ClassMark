import SwiftUI
import UIKit

struct AttendanceHistoryView: View {
    @State private var records: [AttendanceRecord] = []
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .list
    @State private var showDatePicker = false
    @State private var csvURL: URL?
    @State private var showShareSheet = false
    
    private let dataManager = DataManager.shared
    private let calendar = Calendar.current
    
    enum ViewMode {
        case calendar
        case list
    }
    
    var body: some View {
        VStack {
            // Simple list view of dates with records
            List {
                if groupedByDate.isEmpty {
                    Section {
                        Text("No attendance records found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                } else {
                    ForEach(sortedDates, id: \.self) { dateString in
                        Section(header: Text(dateString)) {
                            let dateRecords = groupedByDate[dateString] ?? []
                            ForEach(studentsForDate(dateRecords), id: \.rollNumber) { student in
                                let isPresent = isPresentOnDate(student.rollNumber, dateRecords: dateRecords)
                                
                                StudentHistoryRow(
                                    student: student,
                                    isPresent: isPresent
                                )
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: exportAttendanceForDate) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Attendance as CSV")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let csvURL = csvURL {
                // Use our locally defined ShareSheet
                AttendanceShareSheet(items: [csvURL])
            }
        }
        .onAppear(perform: loadAttendanceData)
        .navigationTitle("Attendance History")
    }
    
    private func loadAttendanceData() {
        // Load all records
        records = dataManager.getAttendanceRecords()
    }
    
    // Group records by date for list view
    private var groupedByDate: [String: [AttendanceRecord]] {
        Dictionary(grouping: records) { record -> String in
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            return dateFormatter.string(from: record.date)
        }
    }
    
    private var sortedDates: [String] {
        groupedByDate.keys.sorted(by: >)
    }
    
    private func studentsForDate(_ dateRecords: [AttendanceRecord]) -> [Student] {
        let students = dataManager.getStudents()
        let rollNumbers = dateRecords.map { $0.studentRollNumber }
        return students.filter { rollNumbers.contains($0.rollNumber) }
    }
    
    private func isPresentOnDate(_ rollNumber: String, dateRecords: [AttendanceRecord]) -> Bool {
        return dateRecords.first { $0.studentRollNumber == rollNumber }?.isPresent ?? false
    }
    
    private func getRecordsForSelectedDate() -> [AttendanceRecord] {
        records.filter { record in
            calendar.isDate(record.date, inSameDayAs: selectedDate)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }
    
    private func exportAttendanceForDate() {
        if let url = dataManager.saveCSVToFile() {
            self.csvURL = url
            self.showShareSheet = true
        }
    }
}

struct StudentHistoryRow: View {
    let student: Student
    let isPresent: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.headline)
                Text("Roll No: \(student.rollNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(isPresent ? "Present" : "Absent")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isPresent ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .foregroundColor(isPresent ? .green : .red)
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// Local implementation of ShareSheet
struct AttendanceShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

#Preview {
    NavigationView {
        AttendanceHistoryView()
    }
} 