import Foundation
import Testing
@testable import PanoWizard

struct OpenAIAIRetouchServiceTests {
    @Test
    func buildsDocumentedMultipartImageEditRequest() throws {
        let request = try OpenAIImageEditService.makeRequest(
            apiKey: " test-key \n",
            imageData: Data([0x01, 0x02, 0x03]),
            filename: "nadir.png",
            prompt: "Ta bort stativet",
            size: 2_048,
            boundary: "test-boundary"
        )

        #expect(request.url == OpenAIImageEditService.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "multipart/form-data; boundary=test-boundary"
        )
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"model\"\r\n\r\ngpt-image-2"))
        #expect(body.contains("name=\"prompt\"\r\n\r\nTa bort stativet"))
        #expect(body.contains("name=\"size\"\r\n\r\n2048x2048"))
        #expect(body.contains("name=\"quality\"\r\n\r\nhigh"))
        #expect(body.contains("name=\"output_format\"\r\n\r\npng"))
        #expect(body.contains("name=\"image[]\"; filename=\"nadir.png\""))
        #expect(body.hasSuffix("--test-boundary--\r\n"))
    }

    @Test
    func decodesBase64ImageResponse() throws {
        let expected = Data([0x89, 0x50, 0x4e, 0x47])
        let response = """
        {"data":[{"b64_json":"\(expected.base64EncodedString())"}]}
        """

        let decoded = try OpenAIImageEditService.decodeImageData(
            from: Data(response.utf8),
            statusCode: 200
        )

        #expect(decoded == expected)
    }

    @Test
    func exposesAPIErrorMessage() {
        let response = Data(
            #"{"error":{"message":"Felaktig API-nyckel"}}"#.utf8
        )

        do {
            _ = try OpenAIImageEditService.decodeImageData(
                from: response,
                statusCode: 401
            )
            Issue.record("Ett API-fel förväntades")
        } catch let error as OpenAIImageEditError {
            #expect(
                error == .api(
                    statusCode: 401,
                    message: "Felaktig API-nyckel"
                )
            )
        } catch {
            Issue.record("Oväntad feltyp: \(error)")
        }
    }
}
