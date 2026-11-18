import Foundation
import WebKit
import Combine

@MainActor
final class WebSessionCoordinator: NSObject, ObservableObject, WKNavigationDelegate {
    private let allowedHosts: Set<String> = [
        "xiaohongshu.com",
        "www.xiaohongshu.com",
        "live-room.xiaohongshu.com",
    ]

    private(set) var webView: WKWebView?
    private var loginContinuation: CheckedContinuation<String, Error>?

    func prepareLoginWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    func loginXiaohongshu() async throws -> String {
        guard loginContinuation == nil else { throw WebSessionError.alreadyRunning }
        let webView = prepareLoginWebView()
        guard let url = URL(string: "https://www.xiaohongshu.com/") else {
            throw WebSessionError.invalidURL
        }
        webView.load(URLRequest(url: url))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                loginContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(WebSessionError.cancelled))
            }
        }
    }

    func close() {
        finish(.failure(WebSessionError.cancelled))
        webView?.navigationDelegate = nil
        webView = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let host = navigationAction.request.url?.host?.lowercased(),
              allowedHosts.contains(host) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let relevant = cookies.filter { cookie in
                self?.allowedHosts.contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()) == true
            }
            guard !relevant.isEmpty else { return }
            let header = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            Task { @MainActor in self?.finish(.success(header)) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = loginContinuation else { return }
        loginContinuation = nil
        continuation.resume(with: result)
    }
}

enum WebSessionError: LocalizedError {
    case alreadyRunning
    case invalidURL
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "网页登录已经在进行中"
        case .invalidURL: "网页登录地址无效"
        case .cancelled: "网页登录已取消"
        }
    }
}
