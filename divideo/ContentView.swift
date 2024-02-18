import SwiftUI
import AVFoundation
import AVKit
import Photos
import MobileCoreServices

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


