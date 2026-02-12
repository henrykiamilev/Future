import SwiftUI
import AVKit

struct SplashScreenView: View {

    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if let player {
                VideoPlayerView(player: player)
                    .ignoresSafeArea()
            }
        }
        .opacity(fadeOut ? 0 : 1)
        .onAppear {
            setupPlayer()
        }
    }

    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: "splash_animation", withExtension: "mp4") else {
            // Video not found — skip splash
            onFinished()
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = true
        self.player = avPlayer

        // Listen for playback to finish
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.4)) {
                fadeOut = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onFinished()
            }
        }

        avPlayer.play()
    }
}

// MARK: - AVPlayer UIKit wrapper (no controls, fills screen)

private struct VideoPlayerView: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView(player: player)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private class PlayerUIView: UIView {

    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
