// Self-check for PhoneStudyPage dialogue topic/tier filtering and pull-to-refresh wiring.
import Foundation

@MainActor
func run() {
    let html = PhoneStudyPage.html
    assert(html.contains(#"id="ptr""#), "missing pull-to-refresh indicator")
    assert(html.contains("Release to refresh"), "missing pull-to-refresh release prompt")
    assert(html.contains("cache.clear()"), "pull-to-refresh must clear client cache")
    assert(html.contains("dialogueGroup") && html.contains("dialogueTier"), "missing topic or tier storage keys")
    assert(html.contains(#"id="group""#) && html.contains(#"id="tier""#), "missing topic or tier filter pill bars")
    assert(html.contains("All Topics") && html.contains("All Tiers"), "missing All Topics / All Tiers labels")
    assert(!html.contains("\u{2014}") && !html.contains("\u{2013}"), "must not contain em/en dashes")
    print("phone-study-page-check: ok")
}

@main
enum PhoneStudyPageCheck {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
