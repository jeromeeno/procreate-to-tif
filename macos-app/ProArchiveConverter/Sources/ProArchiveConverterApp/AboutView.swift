import SwiftUI

struct AboutView: View {
    private let venmoURL = URL(string: "https://account.venmo.com/u/jerome-eno")
    private let portfolioURL = URL(string: "https://ateli3r.xyz")

    var body: some View {
        VStack(spacing: 18) {
            if let logoImage = BrandAssets.logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
            }

            VStack(spacing: 6) {
                Text("ProArchive Converter")
                    .font(.title2.weight(.semibold))

                Text(versionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Convert `.procreate` archives into layered PSDs, flat renders, animation exports, and timelapse videos on macOS.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Divider()

            VStack(spacing: 10) {
                Text("Made with love by Jerome Eno at Atelier Trois Rivieres, a creative technology studio in Pittsburgh, PA.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if let venmoURL {
                    Link("Support future updates on Venmo", destination: venmoURL)
                }

                if let portfolioURL {
                    Link("View Jerome's portfolio at ATELI3R.", destination: portfolioURL)
                }
            }
            .font(.callout)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 420, idealWidth: 440, minHeight: 420, idealHeight: 440)
    }

    private var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let buildNumber = info["CFBundleVersion"] as? String ?? "1"
        return "Version \(shortVersion) (\(buildNumber))"
    }
}
