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

    /// Why the list is empty. Nothing used to ask this question, so a device that was
    /// powered, on the network and audibly following Link looked identical to no device at
    /// all — see `DiscoveryStatus`.
    var onStatusChanged: ((DiscoveryStatus) -> Void)?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "dev.ericdahl.kitchensync.discovery")

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)

        // There was NO state handler here at all. A browser that iOS refused (Local Network
        // permission) or that died on a network drop stayed dead, forever, in total silence:
        // no devices, no error, nothing to go on. NWBrowser does not recover from `.failed`
        // by itself, so somebody has to restart it, and nobody can if nobody is told.
        browser.stateUpdateHandler = { [weak self] state in
            let status = DiscoveryStatus(browserState: state)
            self?.onStatusChanged?(status)

            // A denial is NOT restartable — iOS will refuse the new browser exactly as it
            // refused this one, and retrying in a loop would just hide the one fact the user
            // needs. Only a genuine failure gets another go.
            if status == .failed { self?.restart() }
        }

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
        browser?.stateUpdateHandler = nil   // cancelling is not news; don't report .stopped
        browser?.cancel()
        browser = nil
    }

    /// Rebuild the browser after a genuine failure. Backed off a little, because a network
    /// that just dropped will not be back within the millisecond, and a hot retry loop
    /// would burn the radio for nothing.
    private func restart() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.browser != nil else { return }   // stop() won the race
            self.browser?.cancel()
            self.browser = nil
            self.start()
        }
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
