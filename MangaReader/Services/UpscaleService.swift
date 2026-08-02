import CoreGraphics
import Darwin
import Foundation
import UIKit

enum UpscaleError: LocalizedError {
    case modelMissing(String)
    case sessionFailed(String)
    case runFailed(String)
    case outputShapeMismatch(expected: String, actual: String)
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .modelMissing(let name):
            return "Model file is missing: \(name)"
        case .sessionFailed(let message):
            return "Unable to load ONNX session: \(message)"
        case .runFailed(let message):
            return "ONNX inference failed: \(message)"
        case .outputShapeMismatch(let expected, let actual):
            return "Output shape \(actual) does not match expected \(expected)."
        case .outputTooLarge:
            return "Enhanced image exceeds the 16384 pixel limit."
        }
    }
}

actor UpscaleService {
    static let maxOutputEdge = 16384

    private let env: ORTEnv?
    private var sessions: [UUID: ORTSession] = [:]

    init() {
        self.env = try? ORTEnv(loggingLevel: .warning)
    }

    func validate(_ profile: ModelProfile) async throws -> (width: Int, height: Int) {
        let width = 64
        let height = 64
        var rgba = [UInt8](repeating: 128, count: width * height * 4)
        for index in stride(from: 3, to: rgba.count, by: 4) {
            rgba[index] = 255
        }
        let output = try runOnBuffer(
            width: width,
            height: height,
            rgba: rgba,
            profile: profile
        )
        let expectedWidth = width * profile.scale
        let expectedHeight = height * profile.scale
        guard output.width == expectedWidth, output.height == expectedHeight else {
            throw UpscaleError.outputShapeMismatch(
                expected: "\(expectedWidth)x\(expectedHeight)",
                actual: "\(output.width)x\(output.height)"
            )
        }
        return (output.width, output.height)
    }

    func enhance(image: UIImage, profile: ModelProfile) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cgImage = normalized.cgImage else {
            throw UpscaleError.sessionFailed("image has no CGImage")
        }
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw UpscaleError.sessionFailed("unable to create bitmap context")
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let output = try runOnBuffer(width: width, height: height, rgba: rgba, profile: profile)
        guard output.width <= Self.maxOutputEdge, output.height <= Self.maxOutputEdge else {
            throw UpscaleError.outputTooLarge
        }
        return try imageFromRGBABuffer(output.rgba, width: output.width, height: output.height)
    }

    func invalidateSession(for profileID: UUID) {
        sessions[profileID] = nil
    }

    private func session(for profile: ModelProfile) throws -> ORTSession {
        if let cached = sessions[profile.id] {
            return cached
        }
        guard let env else {
            throw UpscaleError.sessionFailed("ORT environment unavailable")
        }
        guard let modelURL = profile.modelURL,
              FileManager.default.fileExists(atPath: modelURL.path) else {
            throw UpscaleError.modelMissing(profile.modelFileName)
        }

        let options = ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)
        try options.setLogSeverityLevel(.warning)

        if profile.executionProvider != .cpu {
            let coreMLOptions = ORTCoreMLExecutionProviderOptions()
            coreMLOptions.createMLProgram = true
            coreMLOptions.onlyAllowStaticInputShapes = true
            try options.appendCoreMLExecutionProvider(with: coreMLOptions)
        }

        let session = try ORTSession(
            env: env,
            modelPath: modelURL.path,
            sessionOptions: options
        )
        sessions[profile.id] = session
        return session
    }

    private func runOnBuffer(
        width: Int,
        height: Int,
        rgba: [UInt8],
        profile: ModelProfile
    ) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let session = try session(for: profile)
        let tileSize = max(32, profile.tileSize)
        let overlap = min(max(0, profile.overlap), tileSize / 2)
        let outTile = tileSize * profile.scale
        let outWidth = width * profile.scale
        let outHeight = height * profile.scale
        guard outWidth <= Self.maxOutputEdge, outHeight <= Self.maxOutputEdge else {
            throw UpscaleError.outputTooLarge
        }

        var output = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        var weights = [Float](repeating: 0, count: outWidth * outHeight)
        var colorAccumulator = [Float](repeating: 0, count: outWidth * outHeight * 3)

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let tileW = min(tileSize, width - x)
                let tileH = min(tileSize, height - y)
                let input = extractTile(rgba: rgba, sourceWidth: width, x: x, y: y, tileW: tileW, tileH: tileH, profile: profile)
                let result = try runTile(
                    session: session,
                    input: input,
                    tileW: tileW,
                    tileH: tileH,
                    profile: profile
                )
                blendTile(
                    result: result,
                    into: &output,
                    colors: &colorAccumulator,
                    weights: &weights,
                    outputWidth: outWidth,
                    x: x * profile.scale,
                    y: y * profile.scale,
                    tileW: tileW * profile.scale,
                    tileH: tileH * profile.scale,
                    overlap: overlap * profile.scale,
                    maxValue: profile.normalization == .zeroToOne ? 255 : 1
                )
                x += tileSize - overlap
            }
            y += tileSize - overlap
        }

        for index in 0..<output.count / 4 {
            let weight = weights[index]
            guard weight > 0 else { continue }
            let base = index * 3
            output[index * 4] = UInt8(clamping: Int(colorAccumulator[base] / weight))
            output[index * 4 + 1] = UInt8(clamping: Int(colorAccumulator[base + 1] / weight))
            output[index * 4 + 2] = UInt8(clamping: Int(colorAccumulator[base + 2] / weight))
            output[index * 4 + 3] = 255
        }

        return (outWidth, outHeight, output)
    }

    private func runTile(
        session: ORTSession,
        input: [Float],
        tileW: Int,
        tileH: Int,
        profile: ModelProfile
    ) throws -> [Float] {
        let count = tileW * tileH * 3
        let data = NSMutableData(data: input.withUnsafeBytes { Data($0) })
        let value = try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: [1, 3, tileH, tileW].map { NSNumber(value: $0) }
        )

        let outputs = try session.run(
            withInputs: [profile.inputName: value],
            outputNames: [profile.outputName],
            runOptions: nil
        )
        guard let outputValue = outputs[profile.outputName] else {
            throw UpscaleError.runFailed("run failed")
        }

        let shapeInfo = try outputValue.tensorTypeAndShapeInfo()
        let outputData = try outputValue.tensorData() as Data
        let shape = shapeInfo.shape.compactMap { $0.intValue }
        guard shape.count == 4 else {
            throw UpscaleError.outputShapeMismatch(expected: "1x3xHxW", actual: shape.map(String.init).joined(separator: "x"))
        }
        let outH = shape[2]
        let outW = shape[3]
        guard outH == tileH * profile.scale, outW == tileW * profile.scale else {
            throw UpscaleError.outputShapeMismatch(
                expected: "1x3x\(tileH * profile.scale)x\(tileW * profile.scale)",
                actual: shape.map(String.init).joined(separator: "x")
            )
        }

        let floatCount = outH * outW * 3
        var floats = [Float](repeating: 0, count: floatCount)
        outputData.withUnsafeBytes { rawBuffer in
            let pointer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                floats[i] = pointer[i]
            }
        }
        return floats
    }

    private func extractTile(
        rgba: [UInt8],
        sourceWidth: Int,
        x: Int,
        y: Int,
        tileW: Int,
        tileH: Int,
        profile: ModelProfile
    ) -> [Float] {
        var input = [Float](repeating: 0, count: tileW * tileH * 3)
        for row in 0..<tileH {
            for col in 0..<tileW {
                let sourceIndex = ((y + row) * sourceWidth + (x + col)) * 4
                let red = Float(rgba[sourceIndex])
                let green = Float(rgba[sourceIndex + 1])
                let blue = Float(rgba[sourceIndex + 2])
                let alpha = Float(rgba[sourceIndex + 3])
                let blendedRed = alpha < 255 ? red + (255 - alpha) : red
                let blendedGreen = alpha < 255 ? green + (255 - alpha) : green
                let blendedBlue = alpha < 255 ? blue + (255 - alpha) : blue
                let normalized = profile.normalization == .zeroToOne
                let r = normalized ? blendedRed / 255 : blendedRed
                let g = normalized ? blendedGreen / 255 : blendedGreen
                let b = normalized ? blendedBlue / 255 : blendedBlue
                let target = (row * tileW + col) * 3
                if profile.colorSpace == .bgr {
                    input[target] = b
                    input[target + 1] = g
                    input[target + 2] = r
                } else {
                    input[target] = r
                    input[target + 1] = g
                    input[target + 2] = b
                }
            }
        }
        return input
    }

    private func blendTile(
        result: [Float],
        into output: inout [UInt8],
        colors: inout [Float],
        weights: inout [Float],
        outputWidth: Int,
        x: Int,
        y: Int,
        tileW: Int,
        tileH: Int,
        overlap: Int,
        maxValue: Float
    ) {
        for row in 0..<tileH {
            for col in 0..<tileW {
                let outX = x + col
                let outY = y + row
                guard outX >= 0, outY >= 0, outX < outputWidth, outY < output.count / 4 / outputWidth else {
                    continue
                }
                let edgeX = min(col + 1, tileW - col, overlap + 1)
                let edgeY = min(row + 1, tileH - row, overlap + 1)
                let weight = Float(min(edgeX, edgeY))
                let pixel = outY * outputWidth + outX
                let base = pixel * 3
                let tileBase = (row * tileW + col) * 3
                let r = result[tileBase]
                let g = result[tileBase + 1]
                let b = result[tileBase + 2]
                colors[base] += r * maxValue * weight
                colors[base + 1] += g * maxValue * weight
                colors[base + 2] += b * maxValue * weight
                weights[pixel] += weight
            }
        }
    }

    private func imageFromRGBABuffer(_ rgba: [UInt8], width: Int, height: Int) throws -> UIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw UpscaleError.sessionFailed("unable to create output context")
        }
        rgba.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                if let destination = context.data {
                    memcpy(destination, baseAddress, buffer.count)
                }
            }
        }
        guard let cgImage = context.makeImage() else {
            throw UpscaleError.sessionFailed("unable to create output image")
        }
        return UIImage(cgImage: cgImage)
    }
}
