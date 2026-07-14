import SwiftUI
import UniformTypeIdentifiers

/// Push a firmware `.bin` over the air.
///
/// **The real footgun here is cross-flashing a binary built for a different chip.**
/// The fleet is multi-target, and nothing in the client validates the binary against
/// the device — the firmware doesn't expose its chip target, so the app cannot check.
/// A filename convention is not a safety mechanism, but an unlabelled "Flash" button
/// is worse. So the confirmation names the device and requires an explicit
/// acknowledgement of the target. The proper fix is firmware-side (expose the target
/// in /status or /update) and belongs with T-011.
///
/// The reassurance is real and worth stating plainly: dual-slot OTA (P4-017) means a
/// failed flash does NOT brick the device — it stays on its current firmware.
struct FirmwareUpdateSheet: View {
    let deviceName: String
    let onFlash: (Data) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var binary: Data?
    @State private var filename = ""
    @State private var acknowledgedTarget = false
    @State private var confirming = false
    @State private var flashing = false
    @State private var failure: String?

    private var canFlash: Bool {
        binary != nil && acknowledgedTarget && !flashing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    consequenceBand

                    picker

                    if binary != nil {
                        targetAcknowledgement
                    }

                    if let failure {
                        failureBanner(failure)
                    }

                    if flashing {
                        ProgressView()
                            .tint(KS.led)
                            .frame(maxWidth: .infinity)
                    } else {
                        flashButton
                    }
                }
                .padding()
            }
            .background(KS.bg.ignoresSafeArea())
            .navigationTitle("Firmware")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(flashing)
                }
            }
            .interactiveDismissDisabled(flashing)
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                load(result)
            }
            .alert("Flash \(deviceName)?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Flash", role: .destructive) { flash() }
            } message: {
                Text("\(filename) will be written to \(deviceName) and the device will reboot into it. Make sure this binary was built for THIS device's chip — nothing here can check that for you.")
            }
        }
        .presentationDetents([.large])
    }

    private var consequenceBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS REBOOTS THE DEVICE")
                .font(.ksDisplay(12.5, .semibold))
                .tracking(1.4)
                .foregroundStyle(KS.amberText)

            Text("The binary is written to the inactive slot and the device restarts into it. A failed flash does NOT brick the device — dual-slot OTA means it stays on its current firmware.")
                .font(.ksMono(12))
                .foregroundStyle(KS.mut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KS.consequence, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(KS.amber.opacity(0.35))
        )
    }

    private var picker: some View {
        Button {
            picking = true
        } label: {
            KSField(prefix: "BIN") {
                Text(filename.isEmpty ? "choose a .bin" : filename)
                    .font(.ksMono(13))
                    .foregroundStyle(filename.isEmpty ? KS.mut : KS.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if let binary {
                    Text("\(binary.count / 1024) KB")
                        .font(.ksMono(11))
                        .foregroundStyle(KS.mut)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(flashing)
    }

    /// The app cannot verify the chip target, so the user must. Not a rubber stamp —
    /// it's the only gate that exists.
    private var targetAcknowledgement: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $acknowledgedTarget)
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()

            Text("I built this binary for \(deviceName)'s chip target. Cross-flashing a binary meant for a different chip will not work.")
                .font(.ksMono(11.5))
                .foregroundStyle(KS.mut)
        }
        .accessibilityElement(children: .combine)
    }

    private func failureBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FLASH FAILED")
                .font(.ksDisplay(12))
                .tracking(1.4)
                .foregroundStyle(KS.ember)
            Text(message)
                .font(.ksMono(11.5))
                .foregroundStyle(KS.mut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KS.emberFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var flashButton: some View {
        WriteAndRebootButton { confirming = true }
            .disabled(!canFlash)
            .opacity(canFlash ? 1 : 0.4)
    }

    private func load(_ result: Result<[URL], Error>) {
        failure = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.pathExtension.lowercased() == "bin" else {
            failure = "That isn't a .bin. Pick the firmware image."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            failure = "Couldn't read that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            binary = try Data(contentsOf: url)
            filename = url.lastPathComponent
            acknowledgedTarget = false   // a new binary is a new decision
        } catch {
            failure = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func flash() {
        guard let binary else { return }
        flashing = true
        failure = nil
        Task {
            let ok = await onFlash(binary)
            flashing = false
            if ok {
                dismiss()
            } else {
                // Dual-slot: the device is still running its old firmware. Say so —
                // a user staring at a failed flash needs to know the box still works.
                failure = "The device rejected the image. It is still running its current firmware and is safe to use."
            }
        }
    }
}
