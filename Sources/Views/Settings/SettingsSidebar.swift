import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 22)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(width: 216, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20, alignment: .center)

            Text(section.rawValue)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(selection == section ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .frame(width: 192, height: 38, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == section ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            selection = section
        }
    }
}
