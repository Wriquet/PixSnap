import Vision
import CoreGraphics
import Cocoa

public final class OCREngine: @unchecked Sendable {
    public static let shared = OCREngine()

    public struct OCRResult: Sendable {
        public let fullText: String
        public let lines: [String]
        public let qrCodes: [String]

        public init(fullText: String, lines: [String], qrCodes: [String] = []) {
            self.fullText = fullText
            self.lines = lines
            self.qrCodes = qrCodes
        }
    }

    public func recognizeText(from cgImage: CGImage) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            var recognizedLines: [String] = []
            var recognizedError: Error?

            let textRequest = VNRecognizeTextRequest { request, error in
                if let error = error {
                    recognizedError = error
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                for observation in observations {
                    if let top = observation.topCandidates(1).first {
                        recognizedLines.append(top.string)
                    }
                }
            }
            textRequest.recognitionLevel = .accurate
            textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
            textRequest.automaticallyDetectsLanguage = true
            textRequest.usesLanguageCorrection = true

            var detectedCodes: [String] = []
            let barcodeRequest = VNDetectBarcodesRequest { request, _ in
                guard let observations = request.results as? [VNBarcodeObservation] else { return }
                for obs in observations {
                    if let payload = obs.payloadStringValue, !payload.isEmpty, !detectedCodes.contains(payload) {
                        detectedCodes.append(payload)
                    }
                }
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([textRequest, barcodeRequest])

            if let err = recognizedError {
                throw err
            }

            let fullText = recognizedLines.joined(separator: "\n")
            return OCRResult(fullText: fullText, lines: recognizedLines, qrCodes: detectedCodes)
        }.value
    }
}
