import AuthenticationServices
import CryptoKit
import Foundation
import SafariServices
import Security
import SwiftUI
import UIKit

struct GooglePhotosDownloadedMedia: Sendable {
    let url: URL
    let mimeType: String
    let createdAt: Date?
}

enum GooglePhotosPickerError: LocalizedError {
    case missingConfiguration
    case authenticationCancelled
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Google 포토 연결 설정을 찾을 수 없습니다."
        case .authenticationCancelled:
            "Google 포토 연결을 취소했습니다."
        case .invalidResponse:
            "Google 포토에서 올바른 응답을 받지 못했습니다."
        case .server(let message):
            "Google 포토 오류: \(message)"
        }
    }
}

@MainActor
final class GooglePhotosPickerService: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    static let shared = GooglePhotosPickerService()

    private let scope =
        "https://www.googleapis.com/auth/photospicker.mediaitems.readonly"
    private let tokenStore = GooglePhotosTokenStore()
    private var authenticationSession: ASWebAuthenticationSession?

    private var clientID: String? {
        Bundle.main.object(
            forInfoDictionaryKey: "GooglePhotosOAuthClientID"
        ) as? String
    }

    private var callbackScheme: String? {
        guard let clientID else { return nil }
        return "com.googleusercontent.apps."
            + clientID.replacingOccurrences(
                of: ".apps.googleusercontent.com",
                with: ""
            )
    }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func accessToken() async throws -> String {
        if let token = tokenStore.accessToken,
           tokenStore.expirationDate.timeIntervalSinceNow > 60 {
            return token
        }
        if let refreshToken = tokenStore.refreshToken {
            do {
                return try await refreshAccessToken(refreshToken)
            } catch {
                tokenStore.clear()
            }
        }
        return try await authorize()
    }

    func createSession(accessToken: String) async throws
        -> (id: String, pickerURL: URL)
    {
        var request = URLRequest(
            url: URL(string: "https://photospicker.googleapis.com/v1/sessions")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let response: PickerSession = try await perform(request)
        guard let pickerURL = URL(string: response.pickerUri) else {
            throw GooglePhotosPickerError.invalidResponse
        }
        return (response.id, pickerURL)
    }

    func waitForSelection(
        sessionID: String,
        accessToken: String
    ) async throws {
        while !Task.isCancelled {
            var request = URLRequest(
                url: URL(
                    string: "https://photospicker.googleapis.com/v1/sessions/\(sessionID)"
                )!
            )
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let session: PickerSession = try await perform(request)
            if session.mediaItemsSet == true { return }
            let seconds = max(1, session.pollingConfig?.pollIntervalSeconds ?? 2)
            try await Task.sleep(for: .seconds(seconds))
        }
        throw CancellationError()
    }

    func downloadSelectedMedia(
        sessionID: String,
        accessToken: String,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [GooglePhotosDownloadedMedia] {
        var items: [PickedMediaItem] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(
                string: "https://photospicker.googleapis.com/v1/mediaItems"
            )!
            var queryItems = [
                URLQueryItem(name: "sessionId", value: sessionID),
                URLQueryItem(name: "pageSize", value: "100")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let page: PickedMediaPage = try await perform(request)
            items.append(contentsOf: page.mediaItems ?? [])
            pageToken = page.nextPageToken
        } while pageToken?.isEmpty == false

        var downloads: [GooglePhotosDownloadedMedia] = []
        downloads.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            guard let mediaFile = item.mediaFile,
                  let baseURL = URL(
                    string: mediaFile.baseUrl
                        + (mediaFile.mimeType.hasPrefix("video/") ? "=dv" : "=d")
                  )
            else { continue }
            var request = URLRequest(url: baseURL)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { throw GooglePhotosPickerError.invalidResponse }
            let filename = mediaFile.filename.isEmpty
                ? UUID().uuidString
                : mediaFile.filename
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("GooglePhotos-\(UUID().uuidString)-\(filename)")
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            downloads.append(
                GooglePhotosDownloadedMedia(
                    url: destination,
                    mimeType: mediaFile.mimeType,
                    createdAt: Self.googleDateFormatter.date(from: item.createTime ?? "")
                )
            )
            await progress(index + 1, items.count)
        }
        return downloads
    }

    func deleteSession(sessionID: String, accessToken: String) async {
        var request = URLRequest(
            url: URL(
                string: "https://photospicker.googleapis.com/v1/sessions/\(sessionID)"
            )!
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func authorize() async throws -> String {
        guard let clientID, let callbackScheme else {
            throw GooglePhotosPickerError.missingConfiguration
        }
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(
            Data(SHA256.hash(data: Data(verifier.utf8)))
        )
        let state = Self.randomURLSafeString(byteCount: 24)
        let redirectURI = "\(callbackScheme):/oauth2redirect"
        var components = URLComponents(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authorizationURL = components.url else {
            throw GooglePhotosPickerError.missingConfiguration
        }

        let callbackURL = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: GooglePhotosPickerError.authenticationCancelled
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            session.start()
        }
        authenticationSession = nil
        let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let values = Dictionary(
            uniqueKeysWithValues: (callback?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        guard values["state"] == state, let code = values["code"] else {
            throw GooglePhotosPickerError.invalidResponse
        }
        return try await exchangeCode(
            code,
            verifier: verifier,
            redirectURI: redirectURI,
            clientID: clientID
        )
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: String,
        clientID: String
    ) async throws -> String {
        try await requestToken([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        guard let clientID else { throw GooglePhotosPickerError.missingConfiguration }
        return try await requestToken([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
    }

    private func requestToken(_ parameters: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key.urlQueryEncoded)=\(value.urlQueryEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let response: TokenResponse = try await perform(request)
        tokenStore.save(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresIn: response.expiresIn
        )
        return response.accessToken
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GooglePhotosPickerError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(
                GoogleErrorEnvelope.self,
                from: data
            ))?.error.message ?? "HTTP \(http.statusCode)"
            throw GooglePhotosPickerError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let googleDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct GooglePhotosPickerWebView: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .cancel
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onClose()
        }
    }
}

private final class GooglePhotosTokenStore {
    private let service = "com.intosharp.hanclip.googlephotos"
    private let defaults = UserDefaults.standard

    var accessToken: String? { read("access-token") }
    var refreshToken: String? { read("refresh-token") }
    var expirationDate: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: "googlePhotosTokenExpiry"))
    }

    func save(accessToken: String, refreshToken: String?, expiresIn: Int) {
        write(accessToken, account: "access-token")
        if let refreshToken { write(refreshToken, account: "refresh-token") }
        defaults.set(
            Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970,
            forKey: "googlePhotosTokenExpiry"
        )
    }

    func clear() {
        delete("access-token")
        delete("refresh-token")
        defaults.removeObject(forKey: "googlePhotosTokenExpiry")
    }

    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct PickerSession: Decodable {
    let id: String
    let pickerUri: String
    let mediaItemsSet: Bool?
    let pollingConfig: PollingConfig?
}

private struct PollingConfig: Decodable {
    let pollInterval: String?
    var pollIntervalSeconds: Double? {
        guard let pollInterval else { return nil }
        return Double(pollInterval.trimmingCharacters(in: CharacterSet(charactersIn: "s")))
    }
}

private struct PickedMediaPage: Decodable {
    let mediaItems: [PickedMediaItem]?
    let nextPageToken: String?
}

private struct PickedMediaItem: Decodable {
    let createTime: String?
    let mediaFile: PickedMediaFile?
}

private struct PickedMediaFile: Decodable {
    let baseUrl: String
    let mimeType: String
    let filename: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct GoogleErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "-._~"))
        ) ?? self
    }
}
