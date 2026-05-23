brook.nvim Screencast Showcase Plan (Corrected)

> Target audience: Neovim users browsing r/neovim, r/vim
> Setup: Firefox source tree (or similarly large C/C++/Rust monorepo, ~100M+ LOC)
> Duration target: 3-5 minutes (trimmed for Reddit posting), or 8-12 min full version

PRE-RECORDING SETUP

1. Prepare the environment

- Clone a large repo (Firefox, Chromium, Linux kernel, or your own monorepo) into /tmp/firefox
- Install brook.nvim via your preferred plugin manager
- Configure init.lua with sensible defaults (or leave defaults — the defaults ARE the story)
- Pre-open Neovim so the recording starts cleanly, not from editor launch
- Have the terminal / iterm2 configured with a clean color scheme (256-color, high contrast for recording)

1. Seed useful visual state

- Open a well-known file in the tree (e.g., a central header or entry point)
- Close all windows, tabs, statuslines — clean editor with just the source buffer
- Have the terminal / iterm2 configured with a clean color scheme (256-color, high contrast for recording)

1. Have search targets pre-identified (pick from the actual Firefox codebase)

- A high-frequency identifier: search for something like Mutex, Token, or NS_ABORT_IF_FALSE — expect 5,000+ results
- A specific narrow pattern: mozilla::ipc::ProtocolId — expect < 50 results (to show precision)
- A visual selection demo: JSContext — highlight the word in a file, press <leader>g

SCENE 1 — "The First Paint" (30 seconds)

Purpose: Prove results appear instantly, even before ripgrep finishes scanning 100M lines.

Action:

1. Open the target directory: :cd /tmp/firefox
2. Type: :Rg -- --hidden --no-ignore-vcs --type=c++ Mutex
3. Show the quickfix list opening immediately with the first ~10 results
4. Zoom in or pause briefly on the bottom quickfix window showing results populating while the search is still running
5. Let it complete — show the final result count

Narration / overlay text: "Results stream in immediately. No waiting for the full scan."

SCENE 2 — High-Frequency Search Performance (60 seconds)

Purpose: Demonstrate brook.nvim handling massive result sets without UI freeze.

Action:

1. Search: :Rg -- --hidden NS_IMPL_CYCLE_COLLECTION (or pick a search with 10,000+ hits)
2. Show the quickfix list continuously updating
3. Highlight the quickfix window — show it staying responsive (type in the editor while results stream)
4. Show that you can still type, scroll, switch buffers — the editor never freezes
5. Use <leader>G to stop mid-search, showing that partial results persist

Narration / overlay text: "10,000+ results. UI never freezes. Stop mid-search — partial results stay."

SCENE 3 — Pattern Translation: n/N Navigation (45 seconds)

Purpose: Demonstrate the PCRE2-to-Vim regex translation enabling n/N navigation.

Action:

1. Open a C++ file with complex patterns: :e path/to/some_file.cpp
2. Run: :Rg --type=c++ '--vimgrep' 'Mozilla(RefPtr|UniquePtr)::'  (regex with alternation)
3. After results appear, press n — show it jumping between matches across buffers
4. Also show N (reverse) working
5. Show /<regex> in search register by running a regex search, then show h on the match highlighting the same text

Narration / overlay text: "Ripgrep regex translated to Vim \v-mode. n and N navigation works across files."

SCENE 4 — Word and Selection Search (30 seconds)

Purpose: Show the simplest, most common workflows.

Action:

1. Open any file, place cursor on a meaningful identifier (e.g., Token)
2. Press <leader>g (cword) — show the quickfix populate with exact-word matches
3. Select a phrase visually (e.g., nsresult), press <leader>g in visual mode — show literal search results
4. Show that these searches use -w (word boundary) and -F (fixed string) under the hood

Narration /overlay text: "Two keystrokes for word search. One more for selection search. No typing a pattern."

SCENE 5 — Search Register + Batch Refactor (60 seconds)

Purpose: Demonstrate the composability — search results feeding directly into edits.

Action:

1. Run: :Rg --type=cpp 'refcounted' (or a more focused search)
2. Wait for results to complete
3. In the quickfix list, run: :cfdo %s/refcounted/refcounted_base/gc
   - Show the confirm prompt (y/n/all/quit)
   - Apply to one or two files, then quit
4. Rerun the same search — show the quickfix list now reflects the changes
5. Show :cnewer / :colder cycling through quickfix history (old searches preserved)

Narration / overlay text: "Search results feed directly into :cfdo. Batch-refactor without re-typing anything. Search history preserved."

SCENE 6 — Pattern Translation Deep Dive (45 seconds) [FIXED SCENE]

Purpose: Show the sophisticated pattern translation pipeline handles the full default regex syntax.

Action:

1. Open the pattern spec doc: :e docs/pattern_spec.md (or :help brook-pattern if that's what it's called)
2. Scroll to the supported constructs table — this is the key: show the features the plugin handles:
   - Character classes: \d, \D, \w, \W, \s, \S, \h, \H, \v, \V
   - Unicode escapes: \x, \u, \U (hex, unicode, octal)
   - Unicode properties: \p{...}, \P{...} (from the Rust regex crate)
   - Boundaries: \b, \B, \A, \z
   - Groups: capturing (...), non-capturing (?:), named groups (?P<name>), flag groups (?i)
   - Quantifiers: greedy, non-greedy (translated to Vim { -} syntax)
   - Alternation, dots, anchors
3. Run: :Rg --type=cpp '\p{Lu}' — match any uppercase letter (unicode property)
4. Show n navigating across matches containing various Unicode characters

Narration / overlay text: "Full default regex support — character classes, unicode escapes, properties, groups, quantifiers — translated to Vim \v mode."

SCENE 7 — Edge Cases / Power Moves (45 seconds)

Purpose: Show the plugin handles real-world usage patterns.

Action (pick 3 of 4):

a) Multiple patterns: :Rg -e TODO -e FIXME --type=cpp --hidden

- Show results from both patterns merged in quickfix, n navigates both

b) Filter by file type: :Rg -t lua -t cpp 'Create'

- Show C++ and Lua results only

c) Case sensitivity toggle: :Rg -s 'Mozilla' (exact) vs :Rg -i 'mozilla' (case-insensitive)

d) Literal search for special chars: :Rg -F '($[0].value)' --type=js

e) Repeat last search: :RgRepeat (or <leader>r) — rerun the last search without retyping

f) Stop + resume: Start a search, press <leader>G to stop, then :RgRepeat to rerun

Narration / overlay text: "Multiple patterns, file types, case control, literal search. One key to repeat."

SCENE 8 — Wrap-Up (15 seconds)

Action:

1. Show the README: :e README.md, scroll to key features
2. Show the GitHub URL
3. Final shot: one last fast search in the massive repo

Overlay text: "brook.nvim — seamless ripgrep search in Neovim. No shell. No dependencies. Just fast."

TECHNICAL NOTES FOR RECORDING

| Aspect       | Recommendation                                                              |
|--------------|-----------------------------------------------------------------------------|
| Software     | asciinema or trec for terminal recording, or QuickTime/ScreenFlow for macOS |
| Zoom level   | 150% so regex and code are readable on 1080p                                |
| Mouse cursor | Show cursor movement on key scenes (show/hide for fast parts)               |
| Speed        | Playback speed up 2x-3x for repetitive streaming; 1x for key presses        |
| Font         | 14pt+ monospace (JetBrains Mono, Fira Code, Cascadia Code)                  |
| Audio        | Optional voiceover or text overlays. Reddit viewers often watch muted       |
| Subtitles    | Consider burned-in subtitles for key points                                 |

ESCALATION PLAN (If something goes wrong)

1. Repo too large, search takes too long to warm up — Use a mid-size search (500-2,000 results) instead of the largest
2. Ripgrep not installed — brew install ripgrep (macOS) or apt install ripgrep (Linux) beforehand
3. Quickfix window covers too much of the editor — Set qf_win_height = 8 in config so it's smaller and less obtrusive
4. Firefox clone too slow — Use a smaller but still large repo: LLVM, Rust compiler, or a large Node.js project

REDPOST-READY TITLES (pick one)

- "brook.nvim: fast ripgrep search in Neovim, shown in the Firefox source tree (100M+ LOC)"
- "I built a Neovim plugin that streams ripgrep into quickfix without freezing the UI"
- "What happens when you search 100M lines of code in Neovim in under 3 seconds"

CHECKLIST BEFORE RECORDING

- [ ] Ripgrep installed and in PATH
- [ ] Large repo cloned and browsable
- [ ] Neovim 0.10+ installed
- [ ] brook.nvim installed and functional
- [ ] Recording software ready
- [ ] Each search target verified to actually return results
- [ ] Neovim config finalized (no extra plugins that add noise)
- [ ] Set max_results = 1000 or higher if you want to show scale
- [ ] Set flush_throttle_ms = 10 (default) — this is already tuned
- [ ] Do a dry run of all 8 scenes (just navigate, no recording)
