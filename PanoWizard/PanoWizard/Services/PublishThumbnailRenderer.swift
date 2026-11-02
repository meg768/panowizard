import AppKit
import WebKit
import ImageIO

/// Renders the actual exported viewer, including its saved camera and adjustments.
@MainActor
enum PublishThumbnailRenderer {
    static func render(htmlURL: URL, to destination: URL) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: "Object.defineProperty(window, 'devicePixelRatio', {get: () => 1});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        for _ in 0..<300 {
            try Task.checkCancellation()
            let ready = try? await webView.evaluateJavaScript("typeof panoramaLoaded !== 'undefined' && panoramaLoaded")
            if ready as? Bool == true {
                let result = try await webView.evaluateJavaScript("""
                (() => {
                    y=initialYaw; p=initialPitch; f=initialFOV;
                    draw(); gl.finish();
                    if(canvas.width!==640 || canvas.height!==360 || gl.isContextLost())
                        throw new Error('Thumbnail viewport unavailable');
                    return canvas.toDataURL('image/jpeg', 0.8);
                })()
                """)
                guard let encoded = result as? String,
                      encoded.hasPrefix("data:image/jpeg;base64,"),
                      let data = Data(base64Encoded: String(encoded.dropFirst("data:image/jpeg;base64,".count))),
                      let image = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                      properties[kCGImagePropertyPixelWidth] as? Int == 640,
                      properties[kCGImagePropertyPixelHeight] as? Int == 360 else {
                    throw PublishError.message("The viewer did not produce a 640 × 360 JPEG thumbnail.")
                }
                try data.write(to: destination, options: .atomic)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PublishError.message("The interactive viewer could not render its thumbnail within 30 seconds.")
    }
}
