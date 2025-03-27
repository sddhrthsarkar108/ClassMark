import Foundation
import UIKit

class OpenAIService {
    static let shared = OpenAIService()
    
    private init() {}
    
    enum OpenAIError: Error {
        case apiKeyMissing
        case imageEncodingFailed
        case networkError(Error)
        case invalidResponse
        case noNamesFound
    }
    
    func recognizeNamesFromImage(_ image: UIImage, completion: @escaping (Result<[String], OpenAIError>) -> Void) {
        // Check for API key - in a real app, store this securely
        let apiKey = getAPIKey()
        guard !apiKey.isEmpty else {
            completion(.failure(.apiKeyMissing))
            return
        }
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(.imageEncodingFailed))
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Prepare request
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body
        let requestBody: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                [
                    "role": "system",
                    "content": "You are an OCR system that extracts handwritten names from images."
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Extract only the handwritten names from this attendance sheet. Do not include introductory text or numbers. Return only a plain list of names, one per line."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Make network request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }
                
                // Parse response
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        // Extract names from content
                        let names = content.split(separator: "\n").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty }
                        
                        if names.isEmpty {
                            completion(.failure(.noNamesFound))
                        } else {
                            completion(.success(names.map { String($0) }))
                        }
                    } else {
                        completion(.failure(.invalidResponse))
                    }
                } catch {
                    completion(.failure(.invalidResponse))
                }
            }
            
            task.resume()
            
        } catch {
            completion(.failure(.networkError(error)))
        }
    }
    
    // In a real app, get this from secure storage or keychain
    private func getAPIKey() -> String {
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
} 