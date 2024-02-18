import SwiftUI
import AVFoundation
import AVKit
import Photos
import MobileCoreServices

// Enum to represent different screens
enum AppScreen {
    case welcome, videoSelection, videoEditing, progress
}

typealias CompletionClosure = ((Swift.Result<Void,Error>) ->())


struct ContentView: View {

    @State private var currentScreen: AppScreen = .welcome
    @State private var selectedVideoURL: URL?

    var body: some View {
        NavigationView {
            content
                .navigationViewStyle(StackNavigationViewStyle())
        }
        .navigationViewStyle(StackNavigationViewStyle()) // For iPad
    }

    @ViewBuilder
    var content: some View {
        VStack {
            Text("divideo")
                .font(.title)
                .padding()

            Spacer()

            Button("Choose Video") {
                currentScreen = .videoSelection
            }
            .font(.title)
            .padding(.top, 50)

            NavigationLink(
                destination: VideoEditingView(
                    currentScreen: $currentScreen,
                    selectedVideoURL: selectedVideoURL ?? URL(fileURLWithPath: "")
                ),
                isActive: .constant(currentScreen == .videoEditing || currentScreen == .progress)
            ) {
                EmptyView()
            }
            .padding(.bottom, 50)
        }
        .sheet(isPresented: .constant(currentScreen == .videoSelection)) {
            VideoSelectionViewController(
                currentScreen: $currentScreen,
                selectedVideoURL: $selectedVideoURL
            )
        }
    }
}

struct VideoEditingView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


struct VideoSelectionViewController: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var currentScreen: AppScreen
    @Binding var selectedVideoURL: URL?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.movie"]
        imagePicker.delegate = context.coordinator
        imagePicker.allowsEditing = false
        return imagePicker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: VideoSelectionViewController

        init(_ parent: VideoSelectionViewController) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let mediaType = info[.mediaType] as? String,
               mediaType == UTType.movie.identifier,
               let videoURL = info[.mediaURL] as? URL {
                parent.selectedVideoURL = videoURL
            }
            picker.dismiss(animated: true) {
                self.parent.presentationMode.wrappedValue.dismiss()
                self.parent.currentScreen = .videoEditing
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.parent.presentationMode.wrappedValue.dismiss()
                self.parent.currentScreen = .welcome
            }
        }
    }
}

struct VideoEditingView: View {
    @Binding var currentScreen: AppScreen
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    
    let videoURL: URL
    @StateObject private var videoPlayer: DefaultVideoPlayer // Use @StateObject to manage the player
    @State private var currentTime: CMTime = .zero
    @State private var markers: [CMTime] = []
    @State private var isSplitting = false
    
    init(currentScreen: Binding<AppScreen>, selectedVideoURL: URL) {
        self._currentScreen = currentScreen
        self.videoURL = selectedVideoURL
        self._videoPlayer = StateObject(wrappedValue: DefaultVideoPlayer(url: selectedVideoURL))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                        VideoPlayer(player: videoPlayer.player)
                            .onAppear {
                                videoPlayer.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: DispatchQueue.main) { time in
                                    currentTime = time
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height) // Adjust the height as needed
                    }
            
            VStack {
                HStack {
                    Button(markers.contains(currentTime) ? "Splitted" : "Split") {
                        if !markers.contains(currentTime) {
                            markers.append(currentTime)
                        }
                    }
                    .padding()
                    .disabled(isSplitting)
                    .foregroundColor(markers.contains(currentTime) ? .yellow : .blue)
                    
                    Button(markers.isEmpty ? "Undo last" : "Undo \(timeString(from:markers.last))") {
                        markers.removeLast()
                    }
                    .padding()
                    .disabled(markers.isEmpty)
                    .opacity(markers.isEmpty ? 0.5 : 1)
                    .foregroundColor(.red)


                }
                NavigationLink(destination:
                                ProgressScreen(
                                    currentScreen: $currentScreen,
                                    markers: self.markers,
                                    videoURL: self.videoURL),
                               label: {
                    Text(markers.isEmpty ? "Tap on split button to split your video" :"Export \(markers.count + 1) videos")
                })
                .disabled(markers.isEmpty)
                .opacity(markers.isEmpty ? 0.2 : 1)
                .frame(maxWidth: .infinity, maxHeight: 50)
            }
            Spacer()
        }
        .background(.black)
        .foregroundColor(.white)
        .navigationBarTitle("Video Editing")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func timeString(from time: CMTime?) -> String {
        guard let time = time else { return "" }

        let totalSeconds = CMTimeGetSeconds(time)
        let seconds = Int(totalSeconds) % 60
        let minutes = Int(totalSeconds) / 60
        let hours = Int(totalSeconds) / 3600

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct ProgressScreen: View {
    @Binding var currentScreen: AppScreen
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0.0
    @State private var isSplitting: Bool = false
    @State var markers: [CMTime] = []
    @State var videoURL: URL

    var body: some View {
        ZStack {
            Color.white.opacity(0.7).edgesIgnoringSafeArea(.all)
            
            VStack {
                if isExporting {
                    ProgressView("Exporting", value: exportProgress, total: 1.0)
                        .padding()
                } else {
                    Text("Export Finished")
                        .font(.title)
                        .padding()
                    
                    Button("Open Gallery") {
                        if let galleryURL = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(galleryURL)
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .onAppear {
            isSplitting = true
            isExporting = true
            exportVideoWithMarkers()
        }
    }
    
    private func exportVideoSegment(asset: AVAsset, startMarker: CMTime, endMarker: CMTime, index: Int, timestamp: TimeInterval, completion: @escaping (CompletionClosure)) {
        print("exportVideoSegment start |\(startMarker)| - end |\(endMarker)|")
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("output-\(timestamp)-\(index).mp4")

        let timeRange = CMTimeRange(start: startMarker, end: endMarker)

        // Configure export session
        exportSession?.timeRange = timeRange
        exportSession?.outputFileType = AVFileType.mp4
        exportSession?.outputURL = outputURL

        exportSession?.exportAsynchronously {
            DispatchQueue.main.async {
                self.isSplitting = false
                switch exportSession?.status {
                case .completed:
                    // Video segment was successfully exported, save it to the camera roll
                    self.saveVideoToCameraRoll(outputURL, completion: completion)
                case .failed, .cancelled:
                    completion(.failure(exportSession?.error ?? NSError.init(domain: "exportVideoSegment failed", code: 0)))
                default:
                    break
                }
            }
        }
    }

    private func exportVideoWithMarkers() {
        guard !markers.isEmpty else {
            isSplitting = false
            return
        }
        
        let asset = AVAsset(url: videoURL)
        
        // Determine the output path for the exported videos
        let exportDirectory = FileManager.default.temporaryDirectory
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Handle directory creation error
            print("Error creating directory: \(error)")
            return
        }
        
        // Sort markers in ascending order
        let sortedMarkers = markers.sorted()
        let timestamp = Date().timeIntervalSince1970
        
        func exportSegmentRecursively(index: Int) {
            if index < sortedMarkers.count {
                if index == 0 {
                    // Export from the beginning to the first marker
                    exportVideoSegment(asset: asset, startMarker: .zero, endMarker: sortedMarkers[index], index: index, timestamp: timestamp) { completion in
                        switch completion {
                        case .success:
                            // Calculate export progress and update it
                            exportProgress = Double(index + 1) / Double(sortedMarkers.count)

                            // Continue exporting the next segment
                            exportSegmentRecursively(index: index + 1)
                        case .failure(let error):
                            print("error \(error)")
                        }
                    }
                } else {
                    // Export between markers
                    let previousMarker = sortedMarkers[index - 1]
                    exportVideoSegment(asset: asset, startMarker: previousMarker, endMarker: sortedMarkers[index], index: index, timestamp: timestamp) { completion in
                        switch completion {
                        case .success:
                            // Calculate export progress and update it
                            exportProgress = Double(index + 1) / Double(sortedMarkers.count)

                            // Continue exporting the next segment
                            exportSegmentRecursively(index: index + 1)
                        case .failure(let error):
                            print("error \(error)")
                        }
                    }
                }
            } else {
                // Export video from the latest marker to the end
                if let lastMarker = sortedMarkers.last {
                    exportVideoSegment(asset: asset, startMarker: lastMarker, endMarker: asset.duration, index: sortedMarkers.count, timestamp: timestamp) { completion in
                        switch completion {
                        case .success:
                            // All segments have been exported
                            isExporting = false // Export is finished
                            print("Export is finished")
                        case .failure(let error):
                            print("error \(error)")
                        }
                    }
                }
            }
        }
        
        // Start exporting segments recursively
        isExporting = true // Exporting started
        exportSegmentRecursively(index: 0)
    }
    
    private func saveVideoToCameraRoll(_ url: URL, completion: @escaping(CompletionClosure)) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            if success {
                completion(.success(()))
            } else if let error = error {
                completion(.failure(error))
            }
        }
    }
}

