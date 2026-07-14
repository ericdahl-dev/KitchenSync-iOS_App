import Foundation

/// `application/x-www-form-urlencoded` encoding matched against the firmware's
/// own decoder (`url_decode()` in `KitchenSync/main/ks_form.c`), which handles
/// arbitrary `%XX` plus `+` as space. This encoder never emits a literal `+`
/// (a value containing one is percent-encoded to `%2B`), so there's no
/// ambiguity to resolve on the decode side either — every byte outside
/// RFC 3986's unreserved set is `%XX`-encoded, full stop.
enum FormURLEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ fields: [String: String]) -> Data {
        let pairs = fields
            .sorted { $0.key < $1.key }   // stable order — easier to read in a request log
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}
