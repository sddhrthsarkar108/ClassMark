import Foundation
import UIKit
import Security

class OpenAIService {
    static let shared = OpenAIService()
    
    // Keys for storage
    private let serviceIdentifier = "com.classmark.apikeys"
    private let openAIAccountIdentifier = "openai"
    
    private init() {}
    
    enum OpenAIError: Error {
        case apiKeyMissing
        case imageEncodingFailed
        case networkError(Error)
        case invalidResponse
        case noNamesFound
        case keychainError
    }
    
    func recognizeNamesFromImage(_ image: UIImage, absentStudents: [String] = [], completion: @escaping (Result<[String], OpenAIError>) -> Void) {
        // Check for API key from Keychain
        do {
            let apiKey = try getAPIKey()
            
            // Log API key status (masked for security)
            if apiKey.isEmpty {
                print("⚠️ API KEY IS EMPTY - No key found in keychain")
                completion(.failure(.apiKeyMissing))
                return
            } else {
                // Show first 4 and last 4 characters for debugging, mask the rest
                let maskedKey: String
                if apiKey.count > 8 {
                    let prefix = String(apiKey.prefix(4))
                    let suffix = String(apiKey.suffix(4))
                    maskedKey = "\(prefix)....\(suffix)"
                } else {
                    maskedKey = "****" // Key too short to safely show parts
                }
                print("🔑 API KEY FOUND - Length: \(apiKey.count), Partial: \(maskedKey)")
            }
            
            // Get the selected model from UserDefaults or use default
            let model = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4-turbo"
            print("🤖 Using OpenAI model: \(model)")
            
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to encode image to JPEG")
                completion(.failure(.imageEncodingFailed))
                return
            }
            
            let base64Image = imageData.base64EncodedString()
            print("📸 Image encoded to base64 - Size: \(base64Image.count) characters")
            
            // Prepare request
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Prepare prompt text based on absent students
            var promptText = "Extract only the handwritten names from this attendance sheet. Return each name on a separate line, without any numbering or formatting."
            
            // Add absent student names to the prompt if available
            if !absentStudents.isEmpty {
                let absentList = absentStudents.joined(separator: ", ")
                promptText += "\n\nThe following students are currently marked as absent. Please check if any of their names appear in the image, as they might be difficult to read: \(absentList)"
                print("📝 Including list of \(absentStudents.count) absent students in prompt")
            }
            
            // Add specific instructions about the format
            promptText += "\n\nIMPORTANT: Return ONLY the names, one per line. Do not include any numbering (like '1.', '2.'), explanatory text, or formatting. Just the plain names."
            
            // Create request body - updated to match Python implementation
            let requestBody: [String: Any] = [
                "model": model, // Use selected model
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
                                "text": promptText
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
            
            print("Sending OpenAI API request with model: \(model)")
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
                request.httpBody = jsonData
                
                // Make network request
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("❌ OpenAI network error: \(error.localizedDescription)")
                        
                        // More detailed network error info
                        if let nsError = error as NSError? {
                            print("  Domain: \(nsError.domain)")
                            print("  Code: \(nsError.code)")
                            print("  Description: \(nsError.localizedDescription)")
                            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                                print("  Underlying error: \(underlyingError.localizedDescription)")
                            }
                        }
                        
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    // Log HTTP status code for debugging
                    if let httpResponse = response as? HTTPURLResponse {
                        let statusCode = httpResponse.statusCode
                        print("🌐 OpenAI API HTTP Status: \(statusCode)")
                        
                        // Check for HTTP errors
                        if statusCode < 200 || statusCode >= 300 {
                            print("❌ HTTP Error: Received status code \(statusCode)")
                            print("  Headers: \(httpResponse.allHeaderFields)")
                        }
                    } else {
                        print("⚠️ Response is not HTTPURLResponse")
                    }
                    
                    guard let data = data else {
                        print("❌ OpenAI API returned no data")
                        completion(.failure(.invalidResponse))
                        return
                    }
                    
                    print("📊 Received \(data.count) bytes of response data")
                    
                    // Debug: Print raw response for troubleshooting
                    if let responseString = String(data: data, encoding: .utf8) {
                        let previewLength = min(responseString.count, 200)
                        let preview = responseString.prefix(previewLength)
                        print("📬 OpenAI API response preview: \(preview)...")
                        if responseString.count > previewLength {
                            print("  (Response truncated, total length: \(responseString.count) characters)")
                        }
                    } else {
                        print("⚠️ Unable to decode response data as UTF-8 string")
                    }
                    
                    // Parse response
                    do {
                        print("🔍 Attempting to parse JSON response...")
                        
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("✅ Successfully parsed JSON")
                            
                            // Print available top-level keys for debugging
                            let keys = json.keys.joined(separator: ", ")
                            print("📋 JSON keys available: \(keys)")
                            
                            // Check for error response
                            if let errorData = json["error"] as? [String: Any] {
                                if let errorMessage = errorData["message"] as? String {
                                    print("❌ OpenAI API error: \(errorMessage)")
                                    if let errorType = errorData["type"] as? String {
                                        print("  Error type: \(errorType)")
                                    }
                                    if let errorCode = errorData["code"] as? String {
                                        print("  Error code: \(errorCode)")
                                    }
                                } else {
                                    print("❌ OpenAI API returned error object without message")
                                    print("  Error data: \(errorData)")
                                }
                                completion(.failure(.invalidResponse))
                                return
                            }
                            
                            // Check if choices array exists
                            if let choices = json["choices"] as? [[String: Any]] {
                                print("✅ Found choices array with \(choices.count) items")
                                
                                if choices.isEmpty {
                                    print("⚠️ Choices array is empty")
                                    completion(.failure(.invalidResponse))
                                    return
                                }
                                
                                if let firstChoice = choices.first {
                                    print("✅ Successfully accessed first choice")
                                    
                                    // Debug choice keys
                                    let choiceKeys = firstChoice.keys.joined(separator: ", ")
                                    print("📋 Choice keys available: \(choiceKeys)")
                                    
                                    if let message = firstChoice["message"] as? [String: Any] {
                                        print("✅ Found message object")
                                        
                                        // Debug message keys
                                        let messageKeys = message.keys.joined(separator: ", ")
                                        print("📋 Message keys available: \(messageKeys)")
                                        
                                        if let content = message["content"] as? String {
                                            print("✅ Successfully retrieved content")
                                            print("📝 Content length: \(content.count) characters")
                                            
                                            // Extract names from content
                                            let names = content.split(separator: "\n").map {
                                                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }.filter { !$0.isEmpty }
                                            
                                            print("📋 Extracted \(names.count) names from OpenAI response")
                                            if !names.isEmpty {
                                                print("  First few names: \(names.prefix(min(3, names.count)).joined(separator: ", "))")
                                            }
                                            
                                            if names.isEmpty {
                                                print("⚠️ No names extracted from content")
                                                completion(.failure(.noNamesFound))
                                            } else {
                                                completion(.success(names.map { String($0) }))
                                            }
                                        } else {
                                            print("❌ Message does not contain 'content' field")
                                            completion(.failure(.invalidResponse))
                                        }
                                    } else {
                                        print("❌ First choice does not contain 'message' field")
                                        completion(.failure(.invalidResponse))
                                    }
                                } else {
                                    print("❌ Failed to access first choice")
                                    completion(.failure(.invalidResponse))
                                }
                            } else {
                                print("❌ JSON does not contain 'choices' array")
                                completion(.failure(.invalidResponse))
                            }
                        } else {
                            print("❌ Failed to parse JSON response as dictionary")
                            completion(.failure(.invalidResponse))
                        }
                    } catch {
                        print("❌ JSON parsing error: \(error.localizedDescription)")
                        if let jsonError = error as? NSError {
                            print("  Domain: \(jsonError.domain)")
                            print("  Code: \(jsonError.code)")
                            print("  User info: \(jsonError.userInfo)")
                        }
                        completion(.failure(.invalidResponse))
                    }
                }
                
                task.resume()
                
            } catch {
                print("Error preparing request: \(error.localizedDescription)")
                completion(.failure(.networkError(error)))
            }
        } catch {
            print("API key retrieval error: \(error.localizedDescription)")
            completion(.failure(.apiKeyMissing))
        }
    }
    
    // MARK: - API Key Management
    
    // Securely retrieve the API key from Keychain
    func getAPIKey() throws -> String {
        print("🔍 Attempting to retrieve API key from keychain...")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: openAIAccountIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        print("🔐 Keychain query status: \(status)")
        
        guard status != errSecItemNotFound else {
            print("⚠️ API key not found in keychain (status: errSecItemNotFound)")
            return ""
        }
        
        guard status == errSecSuccess else {
            print("❌ Error accessing keychain: \(status)")
            throw OpenAIError.keychainError
        }
        
        guard let data = item as? Data else {
            print("❌ Failed to cast keychain item to Data")
            throw OpenAIError.keychainError
        }
        
        guard let apiKey = String(data: data, encoding: .utf8) else {
            print("❌ Failed to convert keychain data to string")
            throw OpenAIError.keychainError
        }
        
        print("✅ Successfully retrieved API key from keychain")
        return apiKey
    }
    
    // Save the API key to Keychain
    func saveAPIKey(_ apiKey: String) throws {
        print("💾 Attempting to save API key to keychain...")
        
        // Delete any existing key first
        deleteAPIKey()
        
        guard !apiKey.isEmpty else {
            print("❌ Cannot save empty API key")
            throw OpenAIError.apiKeyMissing
        }
        
        guard let data = apiKey.data(using: .utf8) else {
            print("❌ Failed to convert API key to data")
            throw OpenAIError.keychainError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: openAIAccountIdentifier,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        print("🔐 Keychain save status: \(status)")
        
        guard status == errSecSuccess else {
            print("❌ Failed to save API key to keychain: \(status)")
            throw OpenAIError.keychainError
        }
        
        print("✅ API key saved successfully to keychain")
    }
    
    // Delete the API key from Keychain
    func deleteAPIKey() {
        print("🗑️ Attempting to delete API key from keychain...")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: openAIAccountIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ API key deleted from keychain")
        } else if status == errSecItemNotFound {
            print("ℹ️ No API key found in keychain to delete")
        } else {
            print("⚠️ Error deleting API key from keychain: \(status)")
        }
    }
    
    // Check if we have an API key stored
    func hasAPIKey() -> Bool {
        print("🔍 Checking if API key exists in keychain...")
        do {
            let key = try getAPIKey()
            let exists = !key.isEmpty
            print(exists ? "✅ API key exists in keychain" : "⚠️ No API key found in keychain")
            return exists
        } catch {
            print("❌ Error checking API key: \(error.localizedDescription)")
            return false
        }
    }
} 