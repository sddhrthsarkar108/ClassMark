import Foundation
import Vision
import UIKit

class TextRecognitionService {
    static let shared = TextRecognitionService()
    
    private init() {}
    
    enum TextRecognitionError: Error {
        case imageConversionFailed
        case requestFailed
        case noTextFound
        case lowConfidence
    }
    
    // Main function to extract text from image
    func recognizeText(from image: UIImage, completion: @escaping (Result<[String], TextRecognitionError>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(.imageConversionFailed))
            return
        }
        
        // Create a request handler
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Create a recognition request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("Text recognition error: \(error)")
                completion(.failure(.requestFailed))
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(.noTextFound))
                return
            }
            
            if observations.isEmpty {
                completion(.failure(.noTextFound))
                return
            }
            
            // Process the detected text
            let extractedLines = self.processTextObservations(observations)
            
            // Post notification with extracted text
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ExtractedText"),
                    object: extractedLines
                )
                print("Posted notification with extracted text: \(extractedLines)")
            }
            
            if extractedLines.isEmpty {
                completion(.failure(.noTextFound))
            } else {
                completion(.success(extractedLines))
            }
        }
        
        // Configure the recognition request
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        
        // Perform the request
        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform text recognition: \(error)")
            completion(.failure(.requestFailed))
        }
    }
    
    // Process the observations to extract lines of text
    private func processTextObservations(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var extractedLines: [String] = []
        
        for observation in observations {
            // Get the top candidate for each observation
            if let topCandidate = observation.topCandidates(1).first {
                let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Ignore very short strings or strings with only numbers/special characters
                if text.count > 1 && text.rangeOfCharacter(from: CharacterSet.letters) != nil {
                    extractedLines.append(text)
                }
            }
        }
        
        return extractedLines
    }
    
    // Match extracted names with the student database
    func matchNamesWithStudents(extractedTexts: [String]) -> [String: Double] {
        let students = DataManager.shared.getStudents()
        let studentNames = students.map { $0.name }
        
        var matchedRollNumbers: [String: Double] = [:]
        
        // Process each extracted text line
        for text in extractedTexts {
            // Find all potential matches above threshold
            let potentialMatches = StringMatching.findAllMatches(for: text, in: studentNames, threshold: 0.6)
            
            // Find the best match if any exists
            if let bestMatch = potentialMatches.first {
                // Find corresponding student roll number
                if let student = students.first(where: { $0.name == bestMatch.string }) {
                    matchedRollNumbers[student.rollNumber] = bestMatch.score
                }
            }
        }
        
        return matchedRollNumbers
    }
    
    // Check if we should use fallback (OpenAI) based on match confidence
    func shouldUseFallback(matchResult: [String: Double]) -> Bool {
        // If no matches were found, suggest fallback
        if matchResult.isEmpty {
            return true
        }
        
        // If more than half the matches have low confidence scores
        let lowConfidenceMatches = matchResult.filter { $0.value < 0.75 }
        return Double(lowConfidenceMatches.count) / Double(matchResult.count) > 0.5
    }
} 