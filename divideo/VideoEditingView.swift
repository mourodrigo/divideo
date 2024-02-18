//
//  VideoEditingView.swift
//  divideo
//
//  Created by Rodrigo Bueno on 18/02/24.
//

import Foundation
import SwiftUI
import AVKit

struct VideoEditingView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
