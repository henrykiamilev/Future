import SwiftUI

struct PostCameraView: View {

    @ObservedObject var viewModel: PostViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch viewModel.state {
            case .needsPermission:
                permissionView
            case .camera:
                cameraView
            case .preview:
                previewView
            case .tagging:
                tagView
            case .uploading(let progress):
                uploadingView(progress: progress)
            case .success(let nextAllowedAt):
                successView(nextAllowedAt: nextAllowedAt)
            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("POST")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .task {
            await viewModel.checkCameraAuthorization()
        }
        .onDisappear {
            viewModel.camera.stop()
        }
    }

    // MARK: - Permission Denied

    private var permissionView: some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(Theme.textTertiary)

            Text("Camera Access Required")
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("Open Settings to allow camera access.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Theme.headlineFont)
            .foregroundColor(Theme.accent)

            Spacer()
        }
        .padding(.horizontal, Theme.spacingXL)
    }

    // MARK: - Camera

    private var cameraView: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack(alignment: .topTrailing) {
                CameraPreviewView(coordinator: viewModel.camera)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))

                // Camera controls overlay
                VStack(spacing: Theme.spacingM) {
                    // Flip camera
                    Button {
                        viewModel.camera.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    // Flash toggle
                    Button {
                        viewModel.camera.flashMode = viewModel.camera.flashMode == .off ? .on : .off
                    } label: {
                        Image(systemName: viewModel.camera.flashMode == .off ? "bolt.slash" : "bolt.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(Theme.spacingM)
            }
            .padding(.horizontal, Theme.spacingM)

            Spacer()

            // Shutter button
            Button {
                viewModel.capturePhoto()
            } label: {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle()
                            .fill(Theme.accent)
                            .padding(6)
                    }
            }
            .disabled(!viewModel.camera.isSessionRunning)
            .opacity(viewModel.camera.isSessionRunning ? 1.0 : 0.4)
            .padding(.bottom, Theme.spacingXL)
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
                    .padding(.horizontal, Theme.spacingM)
            }

            Spacer()

            HStack(spacing: Theme.spacingXL) {
                Button("Retake") {
                    viewModel.retakePhoto()
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textSecondary)

                Button("Next") {
                    viewModel.proceedToTagging()
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.accent)
            }
            .padding(.bottom, Theme.spacingXL)
        }
    }

    // MARK: - Tag Editor

    private var tagView: some View {
        VStack(spacing: Theme.spacingL) {
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                    .padding(.top, Theme.spacingL)
            }

            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text("TAGS")
                    .font(Theme.sectionHeaderFont)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1.5)

                ForEach(Array(viewModel.tags.enumerated()), id: \.offset) { index, tag in
                    HStack {
                        Text(tag.label)
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.textPrimary)

                        if let url = tag.externalURL {
                            Text(url)
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            viewModel.removeTag(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    .padding(.vertical, Theme.spacingXS)
                }

                if viewModel.tags.count < 3 {
                    tagInputFields
                }
            }
            .padding(.horizontal, Theme.spacingL)

            Spacer()

            Button {
                viewModel.submitPost()
            } label: {
                Text("Post")
                    .font(Theme.headlineFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .cornerRadius(Theme.radiusM)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.bottom, Theme.spacingXL)
        }
    }

    private var tagInputFields: some View {
        VStack(spacing: Theme.spacingS) {
            TextField("Item name", text: $viewModel.tagLabel)
                .font(Theme.bodyFont)
                .textFieldStyle(.plain)
                .padding(Theme.spacingS)
                .background(Theme.background)
                .cornerRadius(Theme.radiusS)

            TextField("Link (optional)", text: $viewModel.tagURL)
                .font(Theme.captionFont)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .padding(Theme.spacingS)
                .background(Theme.background)
                .cornerRadius(Theme.radiusS)

            Button("Add Tag") {
                viewModel.addTag()
            }
            .font(Theme.labelFont)
            .foregroundColor(Theme.accent)
            .disabled(!viewModel.canAddTag)
            .opacity(viewModel.canAddTag ? 1.0 : 0.4)
        }
    }

    // MARK: - Uploading (with real progress)

    private func uploadingView(progress: Double) -> some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            VStack(spacing: Theme.spacingM) {
                ProgressView(value: progress) {
                    Text(uploadPhaseLabel(progress))
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                }
                .tint(Theme.accent)
                .padding(.horizontal, Theme.spacingXXL)

                Button("Cancel") {
                    viewModel.cancelUpload()
                }
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
            }

            Spacer()
        }
    }

    private func uploadPhaseLabel(_ progress: Double) -> String {
        if progress < 0.20 { return "Compressing..." }
        if progress < 0.30 { return "Preparing..." }
        if progress < 0.80 { return "Uploading..." }
        if progress < 1.0  { return "Finalizing..." }
        return "Done"
    }

    // MARK: - Success

    private func successView(nextAllowedAt: Date) -> some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(Theme.accent)

            Text("Posted")
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("Next post available \(nextAllowedAt, style: .relative)")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Button("Done") {
                viewModel.resetToCamera()
            }
            .font(Theme.headlineFont)
            .foregroundColor(Theme.accent)
            .padding(.bottom, Theme.spacingXL)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(Theme.textTertiary)

            Text(message)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)

            HStack(spacing: Theme.spacingXL) {
                Button("Back") {
                    viewModel.retakePhoto()
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textSecondary)

                Button("Retry") {
                    viewModel.submitPost()
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.accent)
            }

            Spacer()
        }
    }
}
