import Foundation
import Testing
@testable import PanoWizard

struct OpenAIAIRetouchServiceTests {
    @Test
    func redactsStoredAPIKeyForDisplay() {
        #expect(
            OpenAIAPIKeyStore.redactedDescription(
                for: "  sk-project-example-G00A\n"
            ) == "sk-…G00A"
        )
        #expect(OpenAIAPIKeyStore.redactedDescription(for: "  ") == nil)
        #expect(OpenAIAPIKeyStore.redactedDescription(for: nil) == nil)
    }

    @Test
    func buildsDocumentedMultipartImageEditRequest() throws {
        let request = try OpenAIImageEditService.makeRequest(
            apiKey: " test-key \n",
            imageData: Data([0x01, 0x02, 0x03]),
            filename: "nadir.png",
            prompt: "Remove the tripod",
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
        #expect(body.contains("name=\"prompt\"\r\n\r\nRemove the tripod"))
        #expect(body.contains("name=\"size\"\r\n\r\n2048x2048"))
        #expect(body.contains("name=\"quality\"\r\n\r\nhigh"))
        #expect(body.contains("name=\"output_format\"\r\n\r\npng"))
        #expect(body.contains("name=\"image[]\"; filename=\"nadir.png\""))
        #expect(!body.contains("name=\"mask\""))
        #expect(body.hasSuffix("--test-boundary--\r\n"))
    }

    @Test
    func buildsMultipartRequestWithFullImageAndSeparateMask() throws {
        let imageData = Data("FULL_UNMASKED_IMAGE".utf8)
        let maskData = Data("EDIT_REGION_MASK".utf8)
        let request = try OpenAIImageEditService.makeMaskedRequest(
            apiKey: "test-key",
            imageData: imageData,
            maskData: maskData,
            filename: "patch.png",
            maskFilename: "mask.png",
            prompt: "Repair the marked area",
            size: 2_048,
            boundary: "masked-test"
        )

        let body = request.httpBody ?? Data()
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains("name=\"image[]\"; filename=\"patch.png\""))
        #expect(bodyText.contains("name=\"mask\"; filename=\"mask.png\""))
        #expect(body.range(of: imageData) != nil)
        #expect(body.range(of: maskData) != nil)
        #expect(bodyText.contains("name=\"size\"\r\n\r\n2048x2048"))
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
            Issue.record("An API error was expected")
        } catch let error as OpenAIImageEditError {
            #expect(
                error == .api(
                    statusCode: 401,
                    message: "Felaktig API-nyckel"
                )
            )
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
