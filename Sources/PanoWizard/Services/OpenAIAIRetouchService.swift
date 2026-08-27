import Foundation
import Security

struct AIRetouchPreview: Sendable {
    let pole: PanoramaPole
    let sourceURL: URL
    let editedURL: URL
    let preparedURL: URL
}

enum AIRetouchError: LocalizedError {
    case panoramaUnavailable
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .panoramaUnavailable:
            "Generera panoramat innan du använder AI-retusch."
        case .emptyPrompt:
            "Beskriv vad som ska retuscheras."
        }
    }
}

enum OpenAIImageEditError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case invalidImageData
    case api(statusCode: Int, message: String)
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Ange en OpenAI API-nyckel."
        case .invalidResponse:
            "OpenAI returnerade ett ogiltigt svar."
        case .invalidImageData:
            "OpenAI-svaret innehöll ingen läsbar bild."
        case let .api(statusCode, message):
            "OpenAI-fel \(statusCode): \(message)"
        case .keychain(let status):
            "API-nyckeln kunde inte sparas i Nyckelring (fel \(status))."
        }
    }
}

struct OpenAIAPIKeyStore: Sendable {
    private static let service = "se.panowizard.openai"
    private static let account = "api-key"

    func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIImageEditError.missingAPIKey }
        let data = Data(trimmed.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw OpenAIImageEditError.keychain(status: updateStatus)
        }

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIImageEditError.keychain(status: addStatus)
        }
    }
}

struct OpenAIImageEditService: Sendable {
    static let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
    static let model = "gpt-image-2"

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func edit(
        imageData: Data,
        filename: String,
        prompt: String,
        size: Int
    ) async throws -> Data {
        guard !apiKey.isEmpty else { throw OpenAIImageEditError.missingAPIKey }
        let request = try Self.makeRequest(
            apiKey: apiKey,
            imageData: imageData,
            filename: filename,
            prompt: prompt,
            size: size
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageEditError.invalidResponse
        }
        return try Self.decodeImageData(
            from: data,
            statusCode: httpResponse.statusCode
        )
    }

    static func makeRequest(
        apiKey: String,
        imageData: Data,
        filename: String,
        prompt: String,
        size: Int,
        boundary: String = "PanoWizard-\(UUID().uuidString)"
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIImageEditError.missingAPIKey
        }
        var body = Data()
        appendField(name: "model", value: model, boundary: boundary, to: &body)
        appendField(name: "prompt", value: prompt, boundary: boundary, to: &body)
        appendField(
            name: "size",
            value: "\(size)x\(size)",
            boundary: boundary,
            to: &body
        )
        appendField(name: "quality", value: "high", boundary: boundary, to: &body)
        appendField(
            name: "output_format",
            value: "png",
            boundary: boundary,
            to: &body
        )
        appendFile(
            name: "image[]",
            filename: filename,
            contentType: "image/png",
            data: imageData,
            boundary: boundary,
            to: &body
        )
        body.appendUTF8("--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return request
    }

    static func decodeImageData(
        from data: Data,
        statusCode: Int
    ) throws -> Data {
        guard (200..<300).contains(statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw OpenAIImageEditError.api(
                statusCode: statusCode,
                message: envelope?.error.message ?? fallback
            )
        }
        guard let response = try? JSONDecoder().decode(ImageResponse.self, from: data),
              let encoded = response.data.first?.b64JSON,
              let image = Data(base64Encoded: encoded),
              !image.isEmpty else {
            throw OpenAIImageEditError.invalidImageData
        }
        return image
    }

    private static func appendField(
        name: String,
        value: String,
        boundary: String,
        to data: inout Data
    ) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.appendUTF8("\(value)\r\n")
    }

    private static func appendFile(
        name: String,
        filename: String,
        contentType: String,
        data fileData: Data,
        boundary: String,
        to data: inout Data
    ) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; "
                + "filename=\"\(filename)\"\r\n"
        )
        data.appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        data.append(fileData)
        data.appendUTF8("\r\n")
    }
}

private struct ImageResponse: Decodable {
    struct Item: Decodable {
        let b64JSON: String

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [Item]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
