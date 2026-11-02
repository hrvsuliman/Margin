import SwiftUI
import UIKit

/// Phase 0 screen. Its only job is to prove the pipeline:
/// built on GitHub, signed by Sideloadly, running natively on the iPhone.
struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var hapticTrigger = 0
    @State private var hapticsTested = false

    private let info = BuildInfo.current
    private let marginX: CGFloat = 40

    var body: some View {
        ZStack {
            RuledPaper(marginX: marginX)

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    header
                        .entrance(appeared, delay: 0)
                    checklist
                        .entrance(appeared, delay: 0.08)
                    hapticsButton
                        .entrance(appeared, delay: 0.16)
                    footer
                        .entrance(appeared, delay: 0.24)
                }
                .padding(.leading, marginX + 20)
                .padding(.trailing, 24)
                .padding(.top, 56)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHASE 0")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Palette.marginRed)
            Text("Margin")
                .font(.system(size: 52, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.ink)
            Text("School, notes and exam prep, in one place.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 18) {
            CheckRow(
                title: "Native SwiftUI app",
                detail: "Running on iOS \(UIDevice.current.systemVersion)"
            )
            CheckRow(
                title: "Built on GitHub Actions",
                detail: "Version \(info.displayVersion)"
            )
            CheckRow(
                title: "Signed and installed",
                detail: info.bundleID
            )
            CheckRow(
                title: "Light and dark mode",
                detail: colorScheme == .dark ? "Currently dark" : "Currently light"
            )
            CheckRow(
                title: "Haptic feedback",
                detail: hapticsTested ? "Felt a tap? Then it works." : "Not tested yet",
                done: hapticsTested
            )
        }
    }

    private var hapticsButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                hapticsTested = true
            }
            hapticTrigger += 1
        } label: {
            Text(hapticsTested ? "Tap again" : "Test haptics")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(Palette.ink))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private var footer: some View {
        Text("Next up: Phase 1, with the dashboard, subjects, tasks and calendar.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
    }
}

private struct CheckRow: View {
    let title: String
    let detail: String
    var done = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Palette.marginRed : Palette.secondaryInk)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shrinks slightly while pressed, springs back on release.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private extension View {
    /// Fades and lifts the view in once `visible` becomes true.
    func entrance(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(delay), value: visible)
    }
}

#Preview {
    WelcomeView()
}
