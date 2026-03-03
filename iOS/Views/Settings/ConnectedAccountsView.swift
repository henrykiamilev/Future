import SwiftUI

struct ConnectedAccountsView: View {

    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: Theme.spacingS) {
                    Text("CONNECTED ACCOUNTS")
                        .font(Theme.sectionHeaderFont)
                        .tracking(1.5)
                        .foregroundColor(Theme.textSecondary)

                    Text("Link your socials so friends can find you")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.top, Theme.spacingL)
                .padding(.bottom, Theme.spacingXL)

                // Account fields
                VStack(spacing: 0) {
                    accountField(
                        platform: "Instagram",
                        icon: "camera.fill",
                        placeholder: "username",
                        text: $viewModel.instagramHandle,
                        tintColor: Color(red: 0.83, green: 0.18, blue: 0.42)
                    )

                    thinDivider

                    accountField(
                        platform: "Snapchat",
                        icon: "message.fill",
                        placeholder: "username",
                        text: $viewModel.snapchatHandle,
                        tintColor: Color(red: 1.0, green: 0.92, blue: 0.23)
                    )

                    thinDivider

                    accountField(
                        platform: "TikTok",
                        icon: "play.rectangle.fill",
                        placeholder: "username",
                        text: $viewModel.tiktokHandle,
                        tintColor: Theme.textPrimary
                    )

                    thinDivider

                    accountField(
                        platform: "X",
                        icon: "at",
                        placeholder: "handle",
                        text: $viewModel.xHandle,
                        tintColor: Theme.textPrimary
                    )

                    thinDivider

                    accountField(
                        platform: "Website",
                        icon: "globe",
                        placeholder: "yoursite.com",
                        text: $viewModel.websiteURL,
                        tintColor: Color(red: 0.20, green: 0.50, blue: 0.85),
                        isURL: true
                    )
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Accounts")
                    .font(.custom("OpenSauceSans-SemiBold", size: 16))
                    .foregroundColor(Theme.textPrimary)
            }
        }
    }

    private func accountField(
        platform: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        tintColor: Color,
        isURL: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            // Platform icon circle
            Circle()
                .fill(tintColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(tintColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(platform)
                    .font(.custom("OpenSauceSans-Medium", size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .tracking(0.5)

                TextField(placeholder, text: text)
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                    .textInputAutocapitalization(isURL ? .never : .never)
                    .autocorrectionDisabled()
                    .keyboardType(isURL ? .URL : .twitter)
            }

            Spacer()

            if !text.wrappedValue.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.30, green: 0.70, blue: 0.40))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, 70)
    }
}
