import SwiftUI

struct PostCameraView: View {

    @StateObject var viewModel: PostViewModel
    @State private var cameraCoordinator = CameraCoordinator()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch viewModel.state {
            case .camera:
                cameraView
            case .preview:
                previewView
            case .tagging:
                tagView
            case .uploading:
                uploadingView
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
        .onAppear {
            cameraCoordinator.configure()
            cameraCoordinator.start()
        }
        .onDisappear {
            cameraCoordinator.stop()
        }
    }

    // MARK: - Camera

    private var cameraView: some View {
        VStack(spacing: 0) {
            Spacer()

            CameraPreviewView(coordinator: cameraCoordinator)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
                .padding(.horizontal, Theme.spacingM)

            Spacer()

            captureButton
                .padding(.bottom, Theme.spacingXL)
        }
    }

    private var captureButton: some View {
        Button {
            cameraCoordinator.capture { image in
                viewModel.onPhotoCaptured(image)
            }
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
                    cameraCoordinator.start()
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
            // Thumbnail
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                    .padding(.top, Theme.spacingL)
            }

            // Tag list
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

            // Submit
            Button {
                Task { await viewModel.submitPost() }
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

    // MARK: - Uploading

    private var uploadingView: some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            ProgressView(value: viewModel.uploadProgress) {
                Text("Posting...")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .padding(.horizontal, Theme.spacingXXL)

            Spacer()
        }
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

            Text("Next post available \(nextAllowedAt.timeAgo())")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Button("Done") {
                viewModel.resetToCamera()
                cameraCoordinator.start()
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

            Text(message)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)

            HStack(spacing: Theme.spacingXL) {
                Button("Back") {
                    viewModel.retakePhoto()
                    cameraCoordinator.start()
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textSecondary)

                Button("Retry") {
                    Task { await viewModel.submitPost() }
                }
                .font(Theme.headlineFont)
                .foregroundColor(Theme.accent)
            }

            Spacer()
        }
    }
}
