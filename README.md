# NoteGoat

### Notes that outlive the app that wrote them.

Plain UTF-8 Markdown in a folder you own. Any editor, any machine, any decade.

---

## What this is

NoteGoat is a personal notes manager. Every note is an ordinary Markdown file with a YAML header, stored in a plain directory on your own disk.

There is no database, no cloud account, and no proprietary format. If NoteGoat disappeared tomorrow, your notes would still open in TextEdit, Vim, VS Code, GitHub, or anything else that can read a text file — which is the entire point.

That constraint drove every design decision in the project. They're recorded in [docs/SPEC.md](docs/SPEC.md).

**Zero runtime dependencies.** NoteGoat uses only the Python standard library. Nothing to install, nothing to break when a package goes unmaintained.

---

## Quick start

```bash
git clone <your-repo-url> notegoat
cd notegoat

# create your first note (body comes from stdin)
echo "My first note." | python3 python/notegoat.py create "Hello World" --tags "demo"

# list what you have
python3 python/notegoat.py list

# or launch the interactive shell
python3 python/notegoat.py
```

Notes land in `~/.notes/notes/` by default. Nothing else on your system is touched.

**Requirements:** Python 3.9 or newer. `pytest` only if you want to run the test suite.

---

## Two ways to use it

NoteGoat has two interfaces over one shared core.

### Command line

Each command runs and exits. Output is designed to be piped, redirected, and scripted.

```
notegoat create <title> [--tags "a, b"] [--author NAME]   Create a note (body from stdin)
notegoat list [--tag TAG]                                 List notes, optionally filtered
notegoat read <filename>                                  Print one note's body
notegoat edit <filename>                                  Open a note in $EDITOR
notegoat delete <filename> --yes                          Delete a note
notegoat search <words...>                                Search titles, tags, and content
notegoat tags                                             List every tag in use
notegoat stats                                            Library statistics
notegoat help                                             Show this help
```

Because output is clean, notes compose with everything else:

```bash
cat draft.txt | notegoat create "From A Draft"
notegoat list --tag coursework > coursework.txt
notegoat search python && echo "found some"
notegoat edit "$(notegoat create 'New Note' < /dev/null)"
```

### Interactive shell

Run with no arguments and you get a prompt. Same commands, but it walks you through numbered menus instead of taking filenames.

```
$ python3 python/notegoat.py

NoteGoat v0.1.0 · instantiated by (h)gaines.

Notes that outlive the app that wrote them.
### Any editor · Any machine · Any decade

Zip Code Wilmington :: Data Cohort 7.2 · 2026

========================================
Notes directory: /Users/you/.notes

notes> list
1. Hello World — 2026-08-03T04:19:08Z — Tags: demo

1 note(s) found.
Choose a note number (0 to go back):
```

Both interfaces call the same functions. Neither one owns any logic.

---

## The note format

A note is a Markdown file with a YAML header between two `---` lines:

```markdown
---
id: b2a6281e-7e84-4f13-acd4-d33d877f9f2d
title: "Example Note"
author: "hakeem"
created: 2026-08-03T04:19:08Z
modified: 2026-08-03T04:19:08Z
tags: ["demo", "docs"]
---

Some body text.
```

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable across renames. A note's identity, not its filename. |
| `title` | String | JSON-encoded, so colons and quotes are safe. |
| `author` | String | From `--author`, `$NOTEGOAT_AUTHOR`, or your OS username. |
| `created` | ISO 8601 UTC | Set once, never changed. |
| `modified` | ISO 8601 UTC | Set at creation. See *Known limitations*. |
| `tags` | Array of strings | JSON array — always valid YAML. |

**Why JSON inside YAML?** JSON is a subset of YAML, so a JSON-encoded value is always valid YAML with correct quoting and escaping — and it costs no dependency. A title like `Meeting: Q1 Review` would break a naive parser; `"Meeting: Q1 Review"` doesn't.

Notes written by hand, by other tools, or with unquoted values still parse. The reader falls back gracefully.

### Filenames

Titles become filenames: `My First Note` → `my-first-note.md`.

Non-ASCII characters survive. `日本語のノート` becomes `日本語のノート.md`, not an empty string. Names are normalised to Unicode NFC so the same title produces the same filename on macOS and Linux, and capped at 80 characters so a long CJK title stays under the 255-byte filesystem limit.

---

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `NOTEGOAT_HOME` | Where notes live | `~/.notes` |
| `NOTES_HOME` | Same, honoured for compatibility | — |
| `NOTEGOAT_AUTHOR` | Author for new notes | Your OS username |
| `EDITOR` | Editor for `edit` | `nano` |

`NOTEGOAT_HOME` wins over `NOTES_HOME`. Both accept `~`.

```bash
NOTEGOAT_HOME=/tmp/scratch notegoat list
```

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Anything went wrong — note not found, no match, refused deletion, unreadable note, bad usage |

A search or tag filter that finds nothing exits `1`, the way `grep` does. That makes `notegoat search foo && ...` behave the way a shell script expects.

Errors and status messages go to **stderr**; data goes to **stdout**. So `notegoat list > notes.txt` gives you a clean file while warnings still reach your screen.

---

## Running the tests

```bash
pip3 install pytest
./check.sh
```

`check.sh` runs the pytest suite first, then a set of end-to-end smoke checks against the real program — output cleanliness, exit codes, CLI/REPL agreement, Unicode durability, and sandbox isolation. It exits non-zero if anything fails, so `./check.sh && git commit` is safe.

To run just the unit tests:

```bash
pytest -v
```

Every test that touches the filesystem runs against a temporary directory. Your real notes are never touched — `check.sh` verifies that explicitly.

---

## Project layout

```
notegoat/
├── python/
│   ├── notegoat.py      the application
│   ├── notes0.py        course starter file, unmodified
│   └── notes1.py        course starter file, unmodified
├── tests/               pytest suite
├── docs/
│   ├── SPEC.md          decisions and their reasoning
│   └── PLAN.md          how this was built
├── test-notes/          sample notes shipped with the course
├── check.sh             full test run
└── pytest.ini
```

---

## Known limitations

Honest ones, all found while building:

- **`modified` never updates.** It's written at creation. `edit` hands the file to `$EDITOR` and doesn't rewrite the header afterward.
- **Block-style YAML sequences are dropped.** `tags: ["a", "b"]` and `tags: [a, b]` both parse; `tags:` followed by indented `- a` lines does not.
- **`main()` hasn't been decomposed.** The interactive loop was broken into per-command handlers; the argument-parsing branch still runs long.
- **No `update` command.** Editing goes through `$EDITOR`; there's no programmatic way to change a note's body or metadata.

---

## Roadmap

Phase 2 would add a REST API and a browser frontend, plus dataset support (`.csv` / `.json` with sidecar metadata) for data-engineering workflows. Phase 3 would add a graphical editor.

Both are out of scope for this version. The design decisions that make them possible — stable ids, a silent core, a single storage root — are already in place.

---

## Credits

Built by H. Gaines at **Zip Code Wilmington**, Data Cohort 7.2, 2026.

Based on the `future-proof` project skeleton by [@kristofer](https://github.com/kristofer). The starter files in `python/` are preserved unmodified for reference.

## License

MIT — see [LICENSE](LICENSE).
