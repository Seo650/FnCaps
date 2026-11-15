import AppKit
import FnCapsCore
import SwiftUI
import UniformTypeIdentifiers

/// 앱별 설정 목록(「고급」의 앱별 설정 상자 안 내용). 앱은 번들 ID로만 저장하고 고른 앱을 실행하지 않는다.
/// 목록의 앱이 맨 앞인 동안 FnCaps를 끈다. 앱별 대기 시간은 2026-11-11에 없앴다(행에는 이름만 있다).
struct AppExceptionList: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState

    private var exceptions: [SettleException] { model.snapshot.settleExceptions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: L("apps.caption"))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.rowInset)
                .padding(.top, DS.s(12))
                .padding(.bottom, DS.s(4))
            if exceptions.isEmpty {
                Text(verbatim: L("apps.empty"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: DS.s(38), alignment: .center)
            } else {
                ForEach(exceptions, id: \.bundleID) { e in
                    row(e)
                }
            }
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { addApp() } label: {
                Image(systemName: "plus").frame(width: DS.s(28), height: DS.s(22)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("apps.add.a11y"))
            Divider().frame(height: DS.s(14))
            Button { removeSelected() } label: {
                Image(systemName: "minus").frame(width: DS.s(28), height: DS.s(22)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ui.selectedExceptionID == nil)
            .accessibilityLabel(L("apps.remove.a11y"))
            Spacer(minLength: DS.s(8))
            if ui.exceptionError {
                Text(verbatim: L("apps.error.noBundleID"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(DS.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.s(12))
        .padding(.vertical, DS.s(8))
    }

    private func row(_ e: SettleException) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleID)
        let name = url.map { Self.appName($0) } ?? e.bundleID
        let selected = ui.selectedExceptionID == e.bundleID
        return HStack(spacing: DS.s(10)) {
            icon(url)
            Text(verbatim: name).font(DS.rowTitle).lineLimit(1)
            Spacer(minLength: DS.s(8))
        }
        .padding(.horizontal, DS.rowInset)
        .frame(minHeight: DS.s(38))
        .background(selected ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { ui.selectedExceptionID = e.bundleID }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Finder 이름. 「확장자 모두 보기」가 켜져 있어도 「.app」은 떼고 보인다.
    private static func appName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    @ViewBuilder
    private func icon(_ url: URL?) -> some View {
        if let url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: DS.s(20), height: DS.s(20))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: DS.s(5), style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: DS.s(20), height: DS.s(20))
                .overlay(Image(systemName: "app").font(DS.label).foregroundStyle(.secondary))
                .accessibilityHidden(true)
        }
    }

    private func removeSelected() {
        guard let id = ui.selectedExceptionID else { return }
        model.removeSettleException(bundleID: id)
        ui.selectedExceptionID = nil
        ui.exceptionError = false
    }

    private func addApp() {
        ui.exceptionError = false
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let id = Bundle(url: url)?.bundleIdentifier
            if let id, exceptions.contains(where: { $0.bundleID == id }) {
                // 이미 있는 앱이면 그 행을 고른다.
                ui.selectedExceptionID = id
            } else if model.addSettleException(appURL: url), let id {
                ui.selectedExceptionID = id
            } else {
                ui.exceptionError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ui.exceptionError = false }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            panel.begin(completionHandler: handle)
        }
    }
}
