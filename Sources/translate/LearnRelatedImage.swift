import AppKit
import Foundation

/// Related-image lookup for the Learn source pane. One DuckDuckGo fetch: the
/// Images-button rewrite when it returns, otherwise the headword. Fetching the
/// headword first and then replacing it flashes a second pair of tiles.
enum LearnRelatedImage {
    static let thumbnailCount = 2
    static let thumbnailCornerRadius: CGFloat = 12
    static let thumbnailSpacing: CGFloat = 6
    static let thumbnailInset: CGFloat = 4
    static let thumbnailTextGap: CGFloat = 8

    static func thumbnailSide(paneWidth: CGFloat) -> CGFloat {
        max(1, paneWidth - thumbnailInset * 2)
    }

    struct ThumbnailLayout {
        let strip: NSRect
        let items: [NSRect]

        var occupiedHeight: CGFloat {
            LearnRelatedImage.thumbnailInset + strip.height + LearnRelatedImage.thumbnailTextGap
        }
    }

    static func searchTerm(from card: LearnCard) -> String {
        card.headword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchQuery(for term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayQuery(from result: Result<String, Error>, fallback: String) -> String {
        let fallback = searchQuery(for: fallback)
        switch result {
        case let .success(query):
            let trimmed = searchQuery(for: query)
            return trimmed.isEmpty ? fallback : trimmed
        case .failure:
            return fallback
        }
    }

    /// Same source string the Images button sends to `imageSearchQuery`, so the rewrite
    /// prompt sees the selection, not only the parsed headword.
    static func rewriteSource(term: String, sourceText: String) -> String {
        let source = searchQuery(for: sourceText)
        return source.isEmpty ? searchQuery(for: term) : source
    }

    static func needsRefetch(seed: String, resolved: String) -> Bool {
        LearnCard.normalizeAnswer(seed) != LearnCard.normalizeAnswer(resolved)
    }

    /// Query for the single DuckDuckGo thumbnail fetch. `rewrite == nil` means
    /// the model has not answered yet: wait if a rewriter is bound.
    static func thumbnailQuery(seed: String, hasRewriter: Bool, rewrite: Result<String, Error>?) -> String? {
        let seed = searchQuery(for: seed)
        guard !seed.isEmpty else { return nil }
        if !hasRewriter { return seed }
        guard let rewrite else { return nil }
        return displayQuery(from: rewrite, fallback: seed)
    }

    /// DuckDuckGo landing page used only to scrape the `vqd` token.
    static func tokenPageURL(for query: String) -> URL? {
        let trimmed = searchQuery(for: query)
        guard !trimmed.isEmpty else { return nil }
        var parts = URLComponents(string: "https://duckduckgo.com/")
        parts?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "iax", value: "images"),
            URLQueryItem(name: "ia", value: "images"),
        ]
        return parts?.url
    }

    static func pageURL(for query: String) -> URL? {
        let trimmed = searchQuery(for: query)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "q", value: trimmed),
        ]
        return components.url
    }

    static func imageListURL(query: String, vqd: String) -> URL? {
        guard !query.isEmpty, !vqd.isEmpty else { return nil }
        var parts = URLComponents(string: "https://duckduckgo.com/i.js")
        parts?.queryItems = [
            URLQueryItem(name: "l", value: "us-en"),
            URLQueryItem(name: "o", value: "json"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "vqd", value: vqd),
            URLQueryItem(name: "f", value: ",,,"),
            URLQueryItem(name: "p", value: "1"),
        ]
        return parts?.url
    }

    static func vqdToken(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "vqd=")
        else { return nil }
        var rest = html[start.upperBound...]
        if let first = rest.first, first == "'" || first == "\"" || first == "\u{2018}" || first == "\u{2019}" {
            rest = rest.dropFirst()
        }
        let token = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
        return token.count >= 8 ? String(token) : nil
    }

    static func imageURLs(from data: Data, limit: Int = thumbnailCount) -> [URL] {
        guard limit > 0, let payload = try? JSONDecoder().decode(ImageSearch.self, from: data) else { return [] }
        var urls: [URL] = []
        var seen = Set<String>()
        for hit in payload.results ?? [] {
            guard let source = hit.thumbnail ?? hit.image, let url = URL(string: source) else { continue }
            if seen.insert(source).inserted {
                urls.append(url)
                if urls.count == limit { break }
            }
        }
        return urls
    }

    static func firstImageURL(from data: Data) -> URL? {
        imageURLs(from: data, limit: 1).first
    }

    static func fetchImageData(from urls: [URL], completion: @escaping @Sendable ([Data]) -> Void) {
        fetchImageData(urls, acc: [], completion: completion)
    }

    private static func fetchImageData(_ urls: [URL], acc: [Data], completion: @escaping @Sendable ([Data]) -> Void) {
        guard let url = urls.first else {
            completion(acc)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var next = acc
            if let data, !data.isEmpty { next.append(data) }
            fetchImageData(Array(urls.dropFirst()), acc: next, completion: completion)
        }.resume()
    }

    static func fittedSize(of image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        let maxWidth = max(1, maxWidth)
        let maxHeight = max(1, maxHeight)
        let src = image.size
        guard src.width > 0, src.height > 0 else { return NSSize(width: maxWidth, height: maxHeight) }
        let scale = min(maxWidth / src.width, maxHeight / src.height)
        return NSSize(width: max(1, src.width * scale), height: max(1, src.height * scale))
    }

    static func thumbnailLayout(paneWidth: CGFloat, images: [NSImage] = []) -> ThumbnailLayout {
        let inset = thumbnailInset
        let gap = thumbnailSpacing
        let side = thumbnailSide(paneWidth: paneWidth)
        let sizes: [NSSize] = (0..<thumbnailCount).map { index in
            if index < images.count {
                return fittedSize(of: images[index], maxWidth: side, maxHeight: side)
            }
            return NSSize(width: side, height: side)
        }
        let stripHeight = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, sizes.count - 1))
        let strip = NSRect(x: inset, y: inset, width: side, height: stripHeight)
        // Non-flipped strip: y=0 is the bottom. First hit sits above the second, under the source text.
        var y = stripHeight
        let items = sizes.map { size -> NSRect in
            y -= size.height
            let frame = NSRect(x: (side - size.width) / 2, y: y, width: size.width, height: size.height)
            y -= gap
            return frame
        }
        return ThumbnailLayout(strip: strip, items: items)
    }

    /// Fits the whole photo (no crop) and clips that photo to `radius`.
    static func fittedThumbnail(_ image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat, radius: CGFloat, scale: CGFloat = 2) -> NSImage {
        let size = fittedSize(of: image, maxWidth: maxWidth, maxHeight: maxHeight)
        let scale = max(1, scale)
        let pixelsW = max(1, Int((size.width * scale).rounded()))
        let pixelsH = max(1, Int((size.height * scale).rounded()))
        let radius = min(radius, size.width / 2, size.height / 2)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let clip = NSRect(origin: .zero, size: size)
        NSBezierPath(roundedRect: clip, xRadius: radius, yRadius: radius).addClip()
        image.draw(in: clip, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let output = NSImage(size: size)
        output.addRepresentation(rep)
        return output
    }

    private struct ImageSearch: Decodable {
        let results: [Hit]?

        struct Hit: Decodable {
            let image: String?
            let thumbnail: String?
        }
    }
}

/// Two full-photo thumbnails under the Learn source text. Shared by the main pane and subtranslate.
@MainActor
final class LearnRelatedImageStrip: NSView {
    var onOpen: (() -> Void)?
    var onImagesChanged: (() -> Void)?
    /// Starts the Images-button rewrite. Return a cancel function so a newer refresh can stop it.
    var onResolveQuery: ((String, @escaping @Sendable (Result<String, Error>) -> Void) -> (() -> Void)?)?

    private let buttons: [NSButton]
    private var loadedImages: [NSImage] = []
    private var term = ""
    private var resolvedQuery = ""
    private var seedQuery = ""
    private var generation = 0
    private var fetchGeneration = 0
    private var task: URLSessionDataTask?
    private var rewriteCancel: (() -> Void)?

    var hasImages: Bool { !loadedImages.isEmpty }
    var pageURL: URL? { LearnRelatedImage.pageURL(for: resolvedQuery.isEmpty ? term : resolvedQuery) }

    override init(frame frameRect: NSRect) {
        buttons = (0..<LearnRelatedImage.thumbnailCount).map { _ in NSButton(title: "", target: nil, action: nil) }
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        for button in buttons {
            button.target = self
            button.action = #selector(openPage)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleAxesIndependently
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.isHidden = true
            button.toolTip = "Open related images"
            button.setAccessibilityLabel("Related image")
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        task?.cancel()
    }

    func refresh(term: String, rewriteSource: String? = nil) {
        let key = LearnCard.normalizeAnswer(term)
        guard !key.isEmpty else {
            clear()
            return
        }
        if key == self.term { return }
        generation += 1
        fetchGeneration += 1
        let token = generation
        self.term = key
        seedQuery = LearnRelatedImage.searchQuery(for: term)
        resolvedQuery = seedQuery
        task?.cancel()
        rewriteCancel?()
        apply(images: [])
        let rewrite = LearnRelatedImage.rewriteSource(term: seedQuery, sourceText: rewriteSource ?? "")
        if let query = LearnRelatedImage.thumbnailQuery(seed: seedQuery, hasRewriter: onResolveQuery != nil, rewrite: nil) {
            fetchImages(query: query, token: token)
        }
        startRewrite(source: rewrite, token: token)
    }

    func clear() {
        generation += 1
        fetchGeneration += 1
        task?.cancel()
        task = nil
        rewriteCancel?()
        rewriteCancel = nil
        term = ""
        seedQuery = ""
        resolvedQuery = ""
        apply(images: [])
    }

    private func startRewrite(source: String, token: Int) {
        guard let onResolveQuery else { return }
        rewriteCancel = onResolveQuery(source) { [weak self] result in
            Task { @MainActor in
                self?.applyRewrite(result, token: token)
            }
        }
    }

    private func applyRewrite(_ result: Result<String, Error>, token: Int) {
        guard token == generation else { return }
        rewriteCancel = nil
        guard let query = LearnRelatedImage.thumbnailQuery(seed: seedQuery, hasRewriter: true, rewrite: result) else { return }
        fetchImages(query: query, token: token)
    }

    private func fetchImages(query: String, token: Int) {
        guard token == generation else { return }
        fetchGeneration += 1
        let fetchToken = fetchGeneration
        let queryForList = LearnRelatedImage.searchQuery(for: query)
        resolvedQuery = queryForList.isEmpty ? seedQuery : queryForList
        guard let tokenURL = LearnRelatedImage.tokenPageURL(for: queryForList) else { return }
        task?.cancel()
        var request = URLRequest(url: tokenURL)
        request.timeoutInterval = 8
        request.setValue("NTranslate/1.4 (macOS; local.ninh.ntranslate)", forHTTPHeaderField: "User-Agent")
        let pageTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let vqd = LearnRelatedImage.vqdToken(from: data),
                  let listURL = LearnRelatedImage.imageListURL(query: queryForList, vqd: vqd)
            else { return }
            var listRequest = URLRequest(url: listURL)
            listRequest.timeoutInterval = 8
            listRequest.setValue("NTranslate/1.4 (macOS; local.ninh.ntranslate)", forHTTPHeaderField: "User-Agent")
            listRequest.setValue("https://duckduckgo.com/", forHTTPHeaderField: "Referer")
            URLSession.shared.dataTask(with: listRequest) { data, _, _ in
                guard let data else { return }
                let urls = LearnRelatedImage.imageURLs(from: data)
                guard !urls.isEmpty else { return }
                LearnRelatedImage.fetchImageData(from: urls) { [weak self] payloads in
                    let images = payloads
                    Task { @MainActor in
                        guard let self, token == self.generation, fetchToken == self.fetchGeneration else { return }
                        self.apply(images: images.compactMap { NSImage(data: $0) })
                        self.onImagesChanged?()
                    }
                }
            }.resume()
        }
        task = pageTask
        pageTask.resume()
    }

    func layoutInSourcePane(paneWidth: CGFloat, bodyHeight: CGFloat, scrollView: NSScrollView, textView: NSTextView) {
        let show = hasImages
        isHidden = !show
        guard show else { return }
        let layout = LearnRelatedImage.thumbnailLayout(paneWidth: paneWidth, images: loadedImages)
        frame = layout.strip
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for (index, (button, item)) in zip(buttons, layout.items).enumerated() {
            button.frame = item
            if index < loadedImages.count {
                button.image = LearnRelatedImage.fittedThumbnail(
                    loadedImages[index],
                    maxWidth: item.width,
                    maxHeight: item.height,
                    radius: LearnRelatedImage.thumbnailCornerRadius,
                    scale: scale
                )
                button.isHidden = false
            }
        }
        let textH = max(48, bodyHeight - layout.occupiedHeight)
        scrollView.frame = NSRect(x: 0, y: layout.occupiedHeight, width: paneWidth, height: textH)
        textView.minSize = NSSize(width: 0, height: textH)
        if let card = superview, card.subviews.last !== self {
            card.addSubview(self, positioned: .above, relativeTo: nil)
        }
    }

    private func apply(images: [NSImage]) {
        loadedImages = images
        for (index, button) in buttons.enumerated() {
            button.image = nil
            button.isHidden = index >= images.count
        }
        isHidden = !hasImages
    }

    @objc private func openPage() {
        onOpen?()
    }
}
