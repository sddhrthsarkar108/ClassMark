import Foundation

struct StringMatching {
    
    // Clean a name by removing numbering, special characters and standardizing format
    static func cleanName(_ name: String) -> String {
        // Remove numbering patterns (e.g., "1.", "2)", "#3", etc.)
        var cleaned = name.replacingOccurrences(of: "^\\s*\\d+[.)]\\s*", with: "", options: .regularExpression)
        
        // Remove any remaining non-alphabetic characters except spaces
        cleaned = cleaned.components(separatedBy: CharacterSet(charactersIn: " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").inverted)
                        .joined(separator: " ")
        
        // Remove multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    // Calculate the Levenshtein distance between two strings
    static func levenshteinDistance(between a: String, and b: String) -> Int {
        let aCount = a.count
        let bCount = b.count
        
        // Handle edge cases
        if aCount == 0 { return bCount }
        if bCount == 0 { return aCount }
        
        // Create a matrix to store calculation results
        var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)
        
        // Initialize the first row and column
        for i in 0...aCount {
            matrix[i][0] = i
        }
        for j in 0...bCount {
            matrix[0][j] = j
        }
        
        // Fill the matrix
        for i in 1...aCount {
            let aIndex = a.index(a.startIndex, offsetBy: i - 1)
            for j in 1...bCount {
                let bIndex = b.index(b.startIndex, offsetBy: j - 1)
                
                let cost = a[aIndex] == b[bIndex] ? 0 : 1
                
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,        // Deletion
                    matrix[i][j-1] + 1,        // Insertion
                    matrix[i-1][j-1] + cost    // Substitution
                )
            }
        }
        
        return matrix[aCount][bCount]
    }
    
    // Calculate similarity score between two strings (0.0 to 1.0)
    static func similarityScore(between a: String, and b: String) -> Double {
        let distance = levenshteinDistance(between: a.lowercased(), and: b.lowercased())
        let maxLength = max(a.count, b.count)
        
        // Normalize the distance to a similarity score between 0 and 1
        return maxLength == 0 ? 1.0 : 1.0 - (Double(distance) / Double(maxLength))
    }
    
    // Find the best match for a name in a list of names
    static func findBestMatch(for name: String, in candidates: [String]) -> (string: String, score: Double)? {
        guard !candidates.isEmpty else { return nil }
        
        // Normalize and clean the input name
        let normalizedName = cleanName(name).lowercased()
        
        // Find the best match
        var bestMatch = candidates[0]
        var bestScore = similarityScore(between: normalizedName, and: candidates[0].lowercased())
        
        for candidate in candidates.dropFirst() {
            let score = similarityScore(between: normalizedName, and: candidate.lowercased())
            if score > bestScore {
                bestMatch = candidate
                bestScore = score
            }
        }
        
        return (bestMatch, bestScore)
    }
    
    // Find all potential matches above a threshold
    static func findAllMatches(for name: String, in candidates: [String], threshold: Double = 0.7) -> [(string: String, score: Double)] {
        // Normalize and clean the input name
        let normalizedName = cleanName(name).lowercased()
        
        // Calculate scores and filter by threshold
        return candidates.map { candidate in
            (candidate, similarityScore(between: normalizedName, and: candidate.lowercased()))
        }.filter { $0.1 >= threshold }
        .sorted { $0.1 > $1.1 }
    }
} 