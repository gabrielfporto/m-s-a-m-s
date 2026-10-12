import UIKit
import WebKit
import SafariServices

/// Native WebKit shell. Financial records and service credentials stay on the private server.
/// Login and institution authorization must be validated on a physical iPhone before distribution.
final class FinanceViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let home = URL(string: "https://mes-a-mes-financas.rosycream3.chatgpt.site/")!
    private var webView: WKWebView!
    private var progress: UIProgressView!
    private var progressObservation: NSKeyValueObservation?
    private var popupViews: [WKWebView] = []
    private var downloadURLs: [ObjectIdentifier: URL] = [:]
    private var isRecovering = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        progress = UIProgressView(progressViewStyle: .bar)
        progress.tintColor = UIColor(red: 0.75, green: 0.64, blue: 0.30, alpha: 1)
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.progress.setProgress(Float(webView.estimatedProgress), animated: true)
                self.progress.isHidden = webView.estimatedProgress >= 1
            }
        }
        webView.load(URLRequest(url: home))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        switch url.scheme?.lowercased() {
        case "https", "about", "blob", "data": decisionHandler(.allow)
        case "http": decisionHandler(.cancel)
        default:
            decisionHandler(.cancel)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // Preserve the original page and its Pluggy callback while bank/login popups are open.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.scrollView.contentInsetAdjustmentBehavior = .automatic
        popup.allowsBackForwardNavigationGestures = true
        view.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            popup.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        popupViews.append(popup)
        let close = UIButton(type: .system)
        close.setTitle("Fechar autorização", for: .normal)
        close.addTarget(self, action: #selector(closeLatestPopup), for: .touchUpInside)
        close.backgroundColor = view.backgroundColor
        close.accessibilityLabel = "Fechar janela de autorização"
        close.tag = 9001
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            close.heightAnchor.constraint(equalToConstant: 44)
        ])
        return popup
    }

    @objc private func closeLatestPopup() {
        popupViews.popLast()?.removeFromSuperview()
        if popupViews.isEmpty { view.subviews.filter { $0.tag == 9001 }.forEach { $0.removeFromSuperview() } }
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupViews.removeAll { $0 === webView }
        webView.removeFromSuperview()
        if popupViews.isEmpty { view.subviews.filter { $0.tag == 9001 }.forEach { $0.removeFromSuperview() } }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isRecovering = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }
    private func showError(_ error: Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled, presentedViewController == nil else { return }
        progress.isHidden = true
        let alert = UIAlertController(title: "Não foi possível carregar",
                                      message: "Verifique sua conexão. Seus dados continuam no servidor.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tentar novamente", style: .default) { [weak self] _ in
            guard let self = self else { return }; self.webView.load(URLRequest(url: self.home))
        })
        alert.addAction(UIAlertAction(title: "Abrir no Safari", style: .default) { [weak self] _ in
            guard let self = self else { return }; self.present(SFSafariViewController(url: self.home), animated: true)
        })
        present(alert, animated: true)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !isRecovering else { return }; isRecovering = true; webView.reload()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Mês a mês", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Mês a mês", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Confirmar", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let name = (suggestedFilename as NSString).lastPathComponent
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name.isEmpty ? "movimentacoes.csv" : name)
            downloadURLs[ObjectIdentifier(download)] = url
            completionHandler(url)
        } catch { completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadURLs.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        present(share, animated: true)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let url = downloadURLs.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        showError(error)
    }
}
