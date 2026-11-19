import SwiftUI

/// An optional, silent introduction. It never starts a speech session.
struct WelcomeView: View {
    let continueToLibrary: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 42

    init(continueToLibrary: @escaping () -> Void = {}) {
        self.continueToLibrary = continueToLibrary
    }

    private var colors: WelcomeColors { WelcomeColors(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 28)
                    VStack(spacing: 28) {
                        artwork
                        introduction
                        Text("welcome.features")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(colors.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26).padding(.vertical, 12)
                .frame(minHeight: viewport.size.height)
            }
        }
        .background(colors.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) { continueAction }
        .tint(Color.accentColor)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Oralo")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(-0.8).foregroundStyle(colors.ink)
            Text("welcome.subtitle")
                .font(.caption).foregroundStyle(colors.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artwork: some View {
        Image("BrandMark")
            .resizable().scaledToFit().frame(width: 112, height: 112)
            .clipShape(.rect(cornerRadius: 27))
            .padding(5).background(colors.surface, in: .rect(cornerRadius: 32))
            .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
            .rotationEffect(.degrees(-7))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: 24)).foregroundStyle(colors.accent.opacity(0.6))
                    .offset(x: 25, y: -9)
            }
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("welcome.headline.first")
                Text("welcome.headline.second")
                    .background {
                        WelcomeMarker().fill(colors.marker)
                            .padding(.horizontal, -7).padding(.vertical, 1)
                            .rotationEffect(.degrees(-2))
                    }
            }
            .font(.system(size: headlineSize, weight: .bold, design: .rounded))
            .tracking(-1.3)
            .foregroundStyle(colors.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("welcome-headline")
            Text("welcome.message")
                .font(.subheadline).lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var continueAction: some View {
        VStack(spacing: 12) {
            Group {
                if #available(iOS 26, *), !reducedTransparency {
                    continueButton.buttonStyle(.glassProminent)
                } else {
                    continueButton.buttonStyle(.borderedProminent)
                }
            }.buttonBorderShape(.capsule)
            Text("welcome.encouragement")
                .font(.footnote).foregroundStyle(colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 26).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(colors.paper)
    }

    private var continueButton: some View {
        Button(action: continueToLibrary) {
            HStack(spacing: 12) {
                Text("welcome.continue")
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 2)
        }.accessibilityIdentifier("welcome-continue")
    }
}

#Preview { WelcomeView() }
