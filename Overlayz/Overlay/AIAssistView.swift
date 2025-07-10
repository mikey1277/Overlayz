//
//  AIAssistView.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import SwiftUI
import Combine

struct AIAssistView: View {
    var window: NSWindow?
    @Environment(\.colorScheme) private var colorScheme
    
    var lastMessages: [MessageData]{
        return connectionManager.lastMessages
    }
    @State private var inputText: String = ""
    @State private var messages: [String] = []
    
    @State var hasLastMessage = false
    @State private var showThinkingView: Bool = false
    @State private var showSelectedTextView: Bool = false
    @State private var showResultView: Bool = false
    @State private var smarterAnalysisExpanded: Bool = false

    @State var observation: NSKeyValueObservation? = nil
    @FocusState private var isTextFieldFocused: Bool

    // Connect to managers
    @ObservedObject private var connectionManager = AIConnectionManager.shared
    @ObservedObject private var contextManager = AIContextManager.shared
    @ObservedObject private var overlayManager = AIAssistOverlayManager.shared
    
    @Namespace private var commandNamespace
    
    // Computed property to access the streaming result
    private var result: String {
        connectionManager.messageStream
    }
    
    // Computed property to check if AI is thinking
    private var isThinking: Bool {
        connectionManager.isReceiving
    }
    
    private var hasSelectedText: Bool {
        !contextManager.selectedText.isEmpty
    }


    private var isReceiving: Bool {
        showThinkingView || showResultView || hasLastMessage
    }
    
    // For cleaning up subscriptions
    @State private var cancellables = Set<AnyCancellable>()

    var subBody: some View {
        VStack{
            if isReceiving{
                ZStack{
                    VStack{
                        HStack{
                            Button {
                                AIAssistOverlayManager.shared.toggle()
                            } label: {
                                Image("icon_close")
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            Button {
                                
                            } label: {
                                Image("icon_history")
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                // Clear the current conversation
                                connectionManager.clearConversation()
                                connectionManager.lastMessages.removeAll()
                                // Keep the view expanded after clearing
                                hasLastMessage = true
                            } label: {
                                Image("icon_plus")
                            }
                            .buttonStyle(.plain)

                        }
                        Spacer()
                    }
                    .padding([.horizontal, .top])
                    ScrollViewReader { proxy in
                        FadingScrollView {
                            VStack(spacing: 0){
                                    ForEach(lastMessages) { message in
                                        VStack(spacing: 0){
                                            // Consistent padding above each message for breathing room
                                            Color.clear.frame(height: 4).zIndex(-1).id("scroll-padding-\(message.id)")
                                            Color.clear.frame(height: 8).zIndex(-1).id(message.topId)
                                            HStack{
                                                if message.isUser{
                                                    Spacer()
                                                    Text(message.message)
                                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color(red: 0, green: 0, blue: 0).opacity(0.91))
                                                        .font(.system(size: 12, weight: .light))
                                                        .padding(12)
                                                        .frame(minWidth: 10, maxWidth: 320)
                                                        .fixedSize(horizontal: true, vertical: true)
                                                        .background(Color(red: 0, green: 0, blue: 0).opacity(0.05))
                                                        .cornerRadius(12)
                                                }
                                                else{
                                                    FadeInTextView(
                                                        text: .constant(message.message),
                                                        wordDelay: 0.00,
                                                        fadeInDuration: 1.0,
                                                        font: .systemFont(ofSize: 13, weight: .light),
                                                        foregroundColor: colorScheme == .dark ? .white : .black
                                                    )
                                                        .padding(.top, 4)
                                                    Spacer()
                                                }
                                            }.id(message.id)
                                            Color.clear.frame(height: 8).zIndex(-1).id(message.bottomId)
                                        }.padding(.vertical, -8)
                                    }
                                
                                if showThinkingView || hasLastMessage{
                                    VStack{
                                        HStack{
                                            ShimmerTextView(
                                                text: "Thinking...",
                                                font: .system(size: 14).italic(),
                                                textColor: Color(white: 0.33),
                                                intensity: 0.8
                                            ).opacity(isThinking ? 1 : 0)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                }
                                
                                // Add spacing before the current AI response
                                if !result.isEmpty && !lastMessages.isEmpty {
                                    Color.clear.frame(height: 4)
                                }
                                
                                FadeInTextView(
                                    text: .constant(result),
                                    wordDelay: 0.09,
                                    fadeInDuration: 1.5,
                                    font: .systemFont(ofSize: 13, weight: .light),
                                    foregroundColor: colorScheme == .dark ? .white : .black
                                )
                                
                                // Consistent bottom spacing when in conversation mode
                                if isReceiving {
                                    Color.clear.frame(height: 150)
                                }
                            }
                            .padding(20)
                        }.onChange(of: lastMessages) { oldValue, newValue in
                            withAnimation {
                                if let last = lastMessages.last{
                                    proxy.scrollTo("scroll-padding-\(last.id)", anchor: .top)
                                }
                            }
                        }
                        // .onChange(of: result){ oldValue, newValue in
                        //     DispatchQueue.main.asyncAfter(deadline: .now() + 0.3){
                        //         withAnimation {
                        //             if let last = lastMessages.last{
                        //                 proxy.scrollTo(last.topId, anchor: .top)
                        //             }
                        //         }
                        //     }
                        // }
                        .scrollIndicators(.never)
                    }.padding(.top, 32)
                }
                .frame(maxHeight: 275)
                .transition(.move(edge: .bottom))
            }
            
            // Input bar
            VStack{
                HStack {
                    ZStack() {
                        // Placeholder
                        HStack{
                            if showSelectedTextView, isReceiving{
                                selectedTextView(false)
                                .padding(4)
                            }

                            if inputText.isEmpty {
                                Text("How can I help?")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0, green: 0, blue: 0).opacity(0.44))
                                    .padding(.horizontal, 6)
                            }
                            Spacer()
                        }
                        
                        TextEditor(text: $inputText)
                            .onKeyPress(.return, action: {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    return .ignored
                                }
                                send()
                                return .handled
                            })
                            .padding(.leading, (showSelectedTextView && isReceiving) ? 60 : 0)
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .regular))
                            .lineSpacing(3)
                            .background(Color.clear)
                            .scrollContentBackground(.hidden)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                            .scrollIndicators(.never)
                            .focused($isTextFieldFocused)
                    }
                    Spacer()
                    if isReceiving{
                        Image("icon_command").padding(8).matchedGeometryEffect(id: "commandIcon", in: commandNamespace)
                    }
                    
                }
                .frame(minHeight: 44)
                .padding(12)
                .background(Color(red: 1, green: 1, blue: 1).opacity(0.45))
                .cornerRadius(8)
                .shadow(
                    color: Color(red: 0.78, green: 0.78, blue: 0.78, opacity: 0.10), radius: 11, y: 5
                )
                .layoutPriority(1)
                
                if !isReceiving{
                    HStack {
                        HStack(spacing: 8) {
                            smarterAnalysisView()
                            if showSelectedTextView {
                                selectedTextView(true)
                            }
                        }
                        Spacer()
                        Image("icon_command").padding(.vertical, 8).matchedGeometryEffect(id: "commandIcon", in: commandNamespace)
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
                }
                
            }
            .padding(.vertical).padding(.horizontal, 8)
        }
    }
    
    var body: some View {
        VStack{
            Spacer()
            VStack(spacing: 0) {
                ZStack(alignment: .bottom){
                    
                    Rectangle()
                        .fill(.regularMaterial).animation(nil, value: UUID())
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 540, height: 0)
                        .position(x:270, y:0)
                        .background(
                        EllipticalGradient(
                            stops: [
                                Gradient.Stop(color: .white.opacity(0), location: 0.00),
                                Gradient.Stop(color: Color(red: 1, green: 0.79, blue: 0.58).opacity(0.7), location: 0.55),
                                Gradient.Stop(color: .white.opacity(0), location: 1.00),
                            ],
                            center: UnitPoint(x: 0.5, y: 0.95)
                        ).animation(nil, value: UUID()).frame(width: 1040, height: 120)
                            .blur(radius: 20).opacity(colorScheme == .dark ? 0.2 : 0.7)
                        ).animation(nil, value: UUID()).frame(width: 1040, height: 120)

                    subBody.layoutPriority(1)
                }
                .frame(width: 480)
                .cornerRadius(16)
                .padding()
                .onChange(of: isThinking) { oldValue, newValue in
                    showThinkingView = newValue
                }
                .onChange(of: hasSelectedText) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSelectedTextView = newValue
                    }
                }
                .onChange(of: result) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showResultView = !newValue.isEmpty
                    }
                }
                .onChange(of: lastMessages) { newValue in
                    withAnimation {
                        hasLastMessage = !newValue.isEmpty
                    }
                }
                .onChange(of: contextManager.selectedText) { _, newValue in

                    if window?.isVisible == true{
                        isTextFieldFocused = true
                        NSApp.activate(ignoringOtherApps: true)
                        window?.makeKeyAndOrderFront(nil)
                    }

                }
                .onChange(of: contextManager.didChangeSelectedText) { _, newValue in
                    if window?.isVisible == true{
                        isTextFieldFocused = true
                        NSApp.activate(ignoringOtherApps: true)
                        window?.makeKeyAndOrderFront(nil)
                    }
                }
                .onChange(of: smarterAnalysisExpanded) { _, newValue in
                    if newValue {
                        // Capture image context when smarter analysis is enabled
                        Task {
                            try? await contextManager.captureCurrentContext(captureImage: true)
                        }
                    }
                }
                .onAppear {
                    
                    observation = self.window?.observe(\.isVisible, options: [.new]) { _, change in
                        if change.newValue == true {
                            didAppear()
                        }
                    }
                }

            }
        }
    }
    
    func didAppear(){
        isTextFieldFocused = true
    }
    
    private func selectedTextView(_ detail:Bool) -> some View {
        HStack(spacing: 4){
            Image("icon_selected_text")
            if detail{
                Text("Selected text in use")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
            }
            Button {
                contextManager.selectedText = ""
            } label: {
                Image(systemName: "xmark").resizable().frame(width: 10, height: 10).foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.5)).cornerRadius(16)
//        .matchedGeometryEffect(id: "selectedText", in: commandNamespace)
    }
    
    private func smarterAnalysisView() -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                smarterAnalysisExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pano")
                    .font(.system(size: 12))
                if smarterAnalysisExpanded {
                    Text("Deeper Analysis")
                        .font(.system(size: 12))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, smarterAnalysisExpanded ? 12 : 8)
            .padding(.vertical, 8)
            .background(
                Color(red: 0.96, green: 0.96, blue: 0.96).opacity(0.25)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
                    .opacity(smarterAnalysisExpanded ? 1 : 0)
            )
            .cornerRadius(100)
            .shadow(
                color: Color.white,
                radius: smarterAnalysisExpanded ? 2 : 0,
                x: smarterAnalysisExpanded ? 1 : 0,
                y: 0
            )
            .shadow(
                color: Color.white.opacity(0.25),
                radius: smarterAnalysisExpanded ? 6 : 0,
                x: 0,
                y: smarterAnalysisExpanded ? 4 : 0
            )
        }
        .buttonStyle(.plain)
    }
    
    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Add user message to display
        Task{ @MainActor in
            // Clear input immediately

            self.inputText = ""
        }

        Task{
            
            try await connectionManager.sendMessage(trimmed, smarterAnalysisEnabled: smarterAnalysisExpanded)
            
        }
    }
}

#Preview {
    AIAssistView(window: nil)
        .frame(width: 500, height: 320).background(.blue)
}
