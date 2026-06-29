import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.top, 18)

            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.vertical, 8)
                    .tag(section)
                    .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 8)
            }
        }
        .background(.regularMaterial)
    }
}
