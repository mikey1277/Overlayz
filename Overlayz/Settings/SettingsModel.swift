//
//  SettingsModel.swift
//  Overlayz
//
//  Created by occlusion on 6/11/25.
//

import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case dawn, dark, automatic
    var id: String { rawValue }
    /// system icon name for each appearance
    var iconName: String {
        switch self {
        case .dawn: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .automatic: return "circle.lefthalf.fill"
        }
    }
}

/// Supported API providers
enum APIProvider: String, CaseIterable, Identifiable {
    case google = "Google"
    case azure = "Azure"
    case openAI = "OpenAI"
    var id: String { rawValue }
}



class SettingsModel: ObservableObject{
    @AppStorage("Appearance") var appearance: Appearance = .automatic
    @AppStorage("ShowRelatedNotes") var showRelatedNotes: Bool = true
    @AppStorage("APIProvider") var apiProvider: APIProvider = .google

    @AppStorage("APIKey_Google") var keyGoogle: String = ""
    @AppStorage("APIKey_Azure") var keyAzure: String = ""
    @AppStorage("APIKey_OpenAI") var keyOpenAI: String = ""
    
    static let shared = SettingsModel()
}
