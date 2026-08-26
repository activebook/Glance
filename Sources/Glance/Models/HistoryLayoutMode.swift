import Foundation

/// Layout presentations for the Glance History browser.
public enum HistoryLayoutMode: String, Codable, CaseIterable, Identifiable {
    /// Left sidebar list with right detail inspector (standard split view).
    case sidebar = "sidebar"
    /// Top horizontal filmstrip carousel with bottom full-width detail inspector (Finder-style gallery).
    case gallery = "gallery"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sidebar: return "List View"
        case .gallery: return "Gallery View"
        }
    }

    public var systemImage: String {
        switch self {
        case .sidebar: return "list.bullet"
        case .gallery: return "rectangle.split.1x2"
        }
    }
}
