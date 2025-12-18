import Foundation
import Combine

final class ViewModel: ObservableObject {
    @Published var word: String = "resilient"
    @Published var studentSentence: String = "I am resilient when I feel sad."
    @Published var outputJSON: String = ""
    @Published var useExternalAPI: Bool = false
    @Published var apiKeyInput: String = ""
    @Published var isLoading: Bool = false

    private let aiService = AIService()

    init() {
        // For loading saved API key (if any) into input (for demo). 
        if let key = KeychainHelper.shared.getAPIKey() {
            apiKeyInput = key
            useExternalAPI = true
        }
    }

    func saveAPIKeyToKeychain() {
        // Save key securely (only my example). 
        _ = KeychainHelper.shared.saveAPIKey(apiKeyInput)
    }

    func clearAPIKey() {
        KeychainHelper.shared.deleteAPIKey()
        apiKeyInput = ""
        useExternalAPI = false
    }

    func generateJSON() {
        isLoading = true
        outputJSON = ""
        Task {
            let response = await aiService.fetchTutorResponse(word: word, studentSentence: studentSentence, useExternalAPI: useExternalAPI)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(response), let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.outputJSON = json
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.outputJSON = "{ \"error\": \"Failed to encode response\" }"
                    self.isLoading = false
                }
            }
        }
    }
}
