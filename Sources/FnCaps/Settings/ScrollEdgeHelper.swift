import AppKit
import SwiftUI

/// 「키와 언어」 쪽 ScrollView가 보이는 영역과 스크롤 함수를 KeysPageState에 넘긴다(W7).
/// `.coordinateSpace(name: "keys")`가 붙은 뷰와 같은 층의 `.background`에 두어 좌표계를 맞춘다.
/// NSScrollView를 찾지 못하면 nil을 넘겨 자동 스크롤만 끄고 끌기·놓기는 그대로 둔다.
struct ScrollEdgeHelper: NSViewRepresentable {
    let keys: KeysPageState

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onResolve = { [weak keys, weak probe] in
            guard let probe else { return }
            guard let info = probe.scrollInfo() else {
                keys?.viewportInKeys = nil
                keys?.scrollBy = nil
                return
            }
            keys?.viewportInKeys = info.viewport
            keys?.scrollBy = info.scroll
        }
        return probe
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.resolve()
    }

    /// 자기 위로 올라가며 감싼 NSScrollView를 찾는다. 스크롤 함수는 범위 안으로 자른다.
    final class Probe: NSView {
        var onResolve: (() -> Void)?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolve()
        }

        func resolve() {
            onResolve?()
        }

        func scrollInfo() -> (viewport: CGRect, scroll: (CGFloat) -> CGFloat)? {
            var ancestor = superview
            var scroll: NSScrollView?
            while let view = ancestor {
                if let found = view as? NSScrollView {
                    scroll = found
                    break
                }
                ancestor = view.superview
            }
            guard let scroll, let document = scroll.documentView else { return nil }
            let clip = scroll.contentView
            let visibleInWindow = clip.convert(clip.bounds, to: nil)
            let selfInWindow = convert(bounds, to: nil)
            guard selfInWindow.height > 0 else { return nil }
            // 창 좌표(왼쪽 아래 기준)를 "keys" 좌표(왼쪽 위 기준)로 바꾼다.
            let viewport = CGRect(x: visibleInWindow.minX - selfInWindow.minX,
                                  y: selfInWindow.maxY - visibleInWindow.maxY,
                                  width: visibleInWindow.width,
                                  height: visibleInWindow.height)
            // 한계는 부를 때마다 다시 잰다. 끄는 동안 상자가 커져 문서가 길어지면
            // 처음 잰 값으로는 끝까지 내려가지 못한다(04-09, 2026-11-11 사용자 보고).
            let scrollClosure: (CGFloat) -> CGFloat = { [weak document] delta in
                guard let document else { return 0 }
                let maxOrigin = max(document.bounds.height - clip.bounds.height, 0)
                var origin = clip.bounds.origin
                let before = origin.y
                origin.y = min(max(origin.y + delta, 0), maxOrigin)
                guard origin.y != before else { return 0 }
                clip.scroll(to: origin)
                scroll.reflectScrolledClipView(clip)
                return origin.y - before
            }
            return (viewport, scrollClosure)
        }
    }
}
