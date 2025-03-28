import SwiftUI
import UIKit

// Time period enum for filtering records
enum AttendanceTimePeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    
    var id: String { self.rawValue }
    
    // Calculate date range for the selected time period
    func dateRange(from currentDate: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: currentDate)
        
        let startDate: Date
        
        switch self {
        case .week:
            // Go back 7 days from current date
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .month:
            // Go back 1 month from current date
            startDate = calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .quarter:
            // Go back 3 months from current date
            startDate = calendar.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        case .year:
            // Go back 1 year from current date
            startDate = calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        }
        
        // For proper date comparison, set end date to the end of day
        let adjustedEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        
        return startDate...adjustedEndDate
    }
    
    // Get previous time period (for trend comparison)
    func previousPeriodRange(from currentDate: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: currentDate)
        
        let currentRange = dateRange(from: currentDate)
        let currentStartDate = currentRange.lowerBound
        
        // Calculate the difference between current end date and start date
        let components: Set<Calendar.Component> = [.day, .month, .year]
        let difference = calendar.dateComponents(components, from: currentStartDate, to: endDate)
        
        // Previous period end date is the day before current period start date
        let previousEndDate = calendar.date(byAdding: .day, value: -1, to: currentStartDate) ?? endDate
        
        // Start date is calculated by going back the same amount of time
        var previousStartDate: Date
        
        switch self {
        case .week:
            previousStartDate = calendar.date(byAdding: .day, value: -7, to: previousEndDate) ?? previousEndDate
        case .month:
            previousStartDate = calendar.date(byAdding: .month, value: -1, to: previousEndDate) ?? previousEndDate
        case .quarter:
            previousStartDate = calendar.date(byAdding: .month, value: -3, to: previousEndDate) ?? previousEndDate
        case .year:
            previousStartDate = calendar.date(byAdding: .year, value: -1, to: previousEndDate) ?? previousEndDate
        }
        
        return previousStartDate...previousEndDate
    }
}

struct AttendanceHistoryView: View {
    @State private var records: [AttendanceRecord] = []
    @State private var previousPeriodRecords: [AttendanceRecord] = []
    @State private var selectedDate = Date()
    @State private var csvURL: URL?
    @State private var showShareSheet = false
    @State private var isExporting = false
    @State private var exportError: String? = nil
    @State private var selectedTimePeriod: AttendanceTimePeriod = .month
    @State private var showStudentReport = false
    
    private let dataManager = DataManager.shared
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 0) {
            // Time period filter with improved visual design
            VStack(spacing: 0) {
                Picker("Time Period", selection: $selectedTimePeriod) {
                    ForEach(AttendanceTimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: selectedTimePeriod) { _ in
                loadAttendanceData()
            }
            
            // Summary section
            if !groupedByDate.isEmpty {
                AttendanceHistorySummary(
                    dateRange: selectedTimePeriod.dateRange(),
                    totalRecords: records.count,
                    presentCount: records.filter { $0.isPresent }.count,
                    studentsCount: calculateUniqueStudents(),
                    currentRate: calculateAttendanceRate(records: records),
                    previousRate: calculateAttendanceRate(records: previousPeriodRecords),
                    onTap: {
                        showStudentReport = true
                    }
                )
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            
            // Content list
            if groupedByDate.isEmpty {
                EmptyStateView(timePeriod: selectedTimePeriod.rawValue)
            } else {
                List {
                    ForEach(sortedDates, id: \.self) { dateString in
                        Section {
                            let dateRecords = groupedByDate[dateString] ?? []
                            
                            // Date header with stats
                            HStack {
                                Text(dateString)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                // Present/Absent counts for this date
                                HStack(spacing: 12) {
                                    Label("\(dateRecords.filter { $0.isPresent }.count)", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    
                                    Label("\(dateRecords.filter { !$0.isPresent }.count)", systemImage: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 8)
                            
                            // Students for this date
                            ForEach(studentsForDate(dateRecords), id: \.rollNumber) { student in
                                let isPresent = isPresentOnDate(student.rollNumber, dateRecords: dateRecords)
                                
                                StudentHistoryAttendanceRow(
                                    student: student,
                                    isPresent: isPresent
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let csvURL = csvURL {
                AttendanceShareSheet(items: [csvURL])
            }
        }
        .onAppear {
            // Load default time period from UserDefaults if available
            if let savedPeriod = UserDefaults.standard.string(forKey: "defaultTimePeriod"),
               let period = AttendanceTimePeriod.allCases.first(where: { $0.rawValue == savedPeriod }) {
                selectedTimePeriod = period
            }
            loadAttendanceData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimePreferenceChanged"))) { notification in
            if let period = notification.object as? AttendanceTimePeriod {
                selectedTimePeriod = period
                loadAttendanceData()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("History")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportAttendanceForSelectedPeriod) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(isExporting || groupedByDate.isEmpty)
            }
        }
        .overlay(
            Group {
                if let error = exportError {
                    VStack {
                        Spacer()
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                            .padding()
                            .onAppear {
                                // Auto-dismiss after 3 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        exportError = nil
                                    }
                                }
                            }
                    }
                }
            }
        )
        .background(
            NavigationLink(
                destination: StudentAttendanceReportView(
                    timePeriodName: selectedTimePeriod.rawValue,
                    dateRange: selectedTimePeriod.dateRange(),
                    records: records
                ),
                isActive: $showStudentReport
            ) {
                EmptyView()
            }
        )
    }
    
    private func loadAttendanceData() {
        // Load all records first
        let allRecords = dataManager.getAttendanceRecords()
        
        print("Retrieved \(allRecords.count) attendance records from UserDefaults")
        
        // Filter records based on selected time period
        let dateRange = selectedTimePeriod.dateRange()
        let previousRange = selectedTimePeriod.previousPeriodRange()
        
        // For debugging
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        print("Filtering for date range: \(formatter.string(from: dateRange.lowerBound)) to \(formatter.string(from: dateRange.upperBound))")
        print("Previous period range: \(formatter.string(from: previousRange.lowerBound)) to \(formatter.string(from: previousRange.upperBound))")
        
        records = allRecords.filter { record in
            // Normalize record date to start of day for proper comparison
            let recordDate = calendar.startOfDay(for: record.date)
            return recordDate >= calendar.startOfDay(for: dateRange.lowerBound) && 
                   recordDate <= calendar.endOfDay(for: dateRange.upperBound)
        }
        
        // Also load previous period records for trend comparison
        previousPeriodRecords = allRecords.filter { record in
            let recordDate = calendar.startOfDay(for: record.date)
            return recordDate >= calendar.startOfDay(for: previousRange.lowerBound) && 
                   recordDate <= calendar.endOfDay(for: previousRange.upperBound)
        }
        
        print("Loaded \(records.count) records for current period")
        print("Loaded \(previousPeriodRecords.count) records for previous period")
    }
    
    // Calculate unique students in the current records
    private func calculateUniqueStudents() -> Int {
        let uniqueRollNumbers = Set(records.map { $0.studentRollNumber })
        return uniqueRollNumbers.count
    }
    
    // Calculate attendance rate
    private func calculateAttendanceRate(records: [AttendanceRecord]) -> Double {
        guard !records.isEmpty else { return 0.0 }
        let presentCount = records.filter { $0.isPresent }.count
        return Double(presentCount) / Double(records.count)
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
    
    private func exportAttendanceForSelectedPeriod() {
        // Reset error state
        exportError = nil
        
        // Show exporting state
        isExporting = true
        
        // Use a small delay to show the loading indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let url = self.exportFilteredCSV() {
                self.csvURL = url
                self.isExporting = false
                self.showShareSheet = true
                print("CSV file for \(self.selectedTimePeriod.rawValue) created successfully at: \(url.path)")
            } else {
                self.isExporting = false
                self.exportError = "Failed to create CSV file. Please try again."
                print("Failed to create CSV file")
            }
        }
    }
    
    private func exportFilteredCSV() -> URL? {
        let dateRange = selectedTimePeriod.dateRange()
        return dataManager.saveCSVToFile(filterByDateRange: dateRange)
    }
}

// Updated summary component with optimized space usage
struct AttendanceHistorySummary: View {
    let dateRange: ClosedRange<Date>
    let totalRecords: Int
    let presentCount: Int
    let studentsCount: Int
    let currentRate: Double
    let previousRate: Double
    var onTap: () -> Void
    
    @State private var showInfoTooltip = false
    private let iconColor: Color = .blue
    
    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: dateRange.lowerBound)) - \(formatter.string(from: dateRange.upperBound))"
    }
    
    private var rateTrend: Double {
        return currentRate - previousRate
    }
    
    private var trendIcon: String {
        if abs(rateTrend) < 0.01 { // Less than 1% change is considered stable
            return "arrow.left.and.right"
        } else if rateTrend > 0 {
            return "chart.line.uptrend.xyaxis"
        } else {
            return "chart.line.downtrend.xyaxis"
        }
    }
    
    private var trendColor: Color {
        if abs(rateTrend) < 0.01 {
            return .gray
        } else if rateTrend > 0 {
            return .green
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Integrated header with date range
            HStack(alignment: .firstTextBaseline) {
                Text("Summary")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("·")
                    .foregroundColor(.secondary)
                
                Text(dateRangeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Info button with explanation (moved next to date range)
                Button(action: {
                    showInfoTooltip.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(iconColor)
                        .font(.system(size: 14))
                }
                
                Spacer()
                
                // Student stats navigation arrow (where info button was)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)
            
            // Metrics in a compact row with minimal spacing
            VStack(spacing: showInfoTooltip ? 12 : 0) {
                HStack(spacing: 0) {
                    // Students info
                    VStack(spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "person.3")
                                .font(.system(size: 14))
                                .foregroundColor(iconColor)
                                .frame(width: 18)
                            
                            Text("\(studentsCount)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        if showInfoTooltip {
                            Text("Number\nof students")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Attendance rate - consistent icon color
                    VStack(spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14))
                                .foregroundColor(iconColor)
                                .frame(width: 18)
                            
                            Text(String(format: "%.0f%%", currentRate * 100))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        if showInfoTooltip {
                            Text("Attendance\nrate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Trend comparison with blue icon but color-coded text
                    VStack(spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: trendIcon)
                                .font(.system(size: 14))
                                .foregroundColor(iconColor)
                                .frame(width: 18)
                            
                            if abs(rateTrend) < 0.01 {
                                Text("—")
                                    .font(.system(size: 16))
                                    .foregroundColor(trendColor)
                            } else {
                                Text(String(format: "%.1f%%", abs(rateTrend * 100)))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(trendColor)
                            }
                        }
                        
                        if showInfoTooltip {
                            Text("vs previous\nperiod")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemGroupedBackground).opacity(0.6))
            .cornerRadius(8)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle()) // Make the entire card tappable
        .onTapGesture {
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: showInfoTooltip)
    }
}

// Reusable metric view component
struct MetricView: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var footnote: String? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12))
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            
            if let footnote = footnote {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, -4)
            }
        }
    }
}

// Improved student history row that matches the style of the Current Session view
struct StudentHistoryAttendanceRow: View {
    let student: Student
    let isPresent: Bool
    
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
            
            // Non-editable radio button similar to StudentAttendanceRow
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                
                if isPresent {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Original StudentHistoryRow (keep for backward compatibility)
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
            
            // Make it clear this is a status indicator, not a button
            HStack(spacing: 6) {
                Image(systemName: isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isPresent ? .green : .red)
                
                Text(isPresent ? "Present" : "Absent")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(isPresent ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isPresent ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }
}

// New component for empty state
struct EmptyStateView: View {
    let timePeriod: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 70))
                .foregroundColor(Color(.systemGray3))
            
            Text("No Attendance Records")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("No attendance data found for the past \(timePeriod.lowercased())")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToUploadAttendance"),
                    object: nil
                )
            }) {
                Label("Take Attendance", systemImage: "camera")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// Enhanced ShareSheet implementation
struct AttendanceShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Exclude certain activities if needed
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList
        ]
        
        // Add completion handler
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            if let error = error {
                print("Share sheet error: \(error.localizedDescription)")
                return
            }
            
            if completed {
                print("Share completed for activity: \(activityType?.rawValue ?? "unknown")")
            } else {
                print("Share canceled")
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

// Helper extension for getting end of day
private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        return self.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}

#Preview {
    NavigationView {
        AttendanceHistoryView()
    }
}

// MARK: - Student Attendance Report View

// Model to hold individual student attendance data
struct StudentAttendanceReport: Identifiable {
    let id: String
    let name: String
    let rollNumber: String
    let totalDays: Int
    let presentDays: Int
    
    var absentDays: Int {
        return totalDays - presentDays
    }
    
    var attendanceRate: Double {
        return totalDays > 0 ? Double(presentDays) / Double(totalDays) : 0
    }
    
    var absenceRate: Double {
        return totalDays > 0 ? Double(absentDays) / Double(totalDays) : 0
    }
}

// Sort options for the student list
enum StudentSortOption: String, CaseIterable, Identifiable {
    case mostAbsent = "Most Absent"
    case mostPresent = "Most Present" 
    case name = "Name"
    case rollNumber = "Roll Number"
    
    var id: String { self.rawValue }
}

struct StudentAttendanceReportView: View {
    let timePeriodName: String
    let dateRange: ClosedRange<Date>
    let records: [AttendanceRecord]
    
    @State private var searchText = ""
    @State private var sortOption: StudentSortOption = .mostAbsent
    @State private var studentReports: [StudentAttendanceReport] = []
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var csvURL: URL?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var prepareKeyboard = false
    
    private let dataManager = DataManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with date range and controls
            HStack(alignment: .center) {
                // Date range
                Text(dateRangeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // CSV Export button
                Button(action: exportAttendanceReport) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                }
                .disabled(isExporting || studentReports.isEmpty)
                .padding(.horizontal, 4)
                
                // Sort menu (icon only)
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(StudentSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            
            // Search field as a separate component
            SearchFieldView(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
                .id("searchField") // Ensure consistent identity
            
            ZStack {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading student data...")
                        Spacer()
                    }
                } else if filteredReports.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        if !searchText.isEmpty {
                            Text("No students match your search")
                                .font(.headline)
                            
                            Button("Clear Search") {
                                searchText = ""
                                isSearchFieldFocused = false
                            }
                            .padding(.top, 8)
                        } else {
                            Text("No attendance data for this period")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    // Student list with simplified scroll view
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredReports) { report in
                                StudentReportRow(report: report)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                                    .padding(.horizontal, 16)
                                    .onTapGesture {
                                        // Dismiss keyboard when tapping on rows
                                        isSearchFieldFocused = false
                                    }
                            }
                            
                            // Footer space
                            Color.clear
                                .frame(height: 20)
                        }
                        .padding(.top, 8)
                    }
                    .simultaneousGesture(DragGesture().onChanged { _ in
                        // Dismiss keyboard when scrolling
                        isSearchFieldFocused = false
                    })
                }
            }
            .background(Color(.systemGroupedBackground))
            .onTapGesture {
                // Dismiss keyboard when tapping background
                isSearchFieldFocused = false
            }
            
            // Hidden keyboard prewarmer (will briefly show/hide keyboard on appear)
            if prepareKeyboard {
                KeyboardPrewarmer(isActive: $prepareKeyboard)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Report")
        .sheet(isPresented: $showShareSheet) {
            if let csvURL = csvURL {
                AttendanceShareSheet(items: [csvURL])
            }
        }
        .onAppear {
            loadStudentReports()
            
            // Pre-warm the keyboard after a short delay when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                prepareKeyboard = true
            }
        }
        .onChange(of: sortOption) { _ in
            sortStudentReports()
        }
    }
    
    // Date formatting for header
    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: dateRange.lowerBound)) to \(formatter.string(from: dateRange.upperBound))"
    }
    
    // Export student attendance report as CSV
    private func exportAttendanceReport() {
        // Reset state
        isExporting = true
        
        // Convert student reports to dictionaries
        let reportData = filteredReports.map { report -> [String: Any] in
            return [
                "name": report.name,
                "rollNumber": report.rollNumber,
                "presentDays": report.presentDays,
                "totalDays": report.totalDays,
                "attendanceRate": report.attendanceRate
            ]
        }
        
        // Use a small delay to show the loading indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let url = dataManager.saveStudentReportCSV(reportData: reportData, dateRange: self.dateRange) {
                self.csvURL = url
                self.isExporting = false
                self.showShareSheet = true
                print("CSV file for student report created successfully at: \(url.path)")
            } else {
                self.isExporting = false
                print("Failed to create CSV file for student report")
            }
        }
    }
    
    // Filter reports based on search text
    private var filteredReports: [StudentAttendanceReport] {
        if searchText.isEmpty {
            return studentReports
        } else {
            return studentReports.filter { report in
                report.name.lowercased().contains(searchText.lowercased()) ||
                report.rollNumber.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    // Process attendance records into student reports
    private func loadStudentReports() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let students = dataManager.getStudents()
            let uniqueDates = getUniqueDates(from: records)
            var reports: [StudentAttendanceReport] = []
            
            for student in students {
                // Get all records for this student
                let studentRecords = records.filter { $0.studentRollNumber == student.rollNumber }
                let totalDays = uniqueDates.count // Count unique days
                let presentDays = studentRecords.filter { $0.isPresent }.count
                
                let report = StudentAttendanceReport(
                    id: student.rollNumber,
                    name: student.name,
                    rollNumber: student.rollNumber,
                    totalDays: totalDays,
                    presentDays: presentDays
                )
                
                reports.append(report)
            }
            
            DispatchQueue.main.async {
                self.studentReports = reports
                self.sortStudentReports()
                self.isLoading = false
            }
        }
    }
    
    // Sort reports based on selected option
    private func sortStudentReports() {
        switch sortOption {
        case .mostAbsent:
            studentReports.sort { $0.absenceRate > $1.absenceRate }
        case .mostPresent:
            studentReports.sort { $0.attendanceRate > $1.attendanceRate }
        case .name:
            studentReports.sort { $0.name < $1.name }
        case .rollNumber:
            studentReports.sort { $0.rollNumber < $1.rollNumber }
        }
    }
    
    // Extract unique dates from attendance records
    private func getUniqueDates(from records: [AttendanceRecord]) -> Set<Date> {
        let calendar = Calendar.current
        let dates = records.map { calendar.startOfDay(for: $0.date) }
        return Set(dates)
    }
}

// Optimized search field component
struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search students", text: $searchText)
                .focused($isSearchFieldFocused)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .accessibilityIdentifier("studentSearchField")
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    // Keep focus on search field after clearing
                    isSearchFieldFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

// Keyboard pre-warmer component
struct KeyboardPrewarmer: View {
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool
    @State private var dummyText = ""
    
    var body: some View {
        TextField("", text: $dummyText)
            .focused($isFocused)
            .opacity(0)
            .frame(width: 1, height: 1)
            .onAppear {
                // Focus and then quickly unfocus to prep the keyboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isFocused = false
                        
                        // Notify parent that prewarming is complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isActive = false
                        }
                    }
                }
            }
    }
}

// Row component for each student
struct StudentReportRow: View {
    let report: StudentAttendanceReport
    
    @State private var isExpanded = false
    
    private var attendanceColor: Color {
        if report.attendanceRate >= 0.9 {
            return .green
        } else if report.attendanceRate >= 0.75 {
            return .yellow
        } else if report.attendanceRate >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            // Student info - always visible (simplified in collapsed state)
            HStack {
                // Name only when collapsed
                Text(report.name)
                    .font(.headline)
                
                Spacer()
                
                // Simple percentage text, right-aligned
                Text("\(Int(report.attendanceRate * 100))%")
                    .font(.system(size: 16, weight: .semibold))
                
                // Small chevron indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            .padding(.vertical, 8)
            
            // Additional details - only visible when expanded
            if isExpanded {
                // Roll number
                Text("Roll No: \(report.rollNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                // Attendance metrics
                HStack(spacing: 12) {
                    // Present days
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            
                            Text("\(report.presentDays)")
                                .font(.system(size: 15, weight: .medium))
                        }
                        
                        Text("Present")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Absent days
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                            
                            Text("\(report.absentDays)")
                                .font(.system(size: 15, weight: .medium))
                        }
                        
                        Text("Absent")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Total days
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                                .font(.system(size: 12))
                            
                            Text("\(report.totalDays)")
                                .font(.system(size: 15, weight: .medium))
                        }
                        
                        Text("Total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle()) // Make the entire card tappable
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
    }
} 