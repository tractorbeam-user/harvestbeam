import SwiftUI

/// How a tile's three lines read: like a tracked entry (client, "[code]
/// name", task), or with the code on top (code, name, task).
public enum TileText: String, CaseIterable, Identifiable {
    case entry, codeOnTop

    public static let key = "tileText"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .entry: return "Client, Code and Name, Task"
        case .codeOnTop: return "Code, Name, Task"
        }
    }
}
