import SwiftUI
import _AVKit_SwiftUI
import AVFoundation

struct VideoView: View {
    @StateObject var player: DefaultVideoPlayer
    
    var body: some View {
        VideoPlayer(player: player.player)
    }
}

struct VideoTimelineView: View {
    @StateObject var player: DefaultVideoPlayer
    @State private var thumbLoaded = false
    @State private var isDragging = false
    @State private var loadedImages: [UIImage] = [] // Change to UIImage array
    @State private var currentTime: CMTime = .zero // Track current time

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(loadedImages, id: \.self) { image in // Use loadedImages
                        Image(uiImage: image) // Convert UIImage to Image view
                            .resizable()
                            .frame(width: 96, height: 96 * 3/4)
                            .background(Color.black)
                            .cornerRadius(image == loadedImages.first ? 12 : (image == loadedImages.last ? 12 : 0))
                    }
                }
            }

            Text("00:00")
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
        .background(Color("#101010ff"))
        .onAppear {
            loadThumbImages {
                thumbLoaded = true
            }
            
            // Subscribe to the currentTimeObservable to update currentTime
            player.currentTimeObservable.sink { time in
                self.currentTime = time
            }
        }
    }

    private func loadThumbImages(onCompletion: @escaping (() -> Void)) {
        guard let videoURL = player.url else {
            return
        }

        let thumbIntervalSeconds = 5

        var thumbGenerator = ThumbnailGenerator(url: videoURL)
        thumbGenerator.requestThumbnails(intervalSeconds: thumbIntervalSeconds) { image, index, totalCount in
            DispatchQueue.main.async {
                guard let image = image else { return }
                loadedImages.append(UIImage(cgImage: image)) // Append UIImage

                if index == totalCount - 1 {
                    self.thumbLoaded = true
                    self.observePlayer()
                    onCompletion()
                }
            }
        }
    }

    
    private func observePlayer() {
//        guard let videoDuration = player.duration?.seconds, videoDuration > 0 else {
//            return
//        }
//
//
//        let scrollWidth = thumbScrollView.contentSize.width
//        let moveStep = scrollWidth / videoDuration
//
//        player?.currentTimeObservable
//            .sink { [weak self] playingTime in
//                guard let self = self else {
//                    return
//                }
//
//                self.timeView.text = "\(Int(playingTime.seconds).toHHMMSS)"
//
//                if self.player?.status == .playing {
//                    let scrollOffset = -self.scrollPadding + playingTime.seconds * moveStep
//                    self.thumbScrollView.setContentOffset(CGPoint(x: scrollOffset, y: 0), animated: true)
//                }
//        }.store(in: &cancellables)
//
//        player?.statusObservable
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] status in
//                guard let self = self else {
//                    return
//                }
//
//                if status == .playing {
//                    self.isDragging = false // auto scrolling
//                }
//
//                if status == .finished {
//                    // Scroll to zero time
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                        self.player?.seek(to: .zero, completion: nil)
//                        self.thumbScrollView.setContentOffset(CGPoint(x: -self.scrollPadding, y: 0), animated: true)
//                    }
//                }
//        }.store(in: &cancellables)
    }


}

// ******************************************************
// MARK: DefaultVideoPlayer
// ******************************************************


public enum VideoPlayerStatus {
    case initial
    case loading
    case failed
    case readyToPlay
    case playing
    case paused
    case finished
}

protocol VideoPlayerIntf {
    var url: URL? { get set }
    
    var status: VideoPlayerStatus { get }
    
    var statusObservable: AnyPublisher<VideoPlayerStatus, Never> { get }
    
    var duration: CMTime? { get }
    
    var currentTimeObservable: AnyPublisher<CMTime, Never> { get }
    
    var videoSize: CGSize? { get }
    
    func play()
    
    func pause()
    
    func seek(to time: CMTime, completion: ((Bool) -> Void)?)
}

import AVFoundation
import Combine
import Foundation

class DefaultVideoPlayer: NSObject, ObservableObject {
    private(set) var player = AVPlayer()
    @Published var isPlaying = false

    private let observedKeyPaths = [
        #keyPath(AVPlayer.timeControlStatus),
        #keyPath(AVPlayer.currentItem.status),
    ]

    private var timeObserver: Any?

    private static var observerContext = 0

    private var _status = CurrentValueSubject<VideoPlayerStatus, Never>(.initial)

    private(set) lazy var statusObservable: AnyPublisher<VideoPlayerStatus, Never> = {
        _status.eraseToAnyPublisher()
    }()

    var status: VideoPlayerStatus {
        _status.value
    }

    private var _currentTime = CurrentValueSubject<CMTime, Never>(.zero)

    private(set) lazy var currentTimeObservable: AnyPublisher<CMTime, Never> = {
        _currentTime.eraseToAnyPublisher()
    }()

    var url: URL? {
        get {
            (player.currentItem?.asset as? AVURLAsset)?.url
        }

        set {
            if let url = newValue {
                replaceCurrentItem(AVPlayerItem(url: url))
            } else {
                replaceCurrentItem(nil)
            }
        }
    }

    var duration: CMTime? {
        player.currentItem?.duration
    }

    var videoSize: CGSize? {
        guard let videoTrack = player.currentItem?.asset.tracks(withMediaType: .video).first else {
            return nil
        }
        return videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    }

    init(playerItem: AVPlayerItem? = nil) {
        super.init()

        addPlayerObserve()
        if let playerItem = playerItem {
            replaceCurrentItem(playerItem)
        }
    }

    convenience init(asset: AVAsset) {
        self.init(playerItem: AVPlayerItem(asset: asset))
    }

    convenience init(url: URL) {
        let asset = AVAsset(url: url)
        self.init(asset: asset)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removePlayerObserve()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: CMTime, completion: ((Bool) -> Void)?) {
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] success in
            guard let self = self else {
                return
            }
            if success {
                self._currentTime.value = self.player.currentTime()
            }
            completion?(success)
        }
    }

    private func replaceCurrentItem(_ playerItem: AVPlayerItem?) {
        NotificationCenter.default.removeObserver(self,
                                                  name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                  object: player.currentItem)
        player.replaceCurrentItem(with: playerItem)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerDidFinishPlaying),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: playerItem)
    }

    private func addPlayerObserve() {
        for keyPath in observedKeyPaths {
            player.addObserver(self, forKeyPath: keyPath, options: [.new, .initial], context: &DefaultVideoPlayer.observerContext)
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20),
                                                      queue: .main) { [weak self] time in
            guard let self = self else {
                return
            }
            self._currentTime.value = time
        }
    }

    private func removePlayerObserve() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        for keyPath in observedKeyPaths {
            player.removeObserver(self, forKeyPath: keyPath, context: &DefaultVideoPlayer.observerContext)
        }
    }

    @objc private func playerDidFinishPlaying() {
        _status.value = .finished
    }

    // Observing changes in AVPlayer properties
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &DefaultVideoPlayer.observerContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        if keyPath == #keyPath(AVPlayer.timeControlStatus) {
            switch player.timeControlStatus {
            case .playing:
                _status.value = .playing
            case .paused:
                _status.value = .paused
            default:
                _status.value = .loading
            }
        } else if keyPath == #keyPath(AVPlayer.currentItem.status), let playerItem = player.currentItem {
            switch playerItem.status {
            case .readyToPlay:
                _status.value = .readyToPlay
            default:
                _status.value = .failed
            }
        }
    }
}


// ******************************************************
// MARK: DefaultVideoView
// ******************************************************
import AVFoundation

class DefaultVideoView: UIView {
    
    var player: DefaultVideoPlayer? {
        didSet {
            let layer = AVPlayerLayer(player: player?.player)
            layer.frame = self.bounds
            layer.videoGravity = .resizeAspect
            self.layer.addSublayer(layer)
        }
    }
}
