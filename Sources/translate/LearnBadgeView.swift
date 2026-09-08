import AppKit

/// Model representing parsed frequency, register, and CEFR level from "Mức dùng:" text.
struct LearnUsageInfo: Equatable, Sendable {
    var register: String?
    var frequency: String?
    var frequencyLevel: Int // 1 = low, 2 = medium, 3 = high
    var cefr: String?
    var cefrLevel: VocabDiscovery.Level

    var cefrColor: NSColor {
        switch cefrLevel {
        case .a1: return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
        case .a2: return NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1.0)
        case .b1: return NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1.0)
        case .b2: return NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1.0)
        case .c1: return NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
        case .c2: return NSColor(srgbRed: 1.00, green: 0.18, blue: 0.33, alpha: 1.0)
        case .unranked:
            return NSColor.secondaryLabelColor
        }
    }

    var frequencyColor: NSColor {
        switch frequencyLevel {
        case 3: return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
        case 2: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1.0)
        default: return NSColor(srgbRed: 0.92, green: 0.31, blue: 0.26, alpha: 1.0)
        }
    }

    static func parse(from text: String) -> LearnUsageInfo? {
        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Mức dùng:") else { continue }
            // While streaming, the final line may be half-written. Wait for the newline
            // that closes it so the badge does not flicker through partial values.
            guard index < lines.count - 1 else { return nil }
            return parseLine(line)
        }
        return nil
    }

    static func stripUsageLine(from text: String) -> String {
        var lines: [String] = []
        var foundUsage = false
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Mức dùng:") {
                foundUsage = true
                continue
            }
            lines.append(rawLine)
        }
        guard foundUsage else { return text }
        // Clean up any double blank lines created by removing the line
        var cleaned: [String] = []
        var lastWasBlank = false
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastWasBlank { continue }
            cleaned.append(line)
            lastWasBlank = isBlank
        }
        return cleaned.joined(separator: "\n")
    }

    static func parseLine(_ line: String) -> LearnUsageInfo {
        let content = line.dropFirst("Mức dùng:".count).trimmingCharacters(in: .whitespaces)
        let parts = content.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }

        var register: String?
        var frequency: String?
        var frequencyLevel: Int = 2
        var cefr: String?
        var parsedLevel: VocabDiscovery.Level = .unranked

        for part in parts {
            let lower = part.lowercased()
            let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            var foundLevel = false
            for word in words {
                if let lvl = VocabDiscovery.Level(rawValue: word), lvl != .unranked {
                    cefr = lvl.rawValue.uppercased()
                    parsedLevel = lvl
                    foundLevel = true
                    break
                }
            }
            if foundLevel { continue }

            if lower.contains("rất phổ biến") || lower.contains("very common") {
                frequency = "Rất phổ biến"
                frequencyLevel = 3
            } else if lower.contains("phổ biến") || lower.contains("common") {
                frequency = "Phổ biến"
                frequencyLevel = 2
            } else if lower.contains("ít gặp") || lower.contains("hiếm") || lower.contains("rare") {
                frequency = "Ít gặp"
                frequencyLevel = 1
            } else {
                if register == nil {
                    register = part
                } else if frequency == nil {
                    frequency = part
                }
            }
        }

        return LearnUsageInfo(
            register: register,
            frequency: frequency,
            frequencyLevel: frequencyLevel,
            cefr: cefr,
            cefrLevel: parsedLevel
        )
    }
}

/// Custom pill shape container that draws fill and border natively without layer timing issues.
final class BadgePillView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var strokeColor: NSColor = .clear { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 5 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        if strokeColor != .clear {
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// 3-bar vertical signal meter view.
final class FrequencySignalView: NSView {
    var activeBars: Int = 2 {
        didSet { if oldValue != activeBars { needsDisplay = true } }
    }
    var activeColor: NSColor = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 10, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let barWidth: CGFloat = 2.0
        let gap: CGFloat = 1.5
        let heights: [CGFloat] = [3.0, 6.0, 9.0]
        let inactiveColor = NSColor.labelColor.withAlphaComponent(0.2)

        for i in 0..<3 {
            let x = CGFloat(i) * (barWidth + gap)
            let h = heights[i]
            let y = bounds.minY + 0.5
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            let path = CGPath(roundedRect: rect, cornerWidth: 1.0, cornerHeight: 1.0, transform: nil)

            ctx.addPath(path)
            let isBarActive = (i + 1) <= activeBars
            let barColor = isBarActive ? activeColor : inactiveColor
            ctx.setFillColor(barColor.cgColor)
            ctx.fillPath()
        }
    }
}

/// Capsule pill row component for displaying word frequency, CEFR band, and register in Popover result header.
final class LearnBadgeView: NSView {
    private let stack = NSStackView()
    private let cefrPill = BadgePillView()
    private let cefrLabel = NSTextField(labelWithString: "")
    private let freqPill = BadgePillView()
    private let signalView = FrequencySignalView()
    private let freqLabel = NSTextField(labelWithString: "")
    private let registerPill = BadgePillView()
    private let registerLabel = NSTextField(labelWithString: "")

    /// Fixed pill height, shared with the popover layout code that positions this view.
    static let height: CGFloat = 18

    init() {
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setupCefrPill()
        setupFreqPill()
        setupRegisterPill()
    }

    private func setupCefrPill() {
        cefrPill.translatesAutoresizingMaskIntoConstraints = false
        cefrLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        cefrLabel.alignment = .center
        cefrLabel.translatesAutoresizingMaskIntoConstraints = false
        cefrPill.addSubview(cefrLabel)

        NSLayoutConstraint.activate([
            cefrLabel.leadingAnchor.constraint(equalTo: cefrPill.leadingAnchor, constant: 6),
            cefrLabel.trailingAnchor.constraint(equalTo: cefrPill.trailingAnchor, constant: -6),
            cefrLabel.topAnchor.constraint(equalTo: cefrPill.topAnchor, constant: 2),
            cefrLabel.bottomAnchor.constraint(equalTo: cefrPill.bottomAnchor, constant: -2),
            cefrPill.heightAnchor.constraint(equalToConstant: LearnBadgeView.height),
        ])
    }

    private func setupFreqPill() {
        freqPill.translatesAutoresizingMaskIntoConstraints = false
        freqLabel.font = .systemFont(ofSize: 10, weight: .medium)
        freqLabel.textColor = NSColor.labelColor

        let innerStack = NSStackView(views: [signalView, freqLabel])
        innerStack.orientation = .horizontal
        innerStack.spacing = 4
        innerStack.alignment = .centerY
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        freqPill.addSubview(innerStack)

        NSLayoutConstraint.activate([
            innerStack.leadingAnchor.constraint(equalTo: freqPill.leadingAnchor, constant: 5),
            innerStack.trailingAnchor.constraint(equalTo: freqPill.trailingAnchor, constant: -6),
            innerStack.centerYAnchor.constraint(equalTo: freqPill.centerYAnchor),
            freqPill.heightAnchor.constraint(equalToConstant: LearnBadgeView.height),
        ])
    }

    private func setupRegisterPill() {
        registerPill.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = NSFont.systemFont(ofSize: 10)
        registerLabel.font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        registerLabel.textColor = NSColor.secondaryLabelColor
        registerLabel.translatesAutoresizingMaskIntoConstraints = false
        registerPill.addSubview(registerLabel)

        NSLayoutConstraint.activate([
            registerLabel.leadingAnchor.constraint(equalTo: registerPill.leadingAnchor, constant: 5),
            registerLabel.trailingAnchor.constraint(equalTo: registerPill.trailingAnchor, constant: -5),
            registerLabel.topAnchor.constraint(equalTo: registerPill.topAnchor, constant: 2),
            registerLabel.bottomAnchor.constraint(equalTo: registerPill.bottomAnchor, constant: -2),
            registerPill.heightAnchor.constraint(equalToConstant: LearnBadgeView.height),
        ])
    }

    func update(with usage: LearnUsageInfo?) {
        guard let usage else {
            isHidden = true
            return
        }

        // 1. CEFR Level Pill
        if let cefr = usage.cefr, !cefr.isEmpty {
            cefrLabel.stringValue = cefr
            let color = usage.cefrColor
            cefrLabel.textColor = color
            cefrPill.strokeColor = color.withAlphaComponent(0.35)
            cefrPill.fillColor = color.withAlphaComponent(0.12)
            if cefrPill.superview == nil { stack.addArrangedSubview(cefrPill) }
            cefrPill.isHidden = false
        } else {
            cefrPill.isHidden = true
        }

        // 2. Frequency Signal Pill
        if let freq = usage.frequency, !freq.isEmpty {
            freqLabel.stringValue = freq
            signalView.activeBars = usage.frequencyLevel
            signalView.activeColor = usage.frequencyColor
            freqPill.strokeColor = NSColor.labelColor.withAlphaComponent(0.12)
            freqPill.fillColor = NSColor.labelColor.withAlphaComponent(0.05)
            if freqPill.superview == nil { stack.addArrangedSubview(freqPill) }
            freqPill.isHidden = false
        } else {
            freqPill.isHidden = true
        }

        // 3. Register Pill
        if let reg = usage.register, !reg.isEmpty {
            registerLabel.stringValue = reg
            registerPill.strokeColor = NSColor.labelColor.withAlphaComponent(0.1)
            registerPill.fillColor = .clear
            if registerPill.superview == nil { stack.addArrangedSubview(registerPill) }
            registerPill.isHidden = false
        } else {
            registerPill.isHidden = true
        }

        isHidden = false
        needsLayout = true
    }

    func clear() {
        isHidden = true
    }

    /// Pulls the "Mức dùng:" line out of `text` into the badge and returns the text without it.
    /// `live` is false for placeholder/error strings, which never carry a usage line.
    func apply(to text: String, live: Bool) -> String {
        guard live, let usage = LearnUsageInfo.parse(from: text) else {
            clear()
            return text
        }
        update(with: usage)
        return LearnUsageInfo.stripUsageLine(from: text)
    }
}
