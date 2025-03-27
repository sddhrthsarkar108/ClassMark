import Foundation
import SwiftUI

// This file ensures that all components are properly imported
// It doesn't contain any actual functionality

#if canImport(Vision)
import Vision
#endif

// Reference all our components to ensure they're included in the build
class ClassMarkImports {
    static func ensureImports() {
        let _ = AttendanceViewModel()
        let _ = DataManager.shared
        let _ = StringMatching.levenshteinDistance(between: "", and: "")
        let _ = TextRecognitionService.shared
        let _ = OpenAIService.shared
        
        // View references
        typealias ViewTypes = (
            ImagePickerView,
            AttendanceListView,
            ImageProcessingView,
            AttendanceHistoryView
        )
        
        // Model references
        typealias ModelTypes = (
            Student,
            AttendanceRecord
        )
    }
} 