import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct DarkroomView: View {

    let originalImage: UIImage
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    // MARK: - Adjustment State

    @State private var brightness: Double = 0      // -0.3 … 0.3
    @State private var contrast: Double = 1         // 0.5 … 1.5
    @State private var saturation: Double = 1       // 0 … 2
    @State private var warmth: Double = 6500        // 3000 … 10000 (Kelvin)
    @State private var shadows: Double = 0          // -1 … 1
    @State private var highlights: Double = 1       // 0 … 1 (CIHighlightShadowAdjust)

    @State private var previewImage: UIImage?

    // MARK: - Core Image

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    private var ciInput: CIImage? {
        guard let cgImage = originalImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Image preview
            imagePreview
                .padding(.top, Theme.spacingM)

            // Sliders
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacingM) {
                    adjustmentSlider(label: "Brightness", value: $brightness, range: -0.3...0.3)
                    adjustmentSlider(label: "Contrast", value: $contrast, range: 0.5...1.5)
                    adjustmentSlider(label: "Saturation", value: $saturation, range: 0...2)
                    adjustmentSlider(label: "Warmth", value: $warmth, range: 3000...10000)
                    adjustmentSlider(label: "Shadows", value: $shadows, range: -1...1)
                    adjustmentSlider(label: "Highlights", value: $highlights, range: 0...1)
                }
                .padding(.horizontal, Theme.spacingL)
                .padding(.vertical, Theme.spacingM)
            }

            // Bottom bar
            HStack {
                Button("Cancel") { onCancel() }
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                Button("Reset") { resetAdjustments() }
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)

                Spacer()

                Button("Done") { applyAndFinish() }
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)
        }
        .background(Theme.background)
        .onChange(of: brightness) { _ in updatePreview() }
        .onChange(of: contrast) { _ in updatePreview() }
        .onChange(of: saturation) { _ in updatePreview() }
        .onChange(of: warmth) { _ in updatePreview() }
        .onChange(of: shadows) { _ in updatePreview() }
        .onChange(of: highlights) { _ in updatePreview() }
        .onAppear { previewImage = originalImage }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        Group {
            if let preview = previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            } else {
                Rectangle()
                    .fill(Theme.separator)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
        .padding(.horizontal, Theme.spacingM)
    }

    // MARK: - Slider Component

    private func adjustmentSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(sliderValueText(label: label, value: value.wrappedValue))
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(Theme.accent)
        }
    }

    private func sliderValueText(label: String, value: Double) -> String {
        switch label {
        case "Warmth":
            return "\(Int(value))K"
        case "Brightness":
            return String(format: "%+.2f", value)
        default:
            return String(format: "%.2f", value)
        }
    }

    // MARK: - Core Image Processing

    private func updatePreview() {
        guard let input = ciInput else { return }
        let output = applyFilters(to: input)
        previewImage = renderToUIImage(output)
    }

    private func applyFilters(to input: CIImage) -> CIImage {
        // 1. Color controls: brightness, contrast, saturation
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = input
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = Float(saturation)

        var current = colorControls.outputImage ?? input

        // 2. Temperature (warmth)
        let tempFilter = CIFilter.temperatureAndTint()
        tempFilter.inputImage = current
        tempFilter.neutral = CIVector(x: CGFloat(warmth), y: 0)
        tempFilter.targetNeutral = CIVector(x: 6500, y: 0)
        current = tempFilter.outputImage ?? current

        // 3. Highlights & shadows
        let shadowHighlight = CIFilter.highlightShadowAdjust()
        shadowHighlight.inputImage = current
        shadowHighlight.shadowAmount = Float(shadows)
        shadowHighlight.highlightAmount = Float(highlights)
        current = shadowHighlight.outputImage ?? current

        return current
    }

    private func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = Self.context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
    }

    // MARK: - Actions

    private func resetAdjustments() {
        brightness = 0
        contrast = 1
        saturation = 1
        warmth = 6500
        shadows = 0
        highlights = 1
        previewImage = originalImage
    }

    private func applyAndFinish() {
        // Check if any adjustments were made
        let isDefault = brightness == 0 && contrast == 1 && saturation == 1
            && warmth == 6500 && shadows == 0 && highlights == 1
        if isDefault {
            onDone(originalImage)
            return
        }

        // Render full-resolution edited image
        guard let input = ciInput else {
            onDone(originalImage)
            return
        }
        let output = applyFilters(to: input)
        let final = renderToUIImage(output) ?? originalImage
        onDone(final)
    }
}
