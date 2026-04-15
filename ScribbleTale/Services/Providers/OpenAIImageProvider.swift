import Foundation
import os
import PencilKit
import CoreGraphics
import UIKit

private let log = Logger(subsystem: "com.scribbletale.app", category: "OpenAIImageProvider")

@Observable
@MainActor
final class OpenAIImageProvider: ImageGenerationProvider {
    private(set) var isGenerating = false
    private(set) var isAvailable = false
    let unavailableReason: String? = nil

    private var apiKey: String
    private static let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    private static let model = "gpt-image-1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func updateAPIKey(_ key: String) {
        apiKey = key
        isAvailable = !key.isEmpty
    }

    func checkAvailability() async {
        isAvailable = !apiKey.isEmpty
        log.info("checkAvailability: available=\(self.isAvailable)")
    }

    func generateImage(prompt: String, drawing: PKDrawing?) async throws -> CGImage? {
        log.info("generateImage: starting — prompt=\(prompt, privacy: .public)")
        isGenerating = true
        defer {
            isGenerating = false
            log.info("generateImage: finished")
        }

        guard isAvailable else {
            throw OpenAIImageError.apiKeyMissing
        }

        let storyBookPrompt = "\(prompt). Children's storybook illustration style, warm colors, soft edges, whimsical and friendly."

        let request = try buildRequest(prompt: storyBookPrompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            log.error("generateImage: HTTP \(httpResponse.statusCode) — \(body, privacy: .public)")
            throw OpenAIImageError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(ImageResponse.self, from: data)

        guard let imageData = decoded.data.first else {
            log.warning("generateImage: no images in response")
            return nil
        }

        if let b64 = imageData.b64_json, let raw = Data(base64Encoded: b64) {
            return cgImage(from: raw)
        }

        if let urlString = imageData.url, let url = URL(string: urlString) {
            let (imageBytes, _) = try await URLSession.shared.data(from: url)
            return cgImage(from: imageBytes)
        }

        log.warning("generateImage: response contained neither b64 nor url")
        return nil
    }

    // MARK: - Request Building

    private func buildRequest(prompt: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": Self.model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "low",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Decoding

    private struct ImageResponse: Decodable {
        struct ImageData: Decodable {
            let b64_json: String?
            let url: String?
        }
        let data: [ImageData]
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let uiImage = UIImage(data: data) else {
            log.error("cgImage: failed to decode image data (\(data.count) bytes)")
            return nil
        }
        return uiImage.cgImage
    }
}

enum OpenAIImageError: LocalizedError {
    case apiKeyMissing
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            "OpenAI API key is required for image generation"
        case .invalidResponse:
            "Invalid response from OpenAI Images API"
        case .httpError(let statusCode, let body):
            "OpenAI Images API error (\(statusCode)): \(body.prefix(200))"
        }
    }
}
