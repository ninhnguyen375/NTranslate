// Installs the Claude Code skill that turns a project into importable dialogue lessons.
import AppKit

enum ExtractDialogSkill {
    static let name = "extract-ntranslate-dialog"

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(name)/SKILL.md")
    }

    /// Overwrites any older copy so users always get the prompt that matches this app's import format.
    static func install() throws {
        let url = fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // ponytail: embedded copy of ~/.claude/skills/extract-ntranslate-dialog/SKILL.md; edit both together.
    static let content = #"""
---
name: extract-ntranslate-dialog
description: Generate English-learning dialogue lessons (developer A vs coding agent B) from the real context of the current project, output as an NTranslate-compatible JSON file in ./worker/. Use when the user asks to "extract dialog", "tạo bài hội thoại tiếng Anh từ project", "generate English lessons for NTranslate", or invokes /extract-ntranslate-dialog.
---

# Task: Generate English-learning dialogue lessons from THIS project

I learn English to work with coding agents. Create a JSON file of dialogue lessons based on the real context of this project, so I learn the exact prompts and agent replies I will use here.

## Step 1: Study the project (read only, do not change any code)
- Read README, CLAUDE.md (if any), package.json / pyproject / equivalent.
- Scan the folder structure, main pages/screens, API routes, database schema, tests, CI config.
- Read the last ~30 git commits (`git log --oneline -30`) to see real recent work.
- Open the UI code and list every screen, window, menu, tab, button label and hotkey the user sees, in on-screen order.
- List: key features, user journeys (start to finish), business rules (limits, states, who/when/what happens), screen layout, known pain points. Tech stack only as background.

## Step 2: Plan the lessons
- Create 40-50 lessons, split into 3 groups:
  - `Tier 1 - Core prompts` (~15): short, single-intent prompts (add, change, move, remove, fix, explain, run, commit...).
  - `Tier 2 - Full prompts` (~20): prompts with context + requirements + constraints; realistic agent replies ("Here's what changed", "heads-up", "side effect", "I'd recommend").
  - `Tier 3 - Multi-turn` (~15): agent misunderstands → I correct; fix fails → retry; agent blocked; review diff; wrap up session.
- Focus on business and process, not code. About 70% of lessons describe what the user does and sees: end-to-end user journeys, business rules, screen layout (which area sits where, button order, what opens what). About 30% cover controlling the agent (correcting, reviewing results, shipping), still phrased as user behavior ('when the user clicks X, Y should happen'), not file edits.
- Every lesson MUST use real names from this project: screen titles, menu items, button labels, hotkeys, feature names, data the user saves. Mention file or function names only when the lesson really needs them. No generic examples.
- Across all lessons, cover every major user journey and every main screen at least once, so the set doubles as a spoken description of how the product works and how its UI is arranged.
- Teach phrases for describing process and layout: 'sits next to', 'right below', 'opens in a separate window', 'end-to-end flow', 'once per session', 'falls back to', 'only when'.
- Show me the lesson list (title + scenario + group) and wait for my OK before writing.

## Step 3: Write lessons
Rules for each lesson:
- Dialogue between A (me, developer) and B (coding agent).
- 15-20 English lines total (A + B combined), short sentences, active voice, natural spoken English.
- Then the Vietnamese translation, line by line, same order and same count.
- Last line: `Prompt pattern: ...` (a reusable prompt template from the lesson).
- `words`: 3 useful phrases/collocations from the dialogue (e.g. "fall back to", "out of scope"), not basic single words. Repeat key phrases across lessons for spaced review.
- No double quotes inside dialogue text; use single quotes.

## Step 4: Output format
JSON array. Each item exactly like this:

```json
{
  "words": ["phrase 1", "phrase 2", "phrase 3"],
  "text": "Topic: <Topic>\n\nA: ...\nB: ...\n...\n\nA: <VI>...\nB: <VI>...\n...\n\nPrompt pattern: <pattern>",
  "promptVersion": "7",
  "generatedAt": 812800000,
  "title": "<short title>",
  "scenario": "<Project setup | Building UI | Building features | Backend and data | Debugging | Code quality | Testing | Shipping | Controlling the agent | Planning | Reviewing results | Understanding code | Running the app>",
  "group": "<Tier 1 - Core prompts | Tier 2 - Full prompts | Tier 3 - Multi-turn>",
  "count": 0
}
```

- `generatedAt`: start at 812800000, +1000 per lesson.
- `count`: always 0.

## Step 5: Build, validate and install into NTranslate
- Write lessons as source data in `./worker/lessons-src/` (one JSON per tier, fields: title, scenario, words, topic, pattern, en[], vi[]).
- Write a script `./worker/build_lessons.py` that builds the final file and checks: valid JSON, en/vi line counts equal, 15-20 lines per lesson, all required fields present.
- Output: `./worker/<project-name>-english-lessons.json`.
- Then the same script installs every lesson straight into NTranslate's saved passages, so the user does not need to import by hand:
  - Read `historyDirectory` from `~/Library/Application Support/NTranslate/config.json`. Expand `~`. If missing or empty, use `~/Library/Application Support/NTranslate`.
  - Target folder: `<historyDirectory>/weave/` (create it if missing).
  - File name per lesson: `<sha256 hex of the lesson's text field, UTF-8>.json`. This matches the app's own Import, so running twice never duplicates.
  - File content: the lesson object (words, text, promptVersion, generatedAt, title, scenario, group, count). Write compact JSON, UTF-8.
  - If the file already exists, keep its `count` and `isDone` values instead of overwriting them with defaults, so learner progress survives a rerun.
  - Print the target folder and how many files were written new vs updated.
- Do not modify any project source code. Only create files inside `./worker/` and inside the NTranslate `weave` folder.

## Step 6: Report
Briefly summarize: number of lessons per group, which project features were covered, any area you skipped, and the folder the lessons were installed to. Tell the user to open (or reopen) Saved Passages in NTranslate to see them; no restart is needed.
"""#
}
