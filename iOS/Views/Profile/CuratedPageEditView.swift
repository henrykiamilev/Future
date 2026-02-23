import SwiftUI
import PhotosUI

struct CuratedPageEditView: View {

    @ObservedObject var viewModel: CuratedPageViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotos: [Int: PhotosPickerItem] = [:]
    @State private var showQuestionPicker: Int?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacingXL) {
                    imagesSection
                    questionsSection
                }
                .padding(.horizontal, Theme.spacingL)
                .padding(.top, Theme.spacingL)
                .padding(.bottom, Theme.spacingXXL)
            }
            .background(Theme.background)
            .navigationTitle("Edit Curated Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView().tint(Theme.textTertiary)
                    } else {
                        Button("Save") {
                            Task {
                                await viewModel.save()
                                if viewModel.error == nil {
                                    dismiss()
                                }
                            }
                        }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(item: Binding(
                get: { showQuestionPicker.map { QuestionPickerID(index: $0) } },
                set: { showQuestionPicker = $0?.index }
            )) { item in
                questionPickerSheet(for: item.index)
            }
        }
    }

    // MARK: - Images Section

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            sectionHeader("Personality Photos")

            Text("4 images that describe who you are")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.spacingS),
                GridItem(.flexible(), spacing: Theme.spacingS)
            ], spacing: Theme.spacingS) {
                ForEach(0..<4, id: \.self) { index in
                    imageSlot(index: index)
                }
            }
        }
    }

    private func imageSlot(index: Int) -> some View {
        PhotosPicker(selection: Binding(
            get: { selectedPhotos[index] },
            set: { newItem in
                selectedPhotos[index] = newItem
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.uploadImage(at: index, image: image)
                    }
                }
            }
        ), matching: .images) {
            ZStack {
                if let url = viewModel.images[index] {
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: url),
                        targetSize: CGSize(width: 300, height: 300)
                    ) {
                        Rectangle().fill(Theme.separator)
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
                } else {
                    RoundedRectangle(cornerRadius: Theme.radiusM)
                        .fill(Theme.separator.opacity(0.4))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(Theme.textTertiary)
                                Text("Add")
                                    .font(Theme.captionFont)
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Questions Section

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            sectionHeader("About You")

            Text("Pick 4 questions and write your answers")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)

            ForEach(0..<4, id: \.self) { index in
                qaSlotCard(index: index)
            }
        }
    }

    private func qaSlotCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            // Question selector
            Button {
                showQuestionPicker = index
            } label: {
                HStack {
                    Text(viewModel.qaSlots[index].prompt.isEmpty
                         ? "Tap to pick a question"
                         : viewModel.qaSlots[index].prompt)
                        .font(Theme.headlineFont)
                        .foregroundColor(viewModel.qaSlots[index].prompt.isEmpty
                                         ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            // Answer field
            if !viewModel.qaSlots[index].prompt.isEmpty {
                TextField("Your answer...", text: Binding(
                    get: { viewModel.qaSlots[index].answer },
                    set: { viewModel.qaSlots[index].answer = $0 }
                ), axis: .vertical)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2...4)
                    .padding(Theme.spacingS)
                    .background(Theme.background)
                    .cornerRadius(Theme.radiusS)
            }
        }
        .padding(Theme.spacingM)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusL)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
        }
    }

    // MARK: - Question Picker Sheet

    private func questionPickerSheet(for index: Int) -> some View {
        NavigationStack {
            List(viewModel.availableQuestions(excludingIndex: index), id: \.self) { question in
                Button {
                    viewModel.qaSlots[index].prompt = question
                    showQuestionPicker = nil
                } label: {
                    Text(question)
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textPrimary)
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.plain)
            .background(Theme.background)
            .navigationTitle("Pick a Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showQuestionPicker = nil }
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.sectionHeaderFont)
            .foregroundColor(Theme.textTertiary)
            .tracking(1.2)
    }
}

// MARK: - Helper for identifiable sheet binding

private struct QuestionPickerID: Identifiable {
    let index: Int
    var id: Int { index }
}
