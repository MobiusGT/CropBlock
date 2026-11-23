import SwiftUI
import CropBlockKit

/// Subtle info popover explaining which players honor Matroska `PixelCrop*` headers.
struct CompatibilityPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label("Player Compatibility", systemImage: "play.rectangle")
                .font(.headline)

            Text("Crop Block edits only the four Matroska PixelCrop* tags losslessly in-place—zero re-encoding, instant, and reversible. Display dimension headers remain untouched.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Surface.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supported Players")
                            .font(.callout.weight(.semibold))
                        Text("mpv, IINA (mpv-based), MPC-BE, and Kodi honor PixelCrop* headers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Surface.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limited or Ignored")
                            .font(.callout.weight(.semibold))
                        Text("VLC, browsers, and many smart TV or web streaming clients ignore Matroska PixelCrop* headers and display the uncropped frame.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            HStack {
                Text("Project & documentation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: AppMetadata.repositoryURL)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(Space.lg)
        .frame(width: 340)
    }
}
