import AppKit
import SwiftUI

/// A ruler and a bank card drawn at what the app takes for real size, adjusted until they
/// match a physical ruler or card held against the screen.
struct CalibrationView: View {
    let screen: NSScreen
    @Environment(\.dismiss) private var dismiss
    @State private var factor: CGFloat
    @State private var measured: Double?

    /// Length of the ruler bar.
    private static let rulerMM = 150.0
    /// ISO/IEC 7810 ID-1, the size of bank and ID cards.
    private static let cardMM = CGSize(width: 85.60, height: 53.98)
    private static let cardCornerMM = 3.18

    init(screen: NSScreen) {
        self.screen = screen
        _factor = State(initialValue: ScreenCalibration.factor(screen))
    }

    private var ppmm: CGFloat { ScreenCalibration.reportedPointsPerMM(screen) * factor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calibrate Real Size").font(.title2.bold())
            Text("Hold a ruler against the screen with its 0 on the bar's 0. Nudge until the bar ends exactly at \(Int(Self.rulerMM)) mm, or type the length you read.")
                .fixedSize(horizontal: false, vertical: true)

            ruler
                .frame(width: (Self.rulerMM + 8) * ppmm, height: 14 * ppmm)
                .background(.white)

            HStack(spacing: 8) {
                Button { nudge(-0.1) } label: { Image(systemName: "minus") }
                    .buttonRepeatBehavior(.enabled)
                    .help("Shorter by 0.1 mm")
                Button { nudge(0.1) } label: { Image(systemName: "plus") }
                    .buttonRepeatBehavior(.enabled)
                    .help("Longer by 0.1 mm")
                Divider().frame(height: 16)
                Text("The bar measures")
                TextField("", value: $measured, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                    .onSubmit(applyMeasured)
                Text("mm")
                Button("Apply", action: applyMeasured).disabled((measured ?? 0) <= 0)
            }

            Text("Or check with a bank card on the outline:").foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: Self.cardCornerMM * ppmm)
                .stroke(.black, lineWidth: 1)
                .frame(width: Self.cardMM.width * ppmm, height: Self.cardMM.height * ppmm)
                .background(.white)

            Text(info).font(.caption).foregroundStyle(.secondary).monospacedDigit()

            HStack {
                Button("Reset to Display Size") { set(1) }.disabled(factor == 1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .fixedSize()
    }

    /// Millimetre ticks, longer every 5 and 10 mm, with centimetre numbers.
    private var ruler: some View {
        Canvas { context, size in
            let x0 = 4 * ppmm
            var ticks = Path()
            for mm in 0...Int(Self.rulerMM) {
                let x = x0 + CGFloat(mm) * ppmm
                let length = (mm % 10 == 0 ? 5 : mm % 5 == 0 ? 3.5 : 2) * ppmm
                ticks.move(to: CGPoint(x: x, y: 0))
                ticks.addLine(to: CGPoint(x: x, y: length))
                if mm % 10 == 0 {
                    context.draw(Text("\(mm / 10)").font(.system(size: 2.6 * ppmm)).foregroundStyle(.black),
                                 at: CGPoint(x: x, y: 5.5 * ppmm), anchor: .top)
                }
            }
            context.stroke(ticks, with: .color(.black), lineWidth: 1)
            context.fill(Path(CGRect(x: x0, y: size.height - 2 * ppmm, width: Self.rulerMM * ppmm, height: 2 * ppmm)),
                         with: .color(.black))
        }
    }

    private var info: String {
        let name = screen.localizedName
        guard let mm = ScreenCalibration.reportedSizeMM(screen) else {
            return "\(name) doesn't report its size — calibration is needed for real size."
        }
        let size = "\(Int(mm.width.rounded())) × \(Int(mm.height.rounded())) mm"
        let correction = factor == 1 ? "not calibrated" : "correction × \(Double(factor).formatted(.number.precision(.fractionLength(4))))"
        return "\(name) reports \(size) · \(correction)"
    }

    private func nudge(_ mm: Double) { set(factor * (Self.rulerMM + mm) / Self.rulerMM) }

    /// The bar is drawn `rulerMM` long, so a measured length gives the correction directly.
    private func applyMeasured() {
        guard let m = measured, m > 0 else { return }
        set(factor * m / Self.rulerMM)
        measured = nil
    }

    private func set(_ f: CGFloat) {
        factor = f
        ScreenCalibration.setFactor(f, for: screen)
    }
}
