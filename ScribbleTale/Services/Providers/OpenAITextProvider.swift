import Foundation
import os

private let log = Logger(subsystem: "com.scribbletale.app", category: "OpenAITextProvider")

@Observable
@MainActor
final class OpenAITextProvider: TextGenerationProvider {
    private(set) var isLoaded = false
    private(set) var loadingProgress: Double = 0
    private(set) var loadingStatus: String = ""
    private(set) var thinkingText: String = ""
    private(set) var loadedModel: StoryModel?

    private var apiKey: String
    private static let defaultModel = "gpt-4o-mini"
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func updateAPIKey(_ key: String) {
        apiKey = key
        if key.isEmpty {
            isLoaded = false
            loadingStatus = "API key required"
        }
    }

    func load(_ model: StoryModel) async {
        loadingProgress = 0.5
        loadingStatus = "Validating API key..."

        guard !apiKey.isEmpty else {
            loadingStatus = "API key required"
            isLoaded = false
            return
        }

        loadingProgress = 1.0
        loadingStatus = "OpenAI ready"
        isLoaded = true
        loadedModel = model
        log.info("load: OpenAI provider ready with key=\(self.apiKey.prefix(8), privacy: .public)...")
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) -> AsyncThrowingStream<String, Error> {
        let key = apiKey
        let promptPreview = String(userPrompt.prefix(80))
        log.info("generate: starting — maxTokens=\(maxTokens) temp=\(temperature) prompt=\"\(promptPreview, privacy: .public)...\"")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try Self.buildRequest(
                        apiKey: key,
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP
                    )

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        var body = ""
                        for try await line in asyncBytes.lines {
                            body += line
                        }
                        log.error("generate: HTTP \(httpResponse.statusCode) — \(body, privacy: .public)")
                        throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: body)
                    }

                    var tokenCount = 0
                    for try await line in asyncBytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data),
                              let content = chunk.choices.first?.delta.content,
                              !content.isEmpty else {
                            continue
                        }

                        tokenCount += 1
                        continuation.yield(content)
                    }

                    log.info("generate: completed — \(tokenCount) chunks")
                    continuation.finish()
                } catch {
                    log.error("generate: failed — \(error, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request Building

    private static func buildRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": defaultModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "max_tokens": maxTokens,
            "temperature": Double(temperature),
            "top_p": Double(topP),
            "stream": true,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - SSE Decoding

    private struct SSEChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }
}

enum OpenAIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from OpenAI"
        case .httpError(let statusCode, let body):
            "OpenAI API error (\(statusCode)): \(body.prefix(200))"
        case .apiKeyMissing:
            "OpenAI API key is required"
        }
    }
}
