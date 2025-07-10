//
//  AIAssistView.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import SwiftUI
import Combine

// MARK: – ViewModifier that shifts view vertically by a fixed amount
struct SlideOffsetModifier: ViewModifier {
    let offsetY: CGFloat
    func body(content: Content) -> some View {
        content.offset(y: offsetY)
    }
}

extension AnyTransition {
    /// Slide from top by `distance` + asymmetric fade timing
    static func slightSlideFromTop(distance: CGFloat = 80) -> AnyTransition {
        // Base slide modifier
        let slide = AnyTransition.modifier(
            active: SlideOffsetModifier(offsetY: -distance),
            identity: SlideOffsetModifier(offsetY: 0)
        )

        let insertion = slide
            .combined(with: .opacity)
            .animation(.easeInOut(duration: 0.2))

        let removal = slide
            .combined(with: .opacity)
            .animation(.linear(duration: 0.1))

        return .asymmetric(insertion: insertion, removal: removal)
    }
}
// MARK: – Reusable row for a shortcut

/// A custom disclosure group with its indicator on the right.
struct RightArrowDisclosure<Label: View, Content: View>: View {
    /// Binding to control expanded state
    @Binding var isExpanded: Bool
    /// Label view for the header
    let label: Label
    /// Content to show when expanded
    let content: () -> Content

    init(isExpanded: Binding<Bool>,
         @ViewBuilder label: () -> Label,
         @ViewBuilder content: @escaping () -> Content) {
        self._isExpanded = isExpanded
        self.label = label()
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with text on left and chevron on right
            HStack {
                label
                Spacer()
                Image(systemName: "chevron.up")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            .padding(.vertical, 6)
            
            // Body content only when expanded
            if isExpanded {
                content()
                    .padding(.top, 8)
                // use custom slight slide instead of full move(edge:.top)
                    .transition(.slightSlideFromTop(distance: 50))
              }
        }
    }
}

struct ShortcutRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @State var keys = [String]()
    var hasToggle: Bool = false
    @Binding var isEditing: Bool
    @Binding var toggleOn: Bool
    @Binding var shortcut: Shortcut
    
    var editCallback: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                
                Text(title)
                Spacer()

                if isEditing{
                    Text("Recording...")
                        .foregroundStyle(.gray)
                        .font(.system(size: 10, weight: .light))
                        .padding(8).padding(.horizontal, 8)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.gray ,lineWidth: 1)
                        )

                }
                else{
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 16, height: 16)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(.lightGray) ,lineWidth: 1)
                            )
                    }
                }
                Button {
                    isEditing.toggle()
                    editCallback?(isEditing)
                } label: {
                    Image("icon_setting_shortcut_edit")
                        .contentShape(Rectangle())
                        .padding(8)
                        .background(colorScheme == .light ? .white : .black.opacity(0.5)).cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if hasToggle {
                HStack {
                    Text("|").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Show related notes with quick capture (coming soon)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    Spacer()

                    // TODO: disabled until we implement
                    Toggle("", isOn: $toggleOn)
                        .labelsHidden().toggleStyle(.switch).scaleEffect(0.7)
                        .disabled(true)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: shortcut) { oldValue, newValue in
            reload()
        }
        .onAppear{
            reload()
        }
    }
    func reload(){
        keys.removeAll()
        if shortcut.modifiers.contains(.command){
            keys.append("⌘")
        }
        if shortcut.modifiers.contains(.shift){
            keys.append("⇧")
        }
        if shortcut.modifiers.contains(.option){
            keys.append("⌥")
        }
        if shortcut.modifiers.contains(.control){
            keys.append("^")
        }
        keys.append(shortcut.key.uppercased())

    }
}

struct SelectionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let baseColor: Color = Color(red: 0.94, green: 0.74, blue: 0.56)
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // Ensure consistent button height across all appearance options
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? baseColor.opacity(0.3)
                        : colorScheme == .light ? .white : .black.opacity(0.5)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isSelected
                            ? baseColor
                            : Color.clear
                        ,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct SettingsView: View {
    var window: NSWindow?
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showShortcuts = true
    @State private var showTheme = true
    @State private var showAdvanced = true
    @State private var showAccount = true
    
    @FocusState private var isTextFieldFocused: Bool

    @State private var editingAssistant = false
    @State private var editingCapture = false
    @State private var editingNotes = false
    
    @ObservedObject var model = SettingsModel.shared
    @ObservedObject var inputEventModel = InputEventManager.shared.model
    @ObservedObject var authModel = AuthManager.shared.model
    
    private var currentAPIKey: Binding<String> {
        switch model.apiProvider {
        case .google:
            return $model.keyGoogle
        case .azure:
            return $model.keyAzure
        case .openAI:
            return $model.keyOpenAI
        }
    }
    
    var body: some View {
        VStack{
            Color.clear.frame(height: 24)
            
//            ScrollView{
                VStack(alignment: .leading, spacing: 24) {

                    RightArrowDisclosure(isExpanded: $showShortcuts){
                        Text("Customise Shortcuts")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    showShortcuts.toggle()
                                }
                            }
                    } content: {
                        VStack(spacing: 0) {
                            ShortcutRow(
                                title: "Stella Assist",
                                isEditing: $editingAssistant,
                                toggleOn: .constant(false),
                                shortcut: $inputEventModel.aiAssistShortcut)
                                { edit in
                                    editingCapture = false
                                    editingNotes = false
                                    isTextFieldFocused = false
                                    if edit{
                                        InputEventManager.shared.requestCallback = { code in
                                            if code.modifiers.isEmpty ||
                                                inputEventModel.autoContextShortcut == code ||
                                                inputEventModel.quickCaptureShortcut == code
                                            {
                                                return false
                                            }
                                            DispatchQueue.main.async {
                                                inputEventModel.aiAssistShortcut = code
                                                self.editingAssistant = false
                                            }
                                            return true
                                        }
                                    }
                                    else{
                                        InputEventManager.shared.requestCallback = nil
                                    }
                                    
                                }

                            ShortcutRow(
                                title: "Quick Capture",
                                hasToggle: true,
                                isEditing: $editingCapture,
                                toggleOn: $model.showRelatedNotes,
                                shortcut: $inputEventModel.quickCaptureShortcut)
                            { edit in
                                editingAssistant = false
                                editingNotes = false
                                isTextFieldFocused = false
                                if edit{
                                    InputEventManager.shared.requestCallback = { code in
                                        if code.modifiers.isEmpty ||
                                            inputEventModel.autoContextShortcut == code ||
                                            inputEventModel.aiAssistShortcut == code
                                        {
                                            return false
                                        }
                                        DispatchQueue.main.async {
                                            inputEventModel.quickCaptureShortcut = code
                                            self.editingCapture = false
                                        }
                                        return true
                                    }
                                }
                                else{
                                    InputEventManager.shared.requestCallback = nil
                                }
                                
                            }

                            ShortcutRow(
                                title: "Auto Surface Related Notes (In Beta)",
                                isEditing: $editingNotes,
                                toggleOn: .constant(false),
                                shortcut: $inputEventModel.autoContextShortcut)
                            { edit in
                                editingAssistant = false
                                editingCapture = false
                                isTextFieldFocused = false
                                if edit{
                                    InputEventManager.shared.requestCallback = { code in
                                        if code.modifiers.isEmpty ||
                                            inputEventModel.quickCaptureShortcut == code ||
                                            inputEventModel.aiAssistShortcut == code
                                        {
                                            return false
                                        }
                                        DispatchQueue.main.async {
                                            inputEventModel.autoContextShortcut = code
                                            self.editingNotes = false
                                        }
                                        return true
                                    }
                                }
                                else{
                                    InputEventManager.shared.requestCallback = nil
                                }

                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // MARK: Theme
                    RightArrowDisclosure(isExpanded: $showTheme) {
                        Text("Theme")
                        // make the entire text area tappable
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // toggle expansion when text is tapped
                                withAnimation {
                                    showTheme.toggle()
                                }
                            }
                    } content: {
                        HStack {
                            Text("Appearance")
                            Spacer()
                            
                            HStack{
                                Button {
                                    withAnimation {
                                        model.appearance = .dawn
                                        NSApp.appearance = NSAppearance(
                                            named: .aqua
                                        )
                                    }
                                } label: {
                                    HStack {
                                        Image("icon_setting_appearance_light")
                                        if model.appearance == .dawn {
                                            Text("Dawn")
                                        }
                                    }
                                }
                                .buttonStyle(
                                    SelectionButtonStyle(isSelected: model.appearance == .dawn)
                                )

                                
                                Button {
                                    
                                    NSApp.appearance = NSAppearance(
                                        named: .darkAqua
                                    )
                                    withAnimation {
                                        model.appearance = .dark
                                    }
                                } label: {
                                    HStack {
                                        Image("icon_setting_appearance_dark")
                                        if model.appearance == .dark {
                                            Text("Dark")
                                        }
                                    }
                                }
                                .buttonStyle(
                                    SelectionButtonStyle(isSelected: model.appearance == .dark)
                                )

                                Button {
                                    NSApp.appearance = nil
                                    withAnimation {
                                        model.appearance = .automatic
                                    }
                                } label: {
                                    HStack {
                                        Image("icon_setting_appearance_auto")
                                        if model.appearance == .automatic {
                                            Text("Auto")
                                        }
                                    }
                                }
                                .buttonStyle(
                                    SelectionButtonStyle(isSelected: model.appearance == .automatic)
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // TODO: enable advanced + API key
                    // RightArrowDisclosure(isExpanded: $showAdvanced) {
                    //     Text("Advanced")
                    //     // make the entire text area tappable
                    //         .contentShape(Rectangle())
                    //         .onTapGesture {
                    //             // toggle expansion when text is tapped
                    //             withAnimation {
                    //                 showAdvanced.toggle()
                    //             }
                    //         }
                    // } content:{
                    //     VStack(spacing: 16) {
                    //         HStack {
                    //             Text("Use API")
                    //             Spacer()
                                
                    //             Menu {
                    //                 // Build the menu items
                    //                 ForEach(APIProvider.allCases) { type in
                    //                     Button(type.rawValue) {
                    //                         model.apiProvider = type
                    //                     }
                    //                 }
                    //             } label: {
                    //                 // The label view, now with a border and background
                    //                 HStack(spacing: 4) {
                    //                     Text(model.apiProvider.rawValue)
                    //                         .foregroundColor(.primary)
                    //                 }
                    //                 .padding(.horizontal, 8)
                    //                 .padding(.vertical, 4)
                    //             }
                    //             .menuStyle(BorderlessButtonMenuStyle())
                    //             .padding(4)
                    //             .background(
                    //                 RoundedRectangle(cornerRadius: 6).fill(
                    //                     colorScheme == .light
                    //                     ? Color.white
                    //                     : Color.black.opacity(0.5))
                    //                 .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)

                    //             ).frame(width: 100)
                                
                    //         }
                            
                    //         HStack {
                    //             Text("API Key")
                    //             Spacer()
                    //             TextField("Paste API Key", text: currentAPIKey)
                    //                 .textFieldStyle(PlainTextFieldStyle())
                    //                 .frame(width: 200)
                    //                 .padding(4)
                    //                 .background(
                    //                     RoundedRectangle(cornerRadius: 0).fill(
                    //                         colorScheme == .light
                    //                         ? Color.white
                    //                         : Color.black.opacity(0.5))
                    //                     .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    //                 )
                    //                 .focused($isTextFieldFocused)

                    //         }
                    //     }
                    //     .padding(.top, 8)
                    // }
                    
                    // MARK: Account
                    RightArrowDisclosure(isExpanded: $showAccount) {
                        Text("Account")
                        // make the entire text area tappable
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // toggle expansion when text is tapped
                                withAnimation {
                                    showAccount.toggle()
                                }
                            }
                    } content:{
                        HStack {
                            if authModel.isAuthenticated {
                                Button {
                                    if let url = URL(string: "https://patternautomation.com/auth/account") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text("Manage Account")
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(colorScheme == .light ? .white : .black.opacity(0.5)))
                                        .opacity(0.5)
                                )
                                Spacer()
                                Button {
                                    AuthManager.shared.logout()
                                } label: {
                                    Text("Log Out")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(colorScheme == .light ? .white : .black.opacity(0.5)))
                                        .opacity(0.5)
                                )
                            } else {
                                Spacer()
                                Button {
                                    AuthManager.shared.startAuthFlow()
                                } label: {
                                    Text("Log In")
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(colorScheme == .light ? .white : .black.opacity(0.5)))
                                        .opacity(0.5)
                                )
                                Spacer()
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Spacer()
                    HStack{
                        Spacer()
                        Image("icon_setting_logo")
                        Spacer()
                    }
                }
                .padding(20)
            }
        .onAppear{
            DispatchQueue.main.async{
                isTextFieldFocused = false
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .inset(by: 0.5)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .ignoresSafeArea(edges: .top)
    }
    
}

#Preview {
    SettingsView(window: nil)
        .frame(width: 500, height: 520).background(.white)
}
