import XCTest
@testable import KitchenSyncApp

/// TDD: written before `KsConfig.rebootRequiredFormKeys` exists.
///
/// **This is the test that keeps a device from rebooting on stage.**
///
/// Every field `POST /save` can carry is either live-editable (it has a `KsLiveEdit`
/// case, so `/live` applies it instantly) or reboot-required (it does not, so
/// changing it needs a full `/save`, which writes NVS and RESTARTS the device —
/// dropping it out of the Link session and stopping clock for several seconds).
///
/// Those two sets must PARTITION the form: every key in exactly one, none in both,
/// none in neither. Today the rule lives in a doc comment, and a doc comment does
/// not fail CI. If firmware later makes a field live-safe, or a new field appears in
/// `saveFormFields` and nobody classifies it, this test is what tells you — instead
/// of a user discovering it when the box restarts mid-set.
///
/// The trap is real and it is not guessable from field names: `metro_accent` is live
/// but `metronome` (enable) is NOT. `led` (enable) IS live but `follow_beat` is not.
final class LiveRebootPartitionTests: XCTestCase {

    /// One instance of EVERY `KsLiveEdit` case. Values are arbitrary — only the key
    /// each case emits matters. A new case that isn't listed here will surface as an
    /// unclassified key below, which fails the partition.
    private static let allLiveEdits: [KsLiveEdit] = [
        .clockOutEnabled(true),
        .metronomeAccent(true),
        .metronomeVolume(50),
        .metronomeVoice(1),
        .ledEnabled(true),
        .ledBrightness(50),
        .ledMode(1),
        .ledFade(50),
        .ledBeatColor(0x00FF00),
        .ledAccentColor(0xFF0000),
    ] + (0..<KsConfig.outputCount).flatMap { i -> [KsLiveEdit] in
        [
            .outputEnabled(index: i, true),
            .outputCable(index: i, 0),
            .outputPPQN(index: i, 24),
            .outputPhase(index: i, 0),
            .outputSwing(index: i, 0),
            .outputFollowsLink(index: i, true),
        ]
    }

    private var liveKeys: Set<String> {
        Set(Self.allLiveEdits.map { $0.formField.key })
    }

    /// The full form, with every WiFi slot carrying both an SSID and a password, so
    /// every key `saveFormFields` can ever emit is present.
    private func allSaveKeys() throws -> Set<String> {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(Self.configJSON.utf8))
        let edits = (0..<KsConfig.wifiSlotCount).map {
            WifiCredentialEdit(id: $0, ssid: "net\($0)", password: "pw\($0)")
        }
        return Set(config.saveFormFields(wifiEdits: edits).keys)
    }

    func test_every_save_field_is_live_editable_or_reboot_required_and_never_both() throws {
        let saveKeys = try allSaveKeys()
        let live = liveKeys
        let reboot = KsConfig.rebootRequiredFormKeys

        let both = live.intersection(reboot)
        XCTAssertTrue(both.isEmpty, """
            Field(s) classified as BOTH live-editable and reboot-required: \(both.sorted()).
            A field cannot be both. One of the two classifications is wrong.
            """)

        let unclassified = saveKeys.subtracting(live).subtracting(reboot)
        XCTAssertTrue(unclassified.isEmpty, """
            Field(s) POSTed by /save that are neither live-editable nor declared \
            reboot-required: \(unclassified.sorted()).

            An unclassified field is a control that might silently REBOOT a device \
            mid-set. Either give it a KsLiveEdit case (if the firmware's \
            ks_config_live_safe_copy accepts it) or add it to \
            KsConfig.rebootRequiredFormKeys.
            """)
    }

    /// The reverse direction: a key declared reboot-required that `/save` doesn't
    /// actually send is dead weight, and worse, it means the settings sheet will tag
    /// a control the device will never hear about.
    func test_every_reboot_required_key_is_actually_sent_by_save() throws {
        let saveKeys = try allSaveKeys()
        let orphaned = KsConfig.rebootRequiredFormKeys.subtracting(saveKeys)

        XCTAssertTrue(orphaned.isEmpty,
                      "Declared reboot-required but never sent by /save: \(orphaned.sorted())")
    }

    /// Pin the trap itself, by name, so nobody "tidies" it away.
    func test_the_metronome_trap_is_classified_correctly() {
        XCTAssertTrue(liveKeys.contains("metro_accent"), "metro_accent IS live")
        XCTAssertTrue(KsConfig.rebootRequiredFormKeys.contains("metronome"),
                      "metronome ENABLE reboots — the ES8311 codec only comes up at boot")
        XCTAssertFalse(liveKeys.contains("metronome"),
                       "metronome enable must NOT be reachable from /live")

        XCTAssertTrue(liveKeys.contains("led"), "led enable IS live")
        XCTAssertTrue(KsConfig.rebootRequiredFormKeys.contains("follow_beat"),
                      "follow_beat enable reboots")
        XCTAssertFalse(liveKeys.contains("follow_beat"))
    }

    func test_wifi_credentials_are_never_live() {
        for key in KsConfig.rebootRequiredFormKeys where key.hasPrefix("wifi_") {
            XCTAssertFalse(liveKeys.contains(key), "\(key) must never be live-editable")
        }
    }

    private static let configJSON = """
    {"clock_out":true,"metronome":false,"metro_accent":true,"metro_vol":80,\
    "metro_voice":0,"led":false,"led_bright":60,"led_mode":0,"led_fade":55,\
    "led_beat":"#00B400","led_accent":"#DC6E00","follow_beat":false,\
    "wifi":[{"ssid":"A","pass_set":true},{"ssid":"B","pass_set":false},{"ssid":"C","pass_set":false}],\
    "clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":1,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":2,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":3,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
    """
}
