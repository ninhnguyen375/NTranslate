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
description: Generate English-learning dialogue lessons between the user (BA or project consultant) and a customer about the current project's business requirements, workflows, rules, and acceptance criteria, output as an NTranslate-compatible JSON file in ./worker/. Use when the user asks to "extract dialog", "tạo bài hội thoại tiếng Anh từ project", "generate English lessons for NTranslate", or invokes /extract-ntranslate-dialog.
---

# Task: Generate English-learning dialogue lessons from THIS project

I learn English to discuss this project's business with customers. Create a JSON file of dialogue lessons between me (BA or project consultant) and a customer, so I can discover needs, clarify workflows and business rules, explain proposals, resolve misunderstandings, and confirm acceptance criteria. This is customer-facing business conversation, not instructions to a coding agent.

## Step 1: Study the project (read only, do not change any code)
- Read README, CLAUDE.md (if any), package.json / pyproject / equivalent.
- Scan the folder structure, main pages/screens, API routes, database schema, tests, CI config.
- Read the last ~30 git commits (`git log --oneline -30`) to see real recent work.
- Open the UI code and list every screen, window, menu, tab, button label and hotkey the user sees, in on-screen order.
- Prioritize available business documents, requirements, meeting notes, and customer terminology. Use code as evidence of current behavior, not proof of customer agreement.
- List: business goals, stakeholder roles, current and proposed workflows, key features, user journeys (start to finish), business rules (limits, states, permissions, approvals, exceptions), screen layout, known pain points, and acceptance criteria. Tech stack only as background.
- Distinguish verified project facts from proposed requirements and open questions. Frame missing rules as questions or explicitly hypothetical customer answers; do not invent commitments, policies, or confirmed customer decisions.

## Step 2: Plan the lessons
- Choose one shared topic for the whole extraction, using the project/product name by default (for example, `NTranslate`). Reuse its exact existing spelling in saved passages. Only ask if the project name is ambiguous.
- Set every lesson's `group` to that shared topic, including later extraction batches for the same project. Do not use tier labels or lesson-specific topics as groups.
- Create 40-50 lessons, split into 3 tiers:
  - `Tier 1 - Core prompts` (~15): short business exchanges with one intent: ask who performs a task, clarify a status, confirm a deadline, explain a screen, or check an exception. Keep this tier label for compatibility; 'prompts' means conversation starters, not agent commands.
  - `Tier 2 - Full prompts` (~20): customer discussions with context, business needs, constraints, and follow-up questions: discover the current process, explain a proposed flow, clarify permissions and approvals, compare options, and define acceptance criteria.
  - `Tier 3 - Multi-turn` (~15): resolve a misunderstood requirement, uncover an exception, negotiate scope or a change request, walk through UAT feedback, distinguish a defect from a new request, and recap decisions and open questions.
- Focus entirely on business conversations between me and the customer. About 70% of lessons cover business goals, daily work, end-to-end processes, roles, rules, data, exceptions, and relevant UI behavior. About 30% cover customer collaboration: clarification, recommendations and tradeoffs, scope, priorities, acceptance, UAT, and meeting wrap-up. Do not include coding-agent control, code review, shell commands, commits, or implementation chatter.
- Make both speakers active: I ask, probe, explain, recommend, and confirm; the customer describes needs, answers, challenges assumptions, and clarifies priorities. Avoid turning every lesson into a product demo or a list of questions.
- Every lesson MUST cover real concepts from this project: screens, workflows, statuses, roles, fields, rules, and exceptions. Mention file or function names only when the lesson really needs them. No generic examples.
- Across all lessons, cover every major user journey and every main screen at least once, so the set doubles as a spoken description of how the product works and how its UI is arranged.
- Teach phrases for customer discussions: 'walk me through', 'who is responsible for', 'what happens if', 'only when', 'subject to approval', 'as we agreed', 'within scope', 'acceptance criteria', and 'let me confirm my understanding'. Include layout phrases such as 'right below' and 'sits next to' when discussing an actual screen.
- Show the shared topic and lesson list (title + scenario + tier) and wait for my OK before writing.

## Step 3: Write lessons & self-review per tier

### Hard quality & anti-cheating rules (learned from real failures)
1. **NEVER write a Python/JS script to generate or pad dialogues (`prepare_lessons.py`, `FOLLOWUPS`, string templates)**:
   - A common failure mode is writing 4 real lines per lesson and appending a 12-line boilerplate tail (`Let me confirm my understanding of {screen}...`, `Are we describing the current process or the proposed design?`, `Agreed. Let us move to the next workflow step.`) to hit the 15-20 line requirement. **This is strictly forbidden.**
   - Author the JSON files in `./worker/lessons-src/tier-1.json`, `tier-2.json`, and `tier-3.json` directly by hand. Every single line from line 1 to line 15-20 must discuss concrete domain logic, screen behavior, edge cases, numbers, or state transitions of that specific topic.
2. **Zero language mixing (100% pure English in `en`, natural Vietnamese in `vi`)**:
   - If the project's UI, database, or docs are in Vietnamese (e.g. `Ma trận năng lực`, `Tiến trình FLC`, `Vừa đủ`, `Nộp lại`), **translate them into natural English domain terms** inside `en` (`Competency Matrix`, `FLC Progress`, `Just Enough`, `Resubmit`). Never write `For Ma trận năng lực, what does...` or `Does Nhiệm vụ của lớp sits next to...`.
   - In `vi`, translate English domain words into natural Vietnamese (`kỹ năng`, `đánh giá đầu vào`, `khóa học`, `người kèm cặp`) instead of leaving raw English words like `skill` or `assessment` mid-sentence. Keep only established proper nouns, machine/class codes (`F-301`, `B-201`, `CL-2609-014`), or role/process acronyms used in Vietnamese business speech (`SPVB`, `OE`, `OJT`, `FLC`, `SET`, `SOP`).
   - Never leak CJK or foreign characters into `en` or `vi`.
3. **Natural spoken English & clean punctuation**:
   - Use natural spoken contractions (`I'm`, `don't`, `can't`, `isn't`, `doesn't`, `we'll`, `let's`, `that's`, `it's`, `there's`). Avoid stiff written forms (`I am`, `I will`, `do not`, `cannot`, `let us`, `that is`, `it is`) unless stressing a contrast.
   - Never use em-dashes (`—`), en-dashes (`–`), middle dots (`·`), or double quotes (`"`) inside dialogue lines. Use commas, colons, parentheses, or single quotes (`'`) instead.
4. **Exact `words` matching & full diversity across lessons**:
   - Each lesson's `words` array has 3 multi-word phrases/collocations (2-4 words each, e.g. `count toward`, `at a glance`, `short of`), never basic single words.
   - **Exact substring match**: every phrase in `words` must appear **verbatim** (case-insensitive) in that lesson's `en` lines so NTranslate can highlight/underline it in the reading view. Do not put `counts toward` in `words` if the dialogue line says `count toward` (or vice versa).
   - **Never reuse one `words` triple across a tier**: every lesson should have its own tailored `words` triple (at least 40 distinct triples across 50 lessons).
5. **Write, audit, and optimize one tier at a time**:
   - Draft `tier-1.json` (~15 lessons) -> run an audit check -> fix any Vietnamese char in `en`, missing `words` substring, stiff uncontracted phrase, or repeated line -> only then draft `tier-2.json` (~20 lessons) -> audit & fix -> draft `tier-3.json` (~15 lessons) -> audit & fix.
   - Each lesson must have:
     - Dialogue between `A:` (me, BA or project consultant) and `B:` (customer or business stakeholder).
     - 15-20 English lines (`en`) and the exact same number of Vietnamese lines (`vi`), aligned turn by turn with matching `A:` / `B:` prefixes.
     - `pattern`: a reusable customer-conversation template in pure English (serialized as `Prompt pattern: ...` at the end of `text`).

## Step 4: Output format
JSON array. Each item exactly like this:

```json
{
  "words": ["phrase 1", "phrase 2", "phrase 3"],
  "text": "Topic: <Topic>\n\nA: ...\nB: ...\n...\n\nA: <VI>...\nB: <VI>...\n...\n\nPrompt pattern: <pattern>",
  "promptVersion": "7",
  "generatedAt": 812800000,
  "title": "<short title>",
  "scenario": "<Business discovery | Process walkthrough | Business rules | Roles and permissions | Approvals | Data and reporting | Exceptions | Screen walkthrough | Requirements clarification | Solution proposal | Scope and priorities | Change requests | Acceptance criteria | UAT feedback | Meeting wrap-up>",
  "group": "<shared project/topic name, for example NTranslate>",
  "tier": "<Tier 1 - Core prompts | Tier 2 - Full prompts | Tier 3 - Multi-turn>",
  "count": 0
}
```

- `generatedAt`: start at 812800000, +1000 per lesson.
- `count`: always 0.

## Step 5: Build, validate and install into NTranslate
- Store source data only in `./worker/lessons-src/tier-1.json`, `tier-2.json`, `tier-3.json` (fields: `title`, `scenario`, `words`, `topic`, `pattern`, `en[]`, `vi[]`). Delete any helper/template scripts if present.
- Write `./worker/build_lessons.py` to build the final JSON and enforce all hard quality gates (raising `ValueError` if any gate fails):
  1. Valid JSON, 40-55 lessons total, all required fields present, every `group` equals the shared topic, and `tier` is one of the three planned tiers.
  2. `len(en) == len(vi)` and `15 <= len(en) <= 20`, with matching speaker prefixes (`A:` / `B:`) on every paired line.
  3. Zero Vietnamese diacritics (`[À-ỹ]`) in `title`, `pattern`, `words`, or any `en` line; zero CJK characters (`[一-鿿]`) anywhere unless the project is Chinese/Japanese; zero em-dashes (`—`), en-dashes (`–`), or double quotes (`"`) inside `text`.
  4. Every phrase in `words` (3 per lesson) appears as an exact case-insensitive substring in that lesson's `en` text, and at least 35 distinct `words` triples exist across the set.
  5. No single `en` line appears in more than 2 lessons across the entire set (blocks boilerplate tails), and fewer than 5% of `en` lines contain stiff uncontracted forms (`\b(I am|I will|do not|cannot|that is|it is|we are|let us)\b`).
- Output: `./worker/<project-name>-english-lessons.json`.
- Then the same `build_lessons.py` script installs every lesson straight into NTranslate's saved passages:
  - Read `historyDirectory` from `~/Library/Application Support/NTranslate/config.json`. Expand `~`. If missing or empty, use `~/Library/Application Support/NTranslate`.
  - Target folder: `<historyDirectory>/weave/` (create it if missing).
  - **Clean up stale passages of the same group**: scan existing `*.json` in `<historyDirectory>/weave/`; if an existing file has `group == <shared topic>` and its filename stem is not in the new set of SHA-256 hashes, delete it so broken or outdated lessons from previous runs do not remain in NTranslate.
  - File name per lesson: `<sha256 hex of the lesson's text field, UTF-8>.json`. This matches the app's own Import, so running twice never duplicates.
  - File content: the lesson object (`words`, `text`, `promptVersion`, `generatedAt`, `title`, `scenario`, `group`, `tier`, `count`). Write compact JSON, UTF-8.
  - If the file already exists, keep its `count` and `isDone` values instead of overwriting them with defaults, so learner progress survives a rerun.
  - Print the target folder and how many files were written new, updated, and removed.
- Do not modify any project source code. Only create files inside `./worker/` and inside the NTranslate `weave` folder.

## Step 6: Report
Briefly summarize: shared topic and number of lessons per tier, which project features were covered, any area you skipped, quality-gate results (unique word triples, duplicate lines = 0, stale files removed), and the folder the lessons were installed to. Tell the user to open (or reopen) Saved Passages in NTranslate to see them; no restart is needed.
"""#
}
