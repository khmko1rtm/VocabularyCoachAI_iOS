import Foundation
import NaturalLanguage
import Security

/// AIService, це універсальний локальний тренувальний сервіс для генерації TutorResponse.
/// Містить в собі:
/// мій локальний словник вбудований,
/// fallback-генерацію пояснень і прикладів для невідомих слів,
/// опційний зовнішній словниковий API (демонстраційна, мок-реалізація),
/// приклад інтеграції з реальним API (там коментований код з прикладом запиту).
final class AIService {
    // MARK: - Local dictionary entry
    private struct Entry {
        let difficulty: String
        let meaning: String
        let pos: NLTag
        let examples: [String]
        let synonyms: [String]
    }

    // My small built-in dictionary 
    private let localDictionary: [String: Entry] = [
        "resilient": Entry(
            difficulty: "Intermediate",
            meaning: "Able to recover quickly from problems or strong emotions; not easily discouraged.",
            pos: .adjective,
            examples: [
                "After losing her job, Maria stayed resilient and found a new role within months.",
                "Children can be very resilient after moving to a new school."
            ],
            synonyms: ["tough", "strong", "adaptable"]
        ),
        "happy": Entry(
            difficulty: "Beginner",
            meaning: "Feeling good and joyful.",
            pos: .adjective,
            examples: [
                "I feel happy when I spend time with my friends.",
                "She was happy with her exam results."
            ],
            synonyms: ["joyful", "glad", "pleased"]
        ),
        "improve": Entry(
            difficulty: "Beginner",
            meaning: "To become better or to make something better.",
            pos: .verb,
            examples: [
                "Practice every day to improve your English.",
                "He took lessons to improve his piano skills."
            ],
            synonyms: ["get better", "enhance", "upgrade"]
        )
        // add more items here
    ]

    // MARK: - Public API

    /// Main function - returns TutorResponse.
    /// - Parameters:
    /// - word: target word (any string)
    /// - studentSentence: student's sentence
    /// - useExternalAPI: if true, tries to fetch from external API (mocked)
    func fetchTutorResponse(word: String, studentSentence: String, useExternalAPI: Bool) async -> TutorResponse {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TutorResponse(
                wordAnalysis: WordAnalysis(difficulty: "Beginner", meaning: "No word provided.", examples: [], synonyms: []),
                sentenceFeedback: SentenceFeedback(status: "Incorrect", explanation: "You did not provide a word to analyse.", correctedSentence: "")
            )
        }

        // 1) Try local dictionary
        if let entry = localDictionary[trimmed.lowercased()] {
            return evaluate(word: trimmed, entry: entry, sentence: studentSentence)
        }

        // 2) Optionally try external dictionary (mocked). 
        if useExternalAPI {
            if let externalEntry = await ExternalDictionaryAPI.shared.fetch(word: trimmed) {
                return evaluate(word: trimmed, entry: externalEntry, sentence: studentSentence)
            }
            // if external failed or returned nil, fall back to heuristic
        }

        // 3) Fallback heuristic: infer pos, difficulty, meaning and examples
        let inferredPOS = inferPOS(for: trimmed)
        let difficulty = inferDifficulty(for: trimmed)
        let meaning = buildFallbackMeaning(for: trimmed, pos: inferredPOS)
        let examples = buildExamples(for: trimmed, pos: inferredPOS)
        let synonyms: [String] = []

        let fallbackEntry = Entry(difficulty: difficulty, meaning: meaning, pos: inferredPOS, examples: examples, synonyms: synonyms)
        return evaluate(word: trimmed, entry: fallbackEntry, sentence: studentSentence)
    }

    // MARK: - Evaluation

    private func evaluate(word: String, entry: Entry, sentence: String) -> TutorResponse {
        let wa = WordAnalysis(difficulty: entry.difficulty, meaning: entry.meaning, examples: entry.examples, synonyms: entry.synonyms)

        // Check whether the student's sentence contains the word (case-insensitive, whole word)
        if let (range, tag) = findWordAndPOSTag(in: sentence, target: word) {
            // Present in sentence
            let actualPOS = tag ?? entry.pos
            let usageNatural = checkSimpleUsage(sentence: sentence, targetRange: range, pos: actualPOS)

            if actualPOS == entry.pos && usageNatural {
                let sf = SentenceFeedback(
                    status: "Correct",
                    explanation: "Great! You used “\(word)” correctly in the sentence.",
                    correctedSentence: ""
                )
                return TutorResponse(wordAnalysis: wa, sentenceFeedback: sf)
            } else {
                let explanation = buildMostlyCorrectExplanation(word: word, expectedPOS: entry.pos, actualPOS: actualPOS, sentence: sentence)
                let suggestion = suggestImprovedSentence(original: sentence, word: word, expectedPOS: entry.pos)
                let sf = SentenceFeedback(status: "Mostly correct", explanation: explanation, correctedSentence: suggestion)
                return TutorResponse(wordAnalysis: wa, sentenceFeedback: sf)
            }
        } else {
            // Word not used
            let suggestion = buildSimpleSentenceWith(word: word, pos: entry.pos)
            let sf = SentenceFeedback(status: "Incorrect", explanation: "You did not use the target word in your sentence. Try to include it in a short, simple sentence.", correctedSentence: suggestion)
            return TutorResponse(wordAnalysis: wa, sentenceFeedback: sf)
        }
    }

    // MARK: - Text analysis helpers

    private func findWordAndPOSTag(in sentence: String, target: String) -> (Range<String.Index>, NLTag?)? {
        let lowerSentence = sentence.lowercased()
        let lowerTarget = target.lowercased()

        guard let foundRange = lowerSentence.range(of: lowerTarget) else { return nil }

        // expand to real token boundaries
        let start = expandToWordBoundary(in: sentence, at: foundRange.lowerBound, back: true)
        let end = expandToWordBoundary(in: sentence, at: foundRange.upperBound, back: false)
        let tokenRange = start..<end

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        let (tag, _) = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lexicalClass)
        return (tokenRange, tag)
    }

    private func expandToWordBoundary(in text: String, at index: String.Index, back: Bool) -> String.Index {
        var i = index
        if back {
            while i > text.startIndex {
                let prev = text.index(before: i)
                let ch = text[prev]
                if ch.isLetter || ch == "'" {
                    i = prev
                } else { break }
            }
            return i
        } else {
            while i < text.endIndex {
                let ch = text[i]
                if ch.isLetter || ch == "'" {
                    i = text.index(after: i)
                } else { break }
            }
            return i
        }
    }

    private func checkSimpleUsage(sentence: String, targetRange: Range<String.Index>, pos: NLTag) -> Bool {
        let before = sentence[..<targetRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let wordsBefore = before.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        if pos == .adjective {
            if let last = wordsBefore.last?.lowercased() {
                let linking = ["is","am","are","was","were","feel","seem","become","looks","look"]
                if linking.contains(last) { return true }
            }
            return false
        } else if pos == .verb {
            if let last = wordsBefore.last?.lowercased() {
                let pronouns = ["i","we","they","she","he","you","it"]
                if pronouns.contains(last) { return true }
            }
            return false
        } else if pos == .noun {
            if let last = wordsBefore.last?.lowercased() {
                let articles = ["a","an","the","my","his","her","their"]
                if articles.contains(last) { return true }
            }
            return false
        } else {
            return true
        }
    }

    private func buildMostlyCorrectExplanation(word: String, expectedPOS: NLTag, actualPOS: NLTag, sentence: String) -> String {
        if expectedPOS == actualPOS {
            return "You used the word, but the sentence could sound more natural. Try the suggestion."
        } else {
            return "You used the word, but it usually works as a \(readablePOS(expectedPOS)). In your sentence it looks like a \(readablePOS(actualPOS)). See the suggestion."
        }
    }

    private func suggestImprovedSentence(original: String, word: String, expectedPOS: NLTag) -> String {
        // For simplicity return a clear short example
        return buildSimpleSentenceWith(word: word, pos: expectedPOS)
    }

    private func buildSimpleSentenceWith(word: String, pos: NLTag) -> String {
        switch pos {
        case .adjective: return "I am \(word)."
        case .verb: return "I \(word) every day."
        case .noun: return "This is a \(word)."
        case .adverb: return "She did it \(word)."
        default: return "I know the word \(word)."
        }
    }

    // MARK: - Fallback generation helpers

    private func inferPOS(for word: String) -> NLTag {
        let lower = word.lowercased()
        if lower.hasSuffix("ly") { return .adverb }
        if lower.hasSuffix("ing") || lower.hasSuffix("ed") { return .verb }
        if lower.hasSuffix("ion") || lower.hasSuffix("ment") || lower.hasSuffix("ness") { return .noun }
        if lower.hasSuffix("able") || lower.hasSuffix("ous") || lower.hasSuffix("ful") || lower.hasSuffix("less") || lower.hasSuffix("ive") || lower.hasSuffix("al") { return .adjective }
        return .adjective
    }

    private func inferDifficulty(for word: String) -> String {
        let len = word.count
        if len <= 5 { return "Beginner" }
        if len <= 9 { return "Intermediate" }
        return "Advanced"
    }

    private func buildFallbackMeaning(for word: String, pos: NLTag) -> String {
        switch pos {
        case .noun: return "\(capitalized(word)) — a thing, person, or idea. (Simple explanation)"
        case .verb: return "\(capitalized(word)) — to do or perform the action named by this word. (Simple explanation)"
        case .adjective: return "\(capitalized(word)) — a word that describes a person, place, thing, or feeling. (Simple explanation)"
        case .adverb: return "\(capitalized(word)) — a word that describes how an action is done. (Simple explanation)"
        default: return "\(capitalized(word)) — a simple description of the word."
        }
    }

    private func buildExamples(for word: String, pos: NLTag) -> [String] {
        switch pos {
        case .adjective: return ["She is \(word).", "It was a \(word) day."]
        case .verb: return ["I \(word) every day.", "They \(word) the problem together."]
        case .noun: return ["The \(word) was on the table.", "She found a \(word)."]
        case .adverb: return ["He moved \(word).", "She spoke \(word)."]
        default: return ["I know the word \(word).", "This sentence uses \(word)."]
        }
    }

    private func capitalized(_ s: String) -> String {
        return s.prefix(1).capitalized + s.dropFirst()
    }

    private func readablePOS(_ pos: NLTag) -> String {
        switch pos {
        case .noun: return "noun"
        case .verb: return "verb"
        case .adjective: return "adjective"
        case .adverb: return "adverb"
        default: return "word"
        }
    }
}

// MARK: - ExternalDictionaryAPI (mock + integration example)

private extension AIService {
    struct ExternalEntry {
        let difficulty: String
        let meaning: String
        let pos: NLTag
        let examples: [String]
        let synonyms: [String]
    }

    // Adapter to Entry
    func evaluate(word: String, entry: ExternalEntry, sentence: String) -> TutorResponse {
        let e = AIService.Entry(difficulty: entry.difficulty, meaning: entry.meaning, pos: entry.pos, examples: entry.examples, synonyms: entry.synonyms)
        return evaluate(word: word, entry: e, sentence: sentence)
    }
}

/// ExternalDictionaryAPI demonstrates how an external API could be integrated.
/// In my app it returns mocked data, but the `fetch` function
/// contains commented example code for a real HTTP call Wordnik, you'll see.
final class ExternalDictionaryAPI {
    static let shared = ExternalDictionaryAPI()
    private init() {}

    /// Fetch definition for a word. Returns nil on failure.
    /// In this demo we simulate a network call with Task.sleep and return a mock response.
    func fetch(word: String) async -> AIService.ExternalEntry? {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s

        // Mocked response (would come from the external API)
        let mock = AIService.ExternalEntry(
            difficulty: "Intermediate",
            meaning: "A mock meaning for \(word). (This is a demo fallback.)",
            pos: .adjective,
            examples: ["This is a mock example using \(word).", "Another mock sentence with \(word)."],
            synonyms: ["sample", "demo"]
        )
        return mock

        /*
        // === Example real request (Wordnik) ===
        guard let apiKey = KeychainHelper.shared.getAPIKey() else { return nil }
        let urlString = "https://api.wordnik.com/v4/word.json/\(word)/definitions?limit=5&api_key=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        // parse JSON response, build ExternalEntry from results
        */
    }
}

// MARK: - KeychainHelper (simple wrapper)
// This is my minimal example of usage. 

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    func saveAPIKey(_ key: String, service: String = "AI-Vocabulary-Coach", account: String = "dictionary_api_key") -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete any existing item
        let queryDel: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(queryDel as CFDictionary)

        // Add new key
        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(queryAdd as CFDictionary, nil)
        return status == errSecSuccess
    }

    func getAPIKey(service: String = "AI-Vocabulary-Coach", account: String = "dictionary_api_key") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    func deleteAPIKey(service: String = "AI-Vocabulary-Coach", account: String = "dictionary_api_key") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
