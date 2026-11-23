import AppKit
import SwiftUI

/// Whole-script reading alignment is a local presentation preference, not text markup.
enum ManuscriptAlignment: String, CaseIterable, Identifiable {
    case left, center, right
    var id: Self { self }
    var native: NSTextAlignment {
        switch self { case .left: .left; case .center: .center; case .right: .right }
    }
    var title: String {
        switch self {
        case .left: MacCopy.text("左对齐", "Align left")
        case .center: MacCopy.text("居中", "Align center")
        case .right: MacCopy.text("右对齐", "Align right")
        }
    }
    var symbol: String {
        switch self { case .left: "text.alignleft"; case .center: "text.aligncenter"; case .right: "text.alignright" }
    }
}

struct ManuscriptAlignmentPicker: View {
    @Bindable var preferences: MacPreferences
    var body: some View {
        Picker(MacCopy.text("文字对齐", "Text alignment"), selection: $preferences.textAlignment) {
            ForEach(ManuscriptAlignment.allCases) { alignment in
                Image(systemName: alignment.symbol).tag(alignment)
                    .accessibilityLabel(alignment.title).help(alignment.title)
                    .accessibilityIdentifier("alignment-\(alignment.rawValue)")
            }
        }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 108)
            .accessibilityIdentifier("manuscript-alignment")
    }
}
