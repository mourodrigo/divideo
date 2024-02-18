//
//  ProgressScreen.swift
//  divideo
//
//  Created by Rodrigo Bueno on 18/02/24.
//

import Foundation
import SwiftUI
import AVKit
import Photos

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
