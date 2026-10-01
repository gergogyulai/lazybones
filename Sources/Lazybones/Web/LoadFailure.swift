import Foundation

/// A page that couldn't be reached, and what to say about it. Only failures the user can do
/// something about count: a redirect cancelling the previous load, or a download taking over from
/// a page, aren't failures anyone should see.
struct LoadFailure: Equatable {
    enum Reason: Equatable {
        /// This Mac has no network, which `retryWhenOnline` waits out.
        case offline
        case unreachable
        case insecure
        case other(String)
    }

    let reason: Reason
    /// What was being loaded, to load again on Try Again.
    let url: URL?
    /// Nothing had loaded in this app yet, so there's no page to go back to.
    let firstLoad: Bool

    init?(_ error: Error, firstLoad: Bool) {
        let e = error as NSError
        switch (e.domain, e.code) {
        case (NSURLErrorDomain, NSURLErrorCancelled),
             // WebKit's legacy domain (not `WKError.errorDomain`, which is "WKErrorDomain").
             // Frame load interrupted: a policy decision (e.g. a download) replaced the navigation.
             (Self.webKitDomain, 102),
             // A plug-in or media document took over the load.
             (Self.webKitDomain, 204):
            return nil
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet),
             (NSURLErrorDomain, NSURLErrorNetworkConnectionLost),
             (NSURLErrorDomain, NSURLErrorDataNotAllowed),
             (NSURLErrorDomain, NSURLErrorInternationalRoamingOff):
            reason = .offline
        case (NSURLErrorDomain, NSURLErrorCannotFindHost),
             (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
             (NSURLErrorDomain, NSURLErrorTimedOut),
             (NSURLErrorDomain, NSURLErrorDNSLookupFailed):
            reason = .unreachable
        // -1206...-1200: TLS failed, or a certificate was bad, untrusted, expired or missing.
        case (NSURLErrorDomain, NSURLErrorClientCertificateRequired...NSURLErrorSecureConnectionFailed):
            reason = .insecure
        default:
            reason = .other(e.localizedDescription)
        }
        url = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        self.firstLoad = firstLoad
    }

    private static let webKitDomain = "WebKitErrorDomain"

    /// Worth trying again by itself when the network comes back.
    var retryWhenOnline: Bool { reason == .offline || reason == .unreachable }

    var symbol: String {
        switch reason {
        case .offline: "wifi.exclamationmark"
        case .unreachable: "exclamationmark.icloud"
        case .insecure: "lock.trianglebadge.exclamationmark"
        case .other: "exclamationmark.triangle"
        }
    }

    func title(for s: Service) -> String { "Can’t Open \(s.name)" }

    func message(for s: Service) -> String {
        let host = url?.host() ?? s.url.host() ?? s.name
        return switch reason {
        case .offline: "This Mac isn’t connected to the internet."
        case .unreachable: "\(host) isn’t responding. Try again later."
        case .insecure: "A secure connection to \(host) couldn’t be made."
        case let .other(description): description
        }
    }
}
