import Foundation
import Network

/// Enumerates KitchenSync units on the LAN.
///
/// The firmware advertises **generic** `_http._tcp` (`KitchenSync/main/wifi_link.c`,
/// ESP-012 — `mdns_service_add(NULL, "_http", "_tcp", 80, NULL, 0)`) with no
/// distinguishing TXT record or service subtype, so this browses every
/// `_http._tcp` responder on the network and filters by the mDNS hostname the
/// firmware actually uses (`kitchensync-XXXX` / the delegated `kitchensync`
/// alias — passing a null instance name to `mdns_service_add` makes ESP-IDF
/// default the Bonjour instance name to the hostname, so the browse result's
/// service name IS that hostname). That's a heuristic, not a guarantee — see
/// `docs/plans/2026-07-14-ios-kitchensync-app-plan.md` in `link-devices` for
/// the firmware-side TXT-record fix that would make this exact instead of
/// prefix-matched.
///
/// Deliberately does NOT resolve the matched service to a raw IP via
/// `NWConnection` (the usual Network.framework recipe for that opens a real TCP
/// connection just to read back the resolved endpoint). Instead this hands the
/// hostname straight back as `<name>.local`, and `URLSession` resolves that
/// through the system's mDNS responder exactly the way Safari resolves it when
/// you open the device's own web UI — one resolution path, not two.
final class KitchenSyncDiscovery {
    var onHostnamesChanged: ((Set<String>) -> Void)?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "dev.ericdahl.kitchensync.discovery")

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let matched = results.compactMap { result -> String? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                // The decision lives in `DeviceMatch` — a pure function with tests. This glue
                // only extracts the two inputs. TXT wins when present; the hostname is the
                // fallback for units that haven't been reflashed (see `DeviceMatch`).
                return DeviceMatch.isKitchenSync(serviceName: name, txt: Self.txt(of: result))
                    ? name : nil
            }
            self?.onHostnamesChanged?(Set(matched))
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// The TXT record, if the responder published one. Firmware doesn't yet (`link-devices`
    /// ESP-031), so this is `nil` for every unit in the field today — which is exactly why
    /// `DeviceMatch` keeps a hostname fallback.
    private static func txt(of result: NWBrowser.Result) -> [String: String]? {
        guard case let .bonjour(record) = result.metadata else { return nil }
        var entries: [String: String] = [:]
        for (key, entry) in record {
            if case let .string(value) = entry {
                entries[key] = value
            }
        }
        return entries.isEmpty ? nil : entries
    }
}
