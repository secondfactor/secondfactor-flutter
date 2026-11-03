import AuthenticationServices
import Flutter
import UIKit

/// The iOS half of `SecondFactor.verify`: opens the hosted page in an
/// `ASWebAuthenticationSession` and answers with the URL it returned to.
///
/// The Dart side has already checked the page URL and split the return URL
/// into a host and a path. The session closes by itself when the page sends
/// the user to that `https://` host and path, which needs iOS 17.4 and the
/// Associated Domains entitlement `webcredentials:<host>`.
public final class SecondFactorPlugin: NSObject, FlutterPlugin, ASWebAuthenticationPresentationContextProviding {
    /// The session being shown. Held so it stays alive until it finishes.
    private var session: ASWebAuthenticationSession?
    private var anchor: UIWindow?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ai.secondfactor/verify", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SecondFactorPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "verify" else {
            return result(FlutterMethodNotImplemented)
        }
        guard #available(iOS 17.4, *) else {
            return result(FlutterError(code: "couldNotStart", message: "SecondFactor.verify needs iOS 17.4 or later.", details: nil))
        }
        guard let args = call.arguments as? [String: String],
              let url = args["url"].flatMap(URL.init(string:)),
              let host = args["host"], let path = args["path"] else {
            return result(FlutterError(code: "couldNotStart", message: "Bad arguments.", details: nil))
        }
        guard let window = Self.presentationWindow() else {
            return result(FlutterError(code: "couldNotStart", message: "There is no window to show the page over.", details: nil))
        }

        // Only one verification at a time. A second call means the first is no
        // longer wanted; canceling it reports `canceled` to its caller.
        session?.cancel()

        // `finish` may be reached twice, from a failed `start()` and from the
        // completion handler, but a Flutter result must be answered only once.
        // It lets go of the session only if no newer one has replaced it, and
        // clears its own reference to break the session → handler → session
        // cycle.
        var session: ASWebAuthenticationSession?
        let finish: (Any?) -> Void = { [weak self] answer in
            guard let finished = session else { return }
            session = nil
            if self?.session === finished { self?.session = nil }
            result(answer)
        }

        session = ASWebAuthenticationSession(url: url, callback: .https(host: host, path: path)) { callbackURL, error in
            DispatchQueue.main.async {
                if let callbackURL {
                    finish(callbackURL.absoluteString)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    finish(FlutterError(code: "canceled", message: "The user closed the page.", details: nil))
                } else {
                    let error = error as NSError?
                    finish(FlutterError(code: "\(error?.domain ?? "unknown") \(error?.code ?? 0)", message: error?.localizedDescription, details: nil))
                }
            }
        }
        guard let session else { return }
        session.presentationContextProvider = self
        // The hosted page needs no cookies from Safari, and none of its own
        // should outlive this one verification.
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        anchor = window
        if !session.start() {
            finish(FlutterError(code: "couldNotStart", message: "The page could not be shown.", details: nil))
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    /// The key window of a connected scene, or failing that the first window.
    private static func presentationWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
