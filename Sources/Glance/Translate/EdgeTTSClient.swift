import Foundation
import CryptoKit

/// Client for Microsoft Edge Read Aloud Text-to-Speech WebSocket API.
/// Generates high-quality neural voice audio (MP3) without requiring third-party API keys.
final class EdgeTTSClient {
    enum EdgeTTSError: LocalizedError {
        case invalidURL
        case connectionFailed(String)
        case synthesisFailed(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Edge TTS WebSocket URL"
            case .connectionFailed(let message):
                return "Edge TTS connection failed: \(message)"
            case .synthesisFailed(let message):
                return "Edge TTS synthesis error: \(message)"
            case .emptyAudio:
                return "Edge TTS returned no audio data"
            }
        }
    }

    private static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let chromiumFullVersion = "143.0.3650.75"
    private static let chromiumMajor = "143"
    private static let secMSGECVersion = "1-\(chromiumFullVersion)"

    /// Generates the dynamic Sec-MS-GEC verification token based on 5-minute Windows epoch time intervals.
    static func generateSecMSGECToken(date: Date = Date()) -> String {
        let unixSec = date.timeIntervalSince1970
        let winEpochOffset: Double = 11_644_473_600
        var ticks = unixSec + winEpochOffset
        ticks -= ticks.truncatingRemainder(dividingBy: 300) // Round down to 5-minute window
        ticks *= 10_000_000.0 // 100-nanosecond intervals (Windows filetime ticks)
        let ticksStr = String(format: "%.0f", ticks)

        let hashInput = "\(ticksStr)\(trustedClientToken)"
        let digest = SHA256.hash(data: Data(hashInput.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// Generates a random 32-hex-character cookie token for MUID.
    private static func generateMUID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// Formats a JavaScript-style UTC date string matching Microsoft Edge requirements.
    private static func dateToString(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: date)
    }

    /// Synthesizes speech from text using Microsoft Edge Neural TTS over WebSocket.
    static func synthesize(text: String,
                           voice: String,
                           rate: Double = 1.0) async throws -> Data {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw EdgeTTSError.emptyAudio }

        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let token = generateSecMSGECToken()
        let urlString = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(trustedClientToken)&ConnectionId=\(connectionId)&Sec-MS-GEC=\(token)&Sec-MS-GEC-Version=\(secMSGECVersion)"

        guard let url = URL(string: urlString) else {
            throw EdgeTTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromiumMajor).0.0.0 Safari/537.36 Edg/\(chromiumMajor).0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("muid=\(generateMUID());", forHTTPHeaderField: "Cookie")

        let session = URLSession(configuration: .default)
        let webSocket = session.webSocketTask(with: request)
        webSocket.resume()

        defer {
            webSocket.cancel(with: .normalClosure, reason: nil)
        }

        let dateStr = dateToString()

        // 1. Send speech.config
        let configPayload = "X-Timestamp:\(dateStr)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
        try await webSocket.send(.string(configPayload))

        // 2. Format rate prosody (+10%, -15%, etc.)
        let ratePct = Int((rate - 1.0) * 100)
        let rateStr = ratePct >= 0 ? "+\(ratePct)%" : "\(ratePct)%"

        // 3. Escape SSML special characters
        let escapedText = cleanText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        let langPrefix = voice.components(separatedBy: "-").prefix(2).joined(separator: "-")
        let reqId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(langPrefix)'><voice name='\(voice)'><prosody pitch='+0Hz' rate='\(rateStr)' volume='+0%'>\(escapedText)</prosody></voice></speak>"
        let ssmlPayload = "X-RequestId:\(reqId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(dateStr)Z\r\nPath:ssml\r\n\r\n\(ssml)"
        try await webSocket.send(.string(ssmlPayload))

        // 4. Receive and accumulate audio data chunks
        var audioAccumulator = Data()
        var isTurnEnd = false

        while !isTurnEnd {
            let message = try await webSocket.receive()
            switch message {
            case .string(let str):
                if str.contains("Path:turn.end") {
                    isTurnEnd = true
                }
            case .data(let data):
                guard data.count >= 2 else { continue }
                // First 2 bytes are big-endian uint16 indicating the header length
                let headerLength = Int(data[0]) << 8 | Int(data[1])
                let headerOffset = 2 + headerLength
                if data.count > headerOffset {
                    let audioChunk = data.subdata(in: headerOffset..<data.count)
                    audioAccumulator.append(audioChunk)
                }
            @unknown default:
                break
            }
        }

        guard !audioAccumulator.isEmpty else {
            throw EdgeTTSError.emptyAudio
        }

        return audioAccumulator
    }
}
