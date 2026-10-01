/// Page scripts shared by every service. Each lives in its own file as a static string;
/// `Scripts.shared(spatialNav:pageLog:)` says which of them a web view gets, and when.
enum Scripts {}

extension Scripts {
    /// The scripts every web view gets, before the service's own (see `ServiceModule.scripts`).
    /// `pageLog` forwards everything the page logs, not just its warnings and errors.
    static func shared(spatialNav: Bool, pageLog: Bool = false) -> [PageScript] {
        var list = [
            // First, so it also catches errors in the scripts after it.
            PageScript(source: console(everything: pageLog), time: .start),
            PageScript(source: hdr, time: .start, mainFrameOnly: false),
            PageScript(source: probe, time: .start),
            PageScript(source: mediaVolume, time: .start),
            PageScript(source: playback, time: .start),
            PageScript(source: keyboard, time: .start),
        ]
        if spatialNav { list.append(PageScript(source: Scripts.spatialNav, time: .start)) }
        return list
    }
}
