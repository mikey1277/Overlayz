//
//  FadingScrollView.swift
//  Overlayz
//
//  Created by occlusion on 5/16/25.
//

import SwiftUI
import SwiftUIIntrospect

/// A ScrollView that fades out its content at the top and bottom edges.
struct FadingScrollView<Content: View>: View {
    // The height of the fading area at top and bottom
    let fadeHeight: CGFloat = 32
    let content: () -> Content

    var body: some View {
        // Place ScrollView and apply a mask to it
        ScrollView {
            content()
        }
        //not working in preview but works in app
        .introspect(.scrollView, on: .macOS(.v13, .v14, .v15), customize: { scrollView in
            scrollView.scrollerInsets = NSEdgeInsets(top: fadeHeight/2, left: 0, bottom: fadeHeight/2, right: 0)
        })
        .mask(
            VStack(spacing: 0) {
                // Top fade: transparent → opaque
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)

                // Middle area: fully opaque
                Rectangle()
                    .frame(maxHeight: .infinity)
                
                // Bottom fade: opaque → transparent
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        )
    }
}

#Preview {
    FadingScrollView {
        VStack(spacing: 16) {
            ForEach(0..<50) { i in
                Text("Item \(i)")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.black))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal).padding(.vertical, 50)
    }
}
