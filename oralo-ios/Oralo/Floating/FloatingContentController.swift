import AVKit

/// AVKit live-content host with its own display surface. The manuscript is
/// rendered locally; no CallKit call, network stream or camera session is used.
@MainActor final class FloatingContentController: AVPictureInPictureVideoCallViewController {
    let surface = FloatingSurfaceView()
    init() {
        super.init(nibName: nil, bundle: nil)
        // Set the aspect ratio before AVKit reads it when creating the window.
        preferredContentSize = FloatingFrameRenderer.size
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override func loadView() { view = surface }
}
