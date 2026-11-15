import AppKit
import FnCapsCore
import SwiftUI

/// P4 「고급」: 길게 누르기 → 전환 → 앱별 설정 → 초기화(D-39, FINAL-REVIEW §3-1 A·B·D).
struct AdvancedPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState

    private var snapshot: AppSnapshot { model.snapshot }

    private func ms(_ value: Int) -> String { LF("settings.value.ms", value) }

    // MARK: 길게 누르기

    /// 길게 누르기가 꺼졌거나 Caps 목록에 영어 입력 소스가 없으면 시간·입력 소스 행을 쓸 수 없다(M3, D-26).
    private var longRowsDisabled: Bool { !snapshot.capsLongEnabled || !snapshot.capsHasEnglish }

    private var capsBox: some View {
        KeyZoneBox {
            Keycap(kind: .caps)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                SettingRow(title: L("longpress.enable.title"), caption: L("advanced.long.enable.caption"), ui: ui) {
                    Toggle(L("longpress.enable.title"), isOn: Binding(
                        get: { snapshot.capsLongEnabled },
                        set: { model.setCapsLongEnabled($0) }))
                        .greenSwitch()
                }
                if snapshot.capsLongEnabled, !snapshot.capsHasEnglish {
                    Text(verbatim: L("longpress.noEnglish.note"))
                        .font(DS.caption)
                        .foregroundStyle(DS.warn)
                        .lineSpacing(DS.s(2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.rowInset)
                        .padding(.top, DS.s(-4))
                        .padding(.bottom, DS.s(10))
                }
                SettingsDivider()
                SettingRow(
                    title: L("longpress.time.title"),
                    caption: L("advanced.long.time.caption"),
                    vertical: true,
                    ui: ui
                ) {
                    // 300...1000 ms, 50 ms 단위, 기본 500(CapsPressJudge).
                    MsSlider(
                        title: L("longpress.time.title"),
                        value: Binding(
                            get: { model.capsLongPressMs },
                            set: { model.setCapsLongPressMs($0) }),
                        range: CapsPressJudge.minMs...CapsPressJudge.maxMs,
                        step: CapsPressJudge.stepMs,
                        mark: CapsPressJudge.defaultMs,
                        markLabel: { LF("advanced.tick.default", $0) },
                        accessibilityValue: { LF("longpress.time.a11y", $0) })
                }
                .disabled(longRowsDisabled)
                SettingsDivider()
                SettingRow(
                    title: L("advanced.long.layouts.title"),
                    caption: L("advanced.long.layouts.caption"),
                    ui: ui
                ) {
                    Toggle(L("advanced.long.layouts.title"), isOn: Binding(
                        get: { model.capsLongLayoutsOnly },
                        set: { model.setCapsLongLayoutsOnly($0) }))
                        .greenSwitch()
                }
                .disabled(longRowsDisabled)
            }
        }
    }

    private var fnBox: some View {
        KeyZoneBox {
            Keycap(kind: .fn)
        } content: {
            SettingRow(title: L("window.longPressToggle"), caption: L("advanced.long.fn.caption"), ui: ui) {
                Toggle(L("window.longPressToggle"), isOn: Binding(
                    get: { snapshot.cancelOnLongPress },
                    set: { model.setCancelOnLongPress($0) }))
                    .greenSwitch()
            }
        }
    }

    // MARK: 전환

    private var switchGroup: some View {
        SettingsGroup(title: L("advanced.group.switch")) {
            SettingRow(
                title: L("advanced.settle.title"),
                info: (id: "settle", text: L("advanced.settle.info")),
                vertical: true,
                ui: ui
            ) {
                // 0...150 ms, 5 ms 단위, 권장 80(SettleTimePolicy).
                MsSlider(
                    title: L("advanced.settle.title"),
                    value: Binding(
                        get: { snapshot.settleGlobalMs },
                        set: { model.setSettleGlobalMs($0) }),
                    range: SettleTimePolicy.range,
                    step: SettleTimePolicy.stepMs,
                    mark: SettleTimePolicy.defaultMs,
                    markLabel: { LF("advanced.settle.recommended", $0) },
                    accessibilityValue: { ms($0) })
            }
        }
    }

    // MARK: 초기화

    private var resetGroup: some View {
        SettingsGroup(title: L("advanced.group.reset")) {
            SettingRow(title: L("advanced.reset.lists.title"), caption: L("advanced.reset.lists.caption"), ui: ui) {
                Button(L("advanced.reset.lists.button")) {
                    Self.confirm(L("advanced.reset.lists.confirm")) { model.resetKeyLists() }
                }
                .buttonStyle(PillButtonStyle())
            }
            SettingsDivider()
            SettingRow(title: L("advanced.reset.all.title"), caption: L("advanced.reset.all.caption"), ui: ui) {
                Button(L("advanced.reset.all.button")) {
                    Self.confirm(L("advanced.reset.all.confirm")) { model.resetAllSettings() }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    /// 확인 창(R4). 「초기화」를 눌렀을 때만 action을 부른다. 화면 상태 속성 없이 쓰려고 NSAlert를 쓴다.
    private static func confirm(_ message: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        let reset = alert.addButton(withTitle: L("advanced.reset.confirmButton"))
        reset.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: L("advanced.reset.cancel"))
        cancel.keyEquivalent = "\u{1b}"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { action() }
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.groupSpacing) {
                Text(verbatim: L(SettingsPage.advanced.titleKey))
                    .font(DS.pageTitle)

                VStack(alignment: .leading, spacing: DS.groupTitleGap) {
                    Text(verbatim: L("advanced.group.long"))
                        .font(DS.groupTitle)
                        .foregroundStyle(.secondary)
                        .padding(.leading, DS.s(4))
                    VStack(spacing: DS.s(10)) {
                        capsBox
                        fnBox
                    }
                }

                switchGroup

                SettingsGroup(title: L("apps.group")) {
                    AppExceptionList(model: model, ui: ui)
                }

                resetGroup
            }
            .padding(.horizontal, DS.pageInsetH)
            .padding(.top, DS.pageInsetTop)
            .padding(.bottom, DS.s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// ms 슬라이더 + 값 줄(최소 / 현재 / 최대). 값 글자는 슬라이더 폭 기준 비율 위치에 둔다.
/// 한 점 눈금은 SwiftUI SliderTick(macOS 26.0+)이 있을 때만 그린다(PA8). macOS 14·15는 값 글자만.
private struct MsSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let mark: Int
    let markLabel: (Int) -> String
    let accessibilityValue: (Int) -> String

    private let width: CGFloat = DS.s(300)
    /// 현재 값 글자 칸 폭. 끝 글자와 겹치면 끝 글자를 숨긴다.
    private let currentWidth: CGFloat = DS.s(120)

    private var doubleValue: Binding<Double> {
        Binding(get: { Double(value) }, set: { value = Int($0.rounded()) })
    }

    private var bounds: ClosedRange<Double> { Double(range.lowerBound)...Double(range.upperBound) }

    private func x(_ v: Int) -> CGFloat {
        width * CGFloat(v - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    private func ms(_ v: Int) -> String { LF("settings.value.ms", v) }

    /// 값은 step 단위로 반올림해 넘긴다. macOS 26 Slider는 step을 주면 단계마다 눈금을 그리므로,
    /// 눈금 하나만 그리려고 macOS 26에서는 step 없는 `ticks:` 초기화와 반올림 Binding을 쓴다.
    private var steppedValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { raw in
                let snapped = (raw - Double(range.lowerBound)) / Double(step)
                value = range.lowerBound + Int(snapped.rounded()) * step
            })
    }

    @ViewBuilder
    private var slider: some View {
        if #available(macOS 26, *) {
            Slider(value: steppedValue, in: bounds,
                   label: { Text(verbatim: title) },
                   ticks: { SliderTick(Double(mark)) })
        } else {
            Slider(value: doubleValue, in: bounds, step: Double(step)) { Text(verbatim: title) }
        }
    }

    /// 11 pt 글자 폭 어림(ASCII 6, 그 밖의 라틴·키릴 7, 한중일 11). 끝 글자와 겹치는지 가리는 데만 쓴다.
    private func estimatedWidth(_ text: String) -> CGFloat {
        text.unicodeScalars.reduce(0) {
            $0 + ($1.isASCII ? DS.s(6) : ($1.value < 0x2E80 ? DS.s(7) : DS.s(11)))
        }
    }

    var body: some View {
        let current = value == mark ? markLabel(value) : ms(value)
        let half = estimatedWidth(current) / 2
        let cx = min(max(x(value), half), width - half)
        let gap: CGFloat = DS.s(8)
        VStack(alignment: .leading, spacing: DS.s(6)) {
            slider
                .labelsHidden()
                .tint(Color.primary.opacity(0.55))
                .frame(width: width)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue(value))
            ZStack(alignment: .leading) {
                if cx - half > estimatedWidth(ms(range.lowerBound)) + gap {
                    Text(verbatim: ms(range.lowerBound)).frame(width: width, alignment: .leading)
                }
                if cx + half < width - estimatedWidth(ms(range.upperBound)) - gap {
                    Text(verbatim: ms(range.upperBound)).frame(width: width, alignment: .trailing)
                }
                Text(verbatim: current)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: currentWidth)
                    .offset(x: cx - currentWidth / 2)
            }
            .font(DS.caption)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(.bottom, DS.s(2))
    }
}
