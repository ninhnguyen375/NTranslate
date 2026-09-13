// Chụp LearnStructuredCardView ra PNG để soi bằng mắt, không qua test target.
//
//   swiftc -parse-as-library Sources/translate/LearnCard.swift \
//     Sources/translate/TextZoom.swift \
//     Sources/translate/VocabPack.swift \
//     Sources/translate/WeaveCache.swift \
//     Sources/translate/VocabDiscovery.swift \
//     Sources/translate/LearnBadgeView.swift \
//     Sources/translate/LearnStructuredCardView.swift \
//     Scripts/learn-card-snapshot.swift -o /tmp/learn-card-snapshot \
//     && /tmp/learn-card-snapshot
import AppKit

/// Bề rộng pane kết quả Learn (pane chính và khung phụ cùng công thức):
/// AppConfig.default.ui.width 720, density compact (padding 10), divider 1,
/// tỉ lệ Learn 0.3/0.7. usable = 720 - 20 - 1 = 699;
/// phải = 699 - floor(699 * 0.3) = 490. `subSectionPanes` dùng cùng ratio khi mode == .learn.
private let resultPaneWidth: CGFloat = 490
private let subResultPaneWidth: CGFloat = 490

private let fullCardText = """
Từ gốc: resilient
Phiên âm: /rɪˈzɪliənt/
Mức dùng: neutral · phổ biến · CEFR B2
adj. kiên cường, bật lại nhanh sau khó khăn
adj. (vật liệu) đàn hồi, trở lại hình dạng cũ

Ví dụ
- [dễ] She is a very resilient child.
  → Cô bé đó rất kiên cường.
- [trung] The economy proved more resilient than analysts expected.
  → Nền kinh tế tỏ ra vững hơn dự đoán của giới phân tích.
- [khó] A resilient supply chain absorbs shocks without passing them on to customers.
  → Chuỗi cung ứng có sức chống chịu sẽ hấp thụ cú sốc mà không đẩy sang khách hàng.

Dễ nhầm với
- resistant: chống lại, không cho tác động xảy ra
  → The fabric is resistant to water.

Họ từ
- resilience: n. khả năng phục hồi
- resiliently: adv. một cách kiên cường
- resile: v. bật lại

Đi kèm thường gặp
- resilient economy: nền kinh tế có sức chống chịu
- emotionally resilient: vững vàng về cảm xúc
- build resilience: gây dựng sức bật

Nhớ nhanh
- gốc re + salire: nhảy lại, bật lên sau khi bị nén.

Tự kiểm tra
- Small businesses had to be ___ to survive the downturn.
  → Đáp án: resilient
"""

private let minCardText = """
Từ gốc: resilient
Phiên âm: /rɪˈzɪliənt/
adj. kiên cường, bật lại nhanh sau khó khăn
"""

@main
@MainActor
enum LearnCardSnapshot {
    static var lightCornerRGB: (CGFloat, CGFloat, CGFloat)?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".cursor-runs")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let full = LearnCard.parse(fullCardText)
        let mini = LearnCard.parse(minCardText)
        precondition(!full.headword.isEmpty, "full card must parse a headword")
        precondition(!mini.headword.isEmpty, "min card must parse a headword")

        var rows: [String] = []
        print("height table: width card first afterWindow delta")
        for width in [CGFloat(240), 299, 301, 490, 640] {
            let suffix = width == 490 ? " (main+sub)" : ""
            rows.append(probeHeight(card: full, raw: fullCardText, width: width, label: "full\(suffix)"))
            rows.append(probeHeight(card: mini, raw: minCardText, width: width, label: "min\(suffix)"))
        }
        print("height table done")

        snapshot(
            card: full,
            appearance: .aqua,
            revealTranslations: true,
            url: root.appendingPathComponent("snap-light-full.png"),
            label: "light-full"
        )
        snapshot(
            card: full,
            appearance: .darkAqua,
            revealTranslations: true,
            url: root.appendingPathComponent("snap-dark-full.png"),
            label: "dark-full"
        )
        snapshot(
            card: mini,
            raw: minCardText,
            appearance: .aqua,
            revealTranslations: false,
            url: root.appendingPathComponent("snap-light-min.png"),
            label: "light-min"
        )
        snapshot(
            card: full,
            appearance: .aqua,
            revealTranslations: false,
            url: root.appendingPathComponent("snap-light-hidden.png"),
            label: "light-hidden"
        )
        snapshot(
            card: full,
            raw: fullCardText,
            appearance: .aqua,
            revealTranslations: true,
            width: subResultPaneWidth,
            url: root.appendingPathComponent("snap-light-sub.png"),
            label: "light-sub"
        )
        snapshot(
            card: full,
            raw: fullCardText,
            appearance: .darkAqua,
            revealTranslations: true,
            width: subResultPaneWidth,
            url: root.appendingPathComponent("snap-dark-sub.png"),
            label: "dark-sub"
        )
        print("wrote snapshots to \(root.path)")
    }

    /// So sánh preferredHeight trước/sau khi vào window với chiều cao stack thật sau layout.
    @discardableResult
    static func probeHeight(card: LearnCard, raw: String, width: CGFloat, label: String) -> String {
        let view = LearnStructuredCardView()
        view.onSpeak = {}
        view.applyUsage(from: raw, live: true)
        view.display(card)
        let first = view.preferredHeight(fittingWidth: width)
        view.frame = NSRect(x: 0, y: 0, width: width, height: first)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: max(first, 120)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let afterWindow = view.preferredHeight(fittingWidth: width)
        let actual = actualContentHeight(of: view)
        let delta = afterWindow - first
        let line = String(
            format: "probe %@: width=%.0f first=%.1f afterWindow=%.1f actual=%.1f dWin=%.1f dActual=%.1f",
            label,
            width,
            first,
            afterWindow,
            actual,
            delta,
            actual - first
        )
        print(line)
        window.orderOut(nil)
        window.contentView = nil
        return line
    }

    static func actualContentHeight(of view: LearnStructuredCardView) -> CGFloat {
        guard let stack = view.subviews.first else { return -1 }
        stack.layoutSubtreeIfNeeded()
        return ceil(stack.fittingSize.height + 14 + 16)
    }

    static func snapshot(
        card: LearnCard,
        raw: String = fullCardText,
        appearance: NSAppearance.Name,
        revealTranslations: Bool,
        width: CGFloat = resultPaneWidth,
        url: URL,
        label: String
    ) {
        guard let named = NSAppearance(named: appearance) else {
            fatalError("\(label): missing appearance \(appearance.rawValue)")
        }
        NSApp.appearance = named

        let view = LearnStructuredCardView()
        view.appearance = named
        view.onSpeak = {}
        view.applyUsage(from: raw, live: true)
        view.display(card)
        view.wantsLayer = true

        let firstMeasure = view.preferredHeight(fittingWidth: width)
        view.frame = NSRect(x: 0, y: 0, width: width, height: firstMeasure)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: firstMeasure))
        host.appearance = named
        host.wantsLayer = true
        named.performAsCurrentDrawingAppearance {
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        host.addSubview(view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: max(firstMeasure, 120)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = named
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFront(nil)
        named.performAsCurrentDrawingAppearance {
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        let afterWindow = view.preferredHeight(fittingWidth: width)

        if revealTranslations {
            revealVeils(in: view, window: window)
        }

        let finalMeasure = view.preferredHeight(fittingWidth: width)
        view.frame = NSRect(x: 0, y: 0, width: width, height: finalMeasure)
        host.frame = view.frame
        named.performAsCurrentDrawingAppearance {
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        window.setContentSize(NSSize(width: width, height: finalMeasure))
        named.performAsCurrentDrawingAppearance {
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        print(String(
            format: "%@: paneWidth=%.0f first=%.1f afterWindow=%.1f final=%.1f delta=%.1f",
            label,
            width,
            firstMeasure,
            afterWindow,
            finalMeasure,
            afterWindow - firstMeasure
        ))

        let bounds = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("\(label): bitmapImageRepForCachingDisplay failed")
        }
        named.performAsCurrentDrawingAppearance {
            host.appearance = named
            view.appearance = named
            host.cacheDisplay(in: bounds, to: rep)
        }
        guard let rgb = sampleRGB(rep) else {
            fatalError("\(label): could not sample a corner pixel")
        }
        if appearance == .aqua {
            lightCornerRGB = rgb
        } else if appearance == .darkAqua {
            if let light = lightCornerRGB, similarRGB(light, rgb) {
                print("\(label): dark appearance did not take (light \(fmt(light)) vs dark \(fmt(rgb))); not writing a fake dark snapshot")
                window.orderOut(nil)
                window.contentView = nil
                return
            }
        }

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("\(label): PNG encode failed")
        }
        do {
            try data.write(to: url)
        } catch {
            fatalError("\(label): write \(url.path): \(error)")
        }
        print("\(label): wrote \(url.lastPathComponent) cornerRGB=\(fmt(rgb))")
        window.orderOut(nil)
        window.contentView = nil
    }

    static func sampleRGB(_ rep: NSBitmapImageRep) -> (CGFloat, CGFloat, CGFloat)? {
        let x = min(8, max(0, rep.pixelsWide - 1))
        let y = min(8, max(0, rep.pixelsHigh - 1))
        guard let color = rep.colorAt(x: x, y: y),
              let rgb = color.usingColorSpace(.deviceRGB)
        else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    static func similarRGB(
        _ a: (CGFloat, CGFloat, CGFloat),
        _ b: (CGFloat, CGFloat, CGFloat)
    ) -> Bool {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) < 0.24
    }

    static func fmt(_ rgb: (CGFloat, CGFloat, CGFloat)) -> String {
        String(format: "(%.2f %.2f %.2f)", rgb.0, rgb.1, rgb.2)
    }

    /// Bấm vào lớp che bản dịch (màu chữ trong) để mở hết ví dụ.
    static func revealVeils(in root: NSView, window: NSWindow) {
        var fields: [NSTextField] = []
        collectTextFields(in: root, into: &fields)
        for field in fields {
            guard field.textColor == .clear, !field.stringValue.isEmpty, let row = field.superview else { continue }
            let rect = row.convert(field.bounds, from: field)
            let local = NSPoint(x: rect.midX, y: rect.midY)
            let windowPoint = row.convert(local, to: nil)
            guard let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else { continue }
            row.mouseDown(with: event)
        }
    }

    static func collectTextFields(in view: NSView, into fields: inout [NSTextField]) {
        if let field = view as? NSTextField { fields.append(field) }
        for child in view.subviews { collectTextFields(in: child, into: &fields) }
    }
}
