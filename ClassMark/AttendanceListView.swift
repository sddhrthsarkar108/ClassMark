import SwiftUI

struct AttendanceListView: View {
    @ObservedObject var viewModel: AttendanceViewModel
    @State private var showingSaveConfirmation = false
    @State private var saveButtonTapped = false
    @State private var showingCompletionOptions = false
    
    var body: some View {
        List {
            Section(header: Text("Date: \(formattedDate)")) {
                // Show a note if we're updating existing records
                if viewModel.isUpdatingExistingRecords {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("You are updating today's existing attendance records")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }
                
                ForEach(viewModel.students) { student in
                    StudentAttendanceRow(
                        student: student,
                        isPresent: viewModel.attendanceStatus[student.rollNumber] ?? false
                    ) {
                        viewModel.toggleAttendance(for: student.rollNumber)
                    }
                }
            }
            
            Section {
                HStack {
                    Button(action: viewModel.markAllPresent) {
                        Text("Mark All Present")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: viewModel.markAllAbsent) {
                        Text("Mark All Absent")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
                    
                    // Show completion options dialog
                    showingCompletionOptions = true
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
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Attendance")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    print("Navigation bar Save button tapped")
                    saveButtonTapped = true
                    
                    // Add haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    
                    // Save attendance records
                    viewModel.saveAttendance()
                    print("Attendance saved")
                    
                    // Show completion options dialog
                    showingCompletionOptions = true
                }) {
                    Text(viewModel.isUpdatingExistingRecords ? "Update" : "Save")
                        .bold()
                }
            }
        }
        .confirmationDialog(
            viewModel.isUpdatingExistingRecords ? 
                "Attendance Updated Successfully" : 
                "Attendance Saved Successfully",
            isPresented: $showingCompletionOptions,
            titleVisibility: .visible
        ) {
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
        .onAppear {
            print("AttendanceListView appeared")
            // Reset the save button state
            saveButtonTapped = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AttendanceSaved"))) { notification in
            // Show completion options automatically when attendance is saved
            showingCompletionOptions = true
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: viewModel.attendanceDate)
    }
}

struct StudentAttendanceRow: View {
    let student: Student
    let isPresent: Bool
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
            
            Button(action: toggleAction) {
                Text(isPresent ? "Present" : "Absent")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPresent ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(isPresent ? .green : .red)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        AttendanceListView(viewModel: AttendanceViewModel())
    }
} 