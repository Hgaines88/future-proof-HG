#!/usr/bin/env bash
#
# bootstrap-github-project.sh
# -----------------------------------------------------------------------------
# Creates labels, issues, and a GitHub Project board for the Future-Proof Notes
# Phase 1 CLI assignment.
#
#   Usage:
#     ./bootstrap-github-project.sh --dry-run     # print what it would do
#     ./bootstrap-github-project.sh               # actually create everything
#     ./bootstrap-github-project.sh --no-extra    # skip the E10 extra-credit issues
#
#   Prerequisites:
#     gh auth login
#     gh auth refresh -s project      # the 'project' scope is required
#     jq                              # optional; only used to auto-set Status
#
#   Run it from inside your repo directory.
#
#   Creates: 5 labels x epics, ~72 issues, 1 project board.
#   Takes 3-5 minutes. Safe to re-run only after deleting what it made --
#   it does NOT check for duplicates.
# -----------------------------------------------------------------------------

set -euo pipefail

DRY_RUN=false
INCLUDE_EXTRA=true
PROJECT_TITLE="Future-Proof Notes — Phase 1 CLI"

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --no-extra) INCLUDE_EXTRA=false ;;
    -h|--help)  sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------- preflight --
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI not found. https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1  || { echo "ERROR: not logged in. Run: gh auth login" >&2; exit 1; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
  echo "ERROR: not inside a GitHub repo (or no remote). cd into your repo first." >&2; exit 1; }
OWNER="${REPO%%/*}"

HAS_JQ=false
command -v jq >/dev/null 2>&1 && HAS_JQ=true

echo "Repo:    $REPO"
echo "Owner:   $OWNER"
echo "Project: $PROJECT_TITLE"
$DRY_RUN && echo "MODE:    dry run (nothing will be created)"
echo

MAPFILE=$(mktemp)
PENDING_DIR=$(mktemp -d)
trap 'rm -rf "$MAPFILE" "$PENDING_DIR"' EXIT
COUNT=0

lookup() { grep -m1 "^$1	" "$MAPFILE" 2>/dev/null | cut -f2; }

# Replace {{E1.2}} style placeholders with the real issue number.
resolve() {
  local text="$1" key num
  while [[ "$text" =~ \{\{([A-Za-z0-9._-]+)\}\} ]]; do
    key="${BASH_REMATCH[1]}"
    num="$(lookup "$key")"
    [ -z "$num" ] && num="?"
    text="${text//\{\{$key\}\}/#$num}"
  done
  printf '%s' "$text"
}

# mk <key> <title> <labels-csv> <body>
# Bodies may contain {{E1.2}} style placeholders. Those referring to an issue
# created earlier resolve immediately; forward references are re-resolved by the
# link-fixup pass after every issue exists.
mk() {
  local key="$1" title="$2" labels="$3" raw="$4" body url num
  body="$(resolve "$raw")"
  COUNT=$((COUNT + 1))

  if $DRY_RUN; then
    printf '[%02d] %s   [%s]\n' "$COUNT" "$title" "$labels"
    printf '%s\t%d\n' "$key" "$COUNT" >> "$MAPFILE"
    case "$body" in *'#?'*) printf '%s' "$raw" > "$PENDING_DIR/$COUNT" ;; esac
    return
  fi

  url=$(gh issue create --repo "$REPO" --title "$title" --label "$labels" --body "$body")
  num="${url##*/}"
  printf '%s\t%s\n' "$key" "$num" >> "$MAPFILE"
  printf '[%02d] #%-4s %s\n' "$COUNT" "$num" "$title"
  # Stash the template if it still had unresolved forward references.
  case "$body" in *'#?'*) printf '%s' "$raw" > "$PENDING_DIR/$num" ;; esac
}

# ------------------------------------------------------------------- labels --
echo "Creating labels..."
mklabel() {
  $DRY_RUN && { echo "  label: $1"; return; }
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
  echo "  label: $1"
}

mklabel "type:task"       "0366d6" "Planned implementation work"
mklabel "type:bug"        "d73a4a" "Defect in existing code"
mklabel "type:decision"   "8250df" "Design decision to settle"
mklabel "type:test"       "0e8a16" "Test coverage"
mklabel "type:docs"       "6a737d" "Documentation"
mklabel "blocks-testing"  "b60205" "Must land before any test is written"
mklabel "graded"          "fbca04" "Explicitly called out in the assignment spec"
mklabel "needs-instructor" "e99695" "Blocked on clarification from the instructor"
mklabel "extra-credit"    "c5def5" "Optional"
for e in E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 E10; do
  mklabel "epic:$e" "ededed" "Epic $e"
done
echo

# ==================================================== STEP 1: UNBLOCK TESTING =
# These come first on purpose. Until NOTES_HOME exists, every test you write
# reads and writes your REAL notes in ~/.notes.
echo "Creating issues..."
echo

read -r -d '' B <<'EOF' || true
## Definition of done
`get_notes_home()` returns the value of the `NOTES_HOME` environment variable if
it is set, and `~/.notes` otherwise. No other module contains a hardcoded path.

## Why this is first
**Until this exists, every test that exercises `delete` deletes real notes.**
This single function is what makes the entire test suite safe to run, which is
why it sits ahead of all other work including the bug fixes.

Source: PossiblePlan Task 0.2.

## Acceptance
- [ ] `NOTES_HOME=/tmp/x notes list` reads from `/tmp/x`
- [ ] Unset `NOTES_HOME` falls back to `~/.notes`
- [ ] `grep -rn '\.notes' src/` finds the path in exactly one file

Estimate: 1h
EOF
mk "E1.2" "E1.2 — config.py: get_notes_home() reads NOTES_HOME" "type:task,epic:E1,blocks-testing" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Every command calls `ensure_notes_dir()` on startup, which creates
`$NOTES_HOME/notes/` if it does not already exist.

## Why
The README specifies this behaviour directly: *"Any notes command, when run,
checks to see if there exists a hidden notes directory in your HOME, and if not,
runs the equivalent of a notes init command."*

The `setup()` function in `notes-shell.py` currently has an empty `if` block
where this belongs.

## Acceptance
- [ ] Deleting `~/.notes` and running any command recreates it
- [ ] Running twice in a row does not error

Blocked by: {{E1.2}}

Estimate: 1h
EOF
mk "E1.4" "E1.4 — ensure_notes_dir() auto-creates the notes directory" "type:task,epic:E1,blocks-testing" "$B"

# ======================================================= STEP 2: FIX DEFECTS ==

read -r -d '' B <<'EOF' || true
## Severity: CRITICAL — verified by reproduction

## What is wrong
In the `create` branch of `command_loop`, the note body is built with an
indented triple-quoted f-string:

```python
note_text = f"""---
                title: {title}
                tags: {tags_value}
                ---

                {content}
                """
```

Python preserves that indentation literally. Every line after the first is
written to disk with 16 leading spaces.

## Why it matters
Four or more leading spaces means **indented code block** in Markdown, so the
note body renders as code in every previewer. The indentation is also
*inconsistent* — only the first line of content gets it, because substitution
happens after the indentation is already baked in.

This is invisible through the app, because `display_note` calls `.strip()` and
hides the damage. It is only visible when the file is opened in a text editor —
which is exactly the scenario this project exists to protect.

## Fix
```python
note_text = (
    "---\n"
    f"title: {title}\n"
    f"tags: {tags_value}\n"
    f"created: {created}\n"
    "---\n\n"
    f"{content}\n"
)
```

## Acceptance
- [ ] `cat ~/.notes/notes/<new-note>.md` shows no leading whitespace
- [ ] Regression test reads the raw bytes and asserts no header line starts with a space
- [ ] Existing malformed notes are migrated or deleted

Estimate: 1h
EOF
mk "P1" "P1 — Created notes are written as invalid Markdown (indented f-string)" "type:bug,epic:E3,graded" "$B"

read -r -d '' B <<'EOF' || true
## Severity: HIGH — verified

## What is wrong
Both the `list` and `search` branches end with `break` after
`display_note(...)`. `break` exits the `while True` in `command_loop`, which
returns to `main()`, which calls `finish()`.

So viewing a single note quits the whole program.

## Fix
Use `continue` instead of `break`, in both places.

## Acceptance
- [ ] `list` → pick a note → view → returns to the `notes>` prompt
- [ ] `search` → pick a note → view → returns to the `notes>` prompt

Estimate: 15m
EOF
mk "P2" "P2 — App exits after viewing a note (break instead of continue)" "type:bug,epic:E6" "$B"

read -r -d '' B <<'EOF' || true
## Severity: MEDIUM

## What is wrong
The `list` and `edit` branches each contain:

```python
notes_dir = Path.home() / ".notes"
```

This shadows the `notes_dir` parameter passed into `command_loop`. Right now it
produces the same value, so nothing visibly breaks.

## Why it matters
The moment `NOTES_HOME` support lands ({{E1.2}}), those two branches will
silently ignore it — **including during tests**, which means the test suite
would operate on real notes even with the fixture in place.

## Fix
Delete both lines. Trust the parameter.

Blocked by: {{E1.2}}

Estimate: 15m
EOF
mk "P3" "P3 — notes_dir silently reassigned inside list and edit branches" "type:bug,epic:E1,blocks-testing" "$B"

read -r -d '' B <<'EOF' || true
## Severity: LOW

`from importlib.metadata import metadata` at the top of `notes-shell.py` is
unused, almost certainly an autocomplete accident, and shares a name with a
local variable used throughout the file.

Harmless today; confusing later.

## Fix
Remove the import.

Estimate: 5m
EOF
mk "P4" "P4 — Remove stray unused importlib import" "type:bug,epic:E1" "$B"

# ============================================================ E0 — PLANNING ===

read -r -d '' B <<'EOF' || true
## Definition of done
A project name is chosen, the repo is renamed, and the README reflects it.

## Why
The README says explicitly: *"CHOOSE your Project's Name NOW.... don't use
future-proof."* Suggested names are listed at the bottom of the README.

Estimate: 30m
EOF
mk "E0.1" "E0.1 — Choose a project name and rename the repo" "type:task,epic:E0,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`docs/PLAN.md` and `docs/SPEC.md` committed. SPEC records the seven design
decisions and their resolutions; PLAN records the build order.

## Why
The README calls out PLAN and SPEC documents by name as something *Future You*
needs in order to pick the project back up.

Estimate: 1.5h
EOF
mk "E0.2" "E0.2 — Write PLAN.md and SPEC.md" "type:docs,epic:E0,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Every task in this repo exists as a card on the project board, sorted into
Backlog / Ready / In Progress / Done.

Estimate: 1h
EOF
mk "E0.3" "E0.3 — Set up the kanban board" "type:task,epic:E0,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
A `dev` branch exists and is the working branch. `main` stays clean.

## Why
The README's contributing section specifies: fork, create a dev branch,
implement, open a PR.

Estimate: 15m
EOF
mk "E0.4" "E0.4 — Create a dev branch and work off it" "type:task,epic:E0" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`.gitignore` covers `__pycache__/`, `.venv/`, `*.pyc`, `.pytest_cache/`, and
`.DS_Store`. `git status` is clean after a full test run.

Note: `.DS_Store` is currently committed in the repo root and should be removed.

Estimate: 15m
EOF
mk "E0.5" "E0.5 — Confirm .gitignore coverage and untrack .DS_Store" "type:task,epic:E0" "$B"

# ========================================================== E1 — FOUNDATION ===

read -r -d '' B <<'EOF' || true
## Definition of done
```
src/notes/
  __init__.py
  config.py
  models.py
  storage.py
  search.py
  cli.py
  shell.py
tests/
```
All imports resolve; `python -c "import notes"` succeeds.

## Why
`notes-shell.py` is 397 lines with a ~200-line function inside it. That already
exceeds what the assignment's own clean-code checklist allows.

Estimate: 1.5h
EOF
mk "E1.1" "E1.1 — Create the package structure" "type:task,epic:E1" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`MAX_TITLE_LENGTH`, `NOTE_EXTENSION`, `PRIORITY_MIN`, `PRIORITY_MAX` defined in
`config.py`. No numeric or string literals for these anywhere else.

## Why
PossiblePlan § Clean Code Methods: *"No Magic Numbers: use named constants
instead of hardcoded values."*

Estimate: 30m
EOF
mk "E1.3" "E1.3 — Extract named constants into config.py" "type:task,epic:E1" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`pyproject.toml` defines a console entry point so that `notes --help` works from
any directory after `pip install -e .`

## Why
The README: *"These commands can all be run from 'anywhere' in your file
system."*

Blocked by: {{E1.1}}

Estimate: 1.5h
EOF
mk "E1.5" "E1.5 — pyproject.toml with a console entry point" "type:task,epic:E1" "$B"

# ========================================================== E2 — NOTE MODEL ===

read -r -d '' B <<'EOF' || true
## Definition of done
A `Note` dataclass with: `id`, `title`, `content`, `created`, `modified`,
`tags`, `author`, `status`, `priority`.

## Why `id`
See the note-identity decision. The README specifies `notes read <note-id>`. If
the id *is* the filename, renaming a title breaks every reference to it.

Estimate: 1.5h
EOF
mk "E2.1" "E2.1 — Note dataclass" "type:task,epic:E2" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`validate_title()` rejects empty strings, whitespace-only strings, and titles
longer than `MAX_TITLE_LENGTH` (200).

Source: PossiblePlan Task 1.2.

## Tests required (3-4)
- [ ] Valid title passes
- [ ] Empty string raises
- [ ] Whitespace-only raises
- [ ] Exactly 200 chars passes, 201 raises

Estimate: 1h
EOF
mk "E2.2" "E2.2 — validate_title()" "type:task,epic:E2" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`validate_priority()` accepts integers 1-5 or `None`, rejects everything else
including strings and out-of-range integers.

Estimate: 45m
EOF
mk "E2.3" "E2.3 — validate_priority()" "type:task,epic:E2" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`Note.to_dict()` and `Note.from_dict()` round-trip without loss for every field,
including `None` optionals and empty tag lists.

Estimate: 45m
EOF
mk "E2.4" "E2.4 — Note.to_dict() / from_dict()" "type:task,epic:E2" "$B"

# ======================================================= E3 — STORAGE LAYER ===

read -r -d '' B <<'EOF' || true
## Definition of done
`yaml.safe_load()` replaces the hand-rolled parser. **Never `yaml.load()`** —
that one executes arbitrary Python from the file.

```
pip install pyyaml
```

## Why
The current parser returns every value as a string, so `tags: [work, urgent]`
becomes the 15-character string `"[work, urgent]"` rather than a list. Tag
filtering is impossible until this changes.

Estimate: 1.5h
EOF
mk "E3.1" "E3.1 — Replace the hand-rolled parser with PyYAML" "type:task,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`format_note(note) -> str` produces clean, unindented Markdown with a valid YAML
header. No line in the header starts with whitespace.

Fixes {{P1}}.

Estimate: 1h
EOF
mk "E3.2" "E3.2 — format_note() emits clean Markdown" "type:task,epic:E3,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`parse_note(text) -> (metadata: dict, content: str)`. Tags come back as a real
Python list. Raises a named exception on a malformed header rather than
returning a dict that looks valid.

Blocked by: {{E3.1}}

Estimate: 1.5h
EOF
mk "E3.3" "E3.3 — parse_note() returns metadata dict and content" "type:task,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`generate_filename(title)` produces `my-first-note-20250520-143022.md` — slug
plus timestamp, so collisions are impossible.

Source: PossiblePlan Task 2.1.

## Why
`filename_from_title` currently produces a bare slug and refuses to create a
second note with the same title. That blocks legitimate repeats like
"Daily standup".

Estimate: 1h
EOF
mk "E3.4" "E3.4 — generate_filename() with a timestamp suffix" "type:task,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
One `list_note_files(notes_dir)` helper, used by both list and search.

## Why
The same three-way glob for `*.md` / `*.note` / `*.txt` currently appears in
both `list_notes` and `search_notes`. Two copies means two places to update.

Also fixes the either/or bug: the current code searches `~/.notes/notes/` **or**
`~/.notes/`, never both, so notes copied to the wrong one are silently invisible.

Estimate: 45m
EOF
mk "E3.5" "E3.5 — Extract list_note_files() helper" "type:task,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Writes go to a temp file in the same directory, then `os.replace()` onto the
target. A crash mid-write cannot leave a truncated note.

## Why
`note_path.write_text(...)` truncates first, then writes. A Ctrl-C in between
leaves a zero-byte note. For a project whose entire premise is data durability,
this is worth four extra lines.

Estimate: 1h
EOF
mk "E3.6" "E3.6 — Atomic writes (temp file + os.replace)" "type:task,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`parse_note(format_note(note))` returns a Note equal to the original, for every
field, including unicode titles and empty tag lists.

**This is the gate for the whole storage epic.** E3 is not done until this
passes.

Blocked by: {{E3.2}}, {{E3.3}}

Estimate: 1h
EOF
mk "E3.7" "E3.7 — Round-trip guarantee: parse(format(note)) == note" "type:test,epic:E3,graded" "$B"

# =============================================================== E4 — CRUD ====

read -r -d '' B <<'EOF' || true
## Definition of done
`create_note()` returns the saved path and sets `created`, `modified`, `author`,
and `id`.

## Why author and modified
The README's YAML Header Specification marks `author` as **Required** and lists
`modified` in the schema. The current `create` writes neither, and writes no id.

Estimate: 1.5h
EOF
mk "E4.1" "E4.1 — create_note() sets all required metadata" "type:task,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`list_notes()` returns a list sorted by `modified` **descending** (newest
first), and returns `[]` rather than `None` when there are no notes.

## Why
Source: PossiblePlan Task 3.2 specifies newest-first. The current code uses
`sorted(note_files)`, which sorts alphabetically by path.

The return type is currently a list on success and `None` on both early-return
paths; callers work by accident.

Estimate: 1h
EOF
mk "E4.2" "E4.2 — list_notes() sorts by modified time, returns a list" "type:task,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`read_note(note_id)` loads by id and raises `NoteNotFound` when absent.

Estimate: 1h
EOF
mk "E4.3" "E4.3 — read_note() by id" "type:task,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`update_note()` bumps `modified` and leaves `created` and `id` untouched.

Estimate: 1h
EOF
mk "E4.4" "E4.4 — update_note() preserves created and id" "type:task,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`delete_note()` in the core deletes without prompting. The **interface** asks
for confirmation.

## Why
Core functions must not call `input()` — that is what makes them testable, and
what lets Phase 2's REST server reuse them.

Consider moving to a `.trash/` folder rather than `unlink()`. Cheap insurance
for a personal notes tool with no undo.

Estimate: 1.5h
EOF
mk "E4.5" "E4.5 — delete_note() with confirmation in the interface layer" "type:task,epic:E4" "$B"

# ============================================================= E5 — SEARCH ====

read -r -d '' B <<'EOF' || true
## Definition of done
`search_notes(query)` matches case-insensitively across title, tags, and
content. Returns a list of Notes.

The existing implementation already uses `.casefold()`, which is the correct
choice — keep it.

Estimate: 1h
EOF
mk "E5.1" "E5.1 — search_notes() across title, tags, content" "type:task,epic:E5" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`filter_by_tag(tag)` works against real tag lists, case-insensitively.

Source: PossiblePlan Task 4.2. Blocked until tags parse as lists.

Blocked by: {{E3.1}}

Estimate: 1h
EOF
mk "E5.2" "E5.2 — filter_by_tag()" "type:task,epic:E5" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`get_all_tags()` returns a deduplicated, alphabetically sorted list.

Source: PossiblePlan Task 4.3.

Estimate: 45m
EOF
mk "E5.3" "E5.3 — get_all_tags()" "type:task,epic:E5" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Search results rank title matches above content matches.

Estimate: 1h
EOF
mk "E5.4" "E5.4 — Rank title matches above content matches" "type:task,epic:E5" "$B"

# ========================================================= E6 — INTERFACES ====

read -r -d '' B <<'EOF' || true
## Definition of done
`argparse`-based CLI with subcommands wired up and accurate `--help` output.

Source: PossiblePlan Tasks 5.1-5.2.

Blocked by: {{D1}} — confirm with the instructor whether the argv CLI or the
REPL is being graded before investing here.

Estimate: 2h
EOF
mk "E6.1" "E6.1 — argparse CLI skeleton" "type:task,epic:E6,needs-instructor" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Handlers for: `create`, `list`, `read`, `edit`, `delete`, `search`, `tags`,
`stats`. Each handler is under 20 lines and calls into the core.

Source: README § Command Reference.

Estimate: 3h
EOF
mk "E6.2" "E6.2 — Command handlers for every documented command" "type:task,epic:E6" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`--tag`, `--tags`, and `--author` flags parse correctly.

The README's example is `notes list --tag "coursework"`.

Estimate: 1h
EOF
mk "E6.3" "E6.3 — Command flags (--tag, --tags, --author)" "type:task,epic:E6" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Errors go to `stderr` with exit code 1. Normal output goes to `stdout` with exit
code 0.

## Why
This is already done correctly in `notes0.py` / `notes1.py` — carry the habit
forward. It is what lets `notes list > out.txt` still show errors on screen.

Estimate: 45m
EOF
mk "E6.4" "E6.4 — Exit codes and stdout/stderr discipline" "type:task,epic:E6" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`command_loop` shrinks to a dispatch table. Each branch becomes
`handle_create()`, `handle_list()`, `handle_delete()`, etc., all under 20 lines,
all calling the same core functions the argv CLI calls.

## Why
`command_loop` is currently ~200 lines and does input parsing, note creation,
deletion, search, prompting, and rendering. PossiblePlan § Clean Code Methods
requires functions to be 10-20 lines and do one thing. **This is graded.**

Fixes {{P5}}.

Blocked by: {{E3.7}}

Estimate: 2h
EOF
mk "E6.5" "E6.5 — Refactor command_loop into handler functions" "type:task,epic:E6,graded" "$B"

# ========================================================= E7 — ROBUSTNESS ====

read -r -d '' B <<'EOF' || true
## Definition of done
A malformed YAML header raises a specific named exception with a useful message,
and the interface offers to show the raw content.

Source: PossiblePlan Task 6.3.

## Why
`parse_yaml_header` currently wraps everything in `except Exception` and returns
a dict that looks like success. A real bug becomes a note silently titled after
its own filename.

Estimate: 1.5h
EOF
mk "E7.1" "E7.1 — Handle corrupted YAML headers with a named exception" "type:task,epic:E7" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`PermissionError` and `OSError` are caught specifically, with useful messages.
No bare `except Exception` anywhere in the codebase.

Source: PossiblePlan Task 6.1.

Estimate: 1.5h
EOF
mk "E7.2" "E7.2 — Catch filesystem errors narrowly" "type:task,epic:E7" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
A missing notes directory is created rather than erroring, on every command.

Blocked by: {{E1.4}}

Estimate: 45m
EOF
mk "E7.3" "E7.3 — Missing directory auto-creates" "type:task,epic:E7" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Emoji and accented characters survive the full title → filename → write → read
round trip.

## Why
UTF-8 is the entire future-proof thesis. `filename_from_title` currently strips
everything outside `[a-z0-9]`, so a title in a non-Latin script produces an
empty filename.

Estimate: 1.5h
EOF
mk "E7.4" "E7.4 — Unicode survives the title-to-filename round trip" "type:task,epic:E7" "$B"

# ============================================================ E8 — TESTING ====

read -r -d '' B <<'EOF' || true
## Definition of done
```python
@pytest.fixture
def notes_home(tmp_path, monkeypatch):
    monkeypatch.setenv("NOTES_HOME", str(tmp_path))
    return tmp_path
```
Every test that touches the filesystem uses this fixture.

## DO NOT WRITE ANY OTHER TEST BEFORE THIS ONE
Without it, a test that exercises `delete` deletes your real notes.

Blocked by: {{E1.2}}, {{P3}}

Estimate: 1.5h
EOF
mk "E8.1" "E8.1 — pytest setup with a NOTES_HOME tmp_path fixture" "type:test,epic:E8,blocks-testing,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
3-4 tests per function in `models.py`: happy path, edge case, error case,
boundary.

Blocked by: {{E8.1}}

Estimate: 2h
EOF
mk "E8.2" "E8.2 — Model tests" "type:test,epic:E8,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Storage tests including:
- [ ] Round trip: `parse(format(note)) == note`
- [ ] Raw bytes: written file starts with `---`, no header line is indented
- [ ] Corrupted file: unclosed header raises a specific named exception
- [ ] Filename collisions produce distinct files

The raw-bytes test is the regression test for {{P1}}.

Blocked by: {{E8.1}}

Estimate: 3h
EOF
mk "E8.3" "E8.3 — Storage tests including round-trip and corruption" "type:test,epic:E8,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Search tests: case-insensitivity, partial match, no match, multi-tag filter,
special characters in the query.

Blocked by: {{E8.1}}

Estimate: 1.5h
EOF
mk "E8.4" "E8.4 — Search and filter tests" "type:test,epic:E8,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Every command tested, plus the unknown-command and missing-argument paths, plus
exit codes.

Blocked by: {{E8.1}}

Estimate: 2h
EOF
mk "E8.5" "E8.5 — CLI tests including error paths" "type:test,epic:E8,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
`pytest --cov` runs and reports coverage. Agree a floor and hold to it.

```
pip install pytest-cov
```

Estimate: 45m
EOF
mk "E8.6" "E8.6 — Coverage reporting" "type:test,epic:E8" "$B"

# ============================================================== E9 — DOCS =====

read -r -d '' B <<'EOF' || true
## Definition of done
README reflects the chosen project name, real usage examples, and the actual
command set.

Blocked by: {{E0.1}}

Estimate: 1.5h
EOF
mk "E9.1" "E9.1 — Rewrite the README for the chosen project name" "type:docs,epic:E9" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
Every public function has a docstring saying what it does, what it returns, and
what it raises.

Estimate: 1h
EOF
mk "E9.2" "E9.2 — Docstrings on every public function" "type:docs,epic:E9,graded" "$B"

read -r -d '' B <<'EOF' || true
## Definition of done
A new reader can clone the repo and run the test suite using only the README.

Estimate: 30m
EOF
mk "E9.3" "E9.3 — Document how to run the tests" "type:docs,epic:E9" "$B"

# ======================================================== DECISIONS D1-D7 =====

read -r -d '' B <<'EOF' || true
## The question
The README's Command Reference and PossiblePlan Phase 5 both describe an
**argv-style CLI**:

```
notes list --tag "coursework"
notes read <note-id>
```

These are shell commands — the program starts, does one thing, exits.

But the repo also ships `notes-shell.py`, an interactive **REPL** skeleton (own
`notes>` prompt, runs until you quit), and that is the one currently extended.

## Why it matters
1. **Flags.** `--tag "coursework"` is argv syntax. A REPL would have to
   reimplement `argparse` by hand inside its loop.
2. **Composability.** `notes search python > out.txt`, `notes list | grep`, and
   cron jobs all work with an argv CLI and none work with a REPL. This is the
   actual future-proof argument.
3. The README says commands run *"from anywhere in your file system"* — a
   statement about a command on `PATH`.

## Where the repo is ambiguous
- Starter files ship **both** patterns (`notes-shell.py` vs `notes0.py`/`notes1.py`)
- `python/README.md` gives no guidance on which to use
- But the **documentation** is argv-only and consistent; PossiblePlan never
  describes a REPL

## Ask the instructor
> "The README's command reference and PossiblePlan Phase 5 both describe an
> argv-style CLI. But the repo also ships notes-shell.py, an interactive REPL
> skeleton, and that's the one I built on. Which interface is being graded? Is a
> REPL acceptable if the argv CLI works too?"

## Recommendation
Build both as thin wrappers over one core. Only `command_loop` is REPL-specific;
everything else is shared. Roughly 60 extra lines, hedges the ambiguity, and
directly demonstrates the separation-of-concerns principle being graded.

**This does not block the storage layer.** Build E3 either way.
EOF
mk "D1" "D1 — Which interface model: REPL, argv CLI, or both?" "type:decision,needs-instructor" "$B"

read -r -d '' B <<'EOF' || true
## Options
Filename · slug · UUID stored in front matter

## Recommendation
**UUID in front matter.**

## Why
The README specifies `notes read <note-id>`. If the id *is* the filename, then
renaming a note's title breaks every reference to it. An id in the header
survives renames.

Phase 2's `GET /api/notes/:id` needs a stable id anyway — and the dataset
sidecar pattern in the README is the same idea: metadata keyed by id lives in a
separate file precisely so the data file can be renamed without losing identity.

Record the decision in `docs/SPEC.md`.
EOF
mk "D2" "D2 — How is a note identified?" "type:decision" "$B"

read -r -d '' B <<'EOF' || true
## Options
`.md` · `.note`

## Recommendation
**`.md`**

## Why
The README says `.note` *"(or any extension you prefer)"* — so the choice is
explicitly yours. PossiblePlan uses `.md` throughout. The current code accepts
`.md`, `.note`, and `.txt`, which means three code paths and no single answer.

Markdown renders on GitHub, in editors, and in every previewer — which is the
future-proof argument itself.

This one needs no permission. It just has to be decided once and written down.
EOF
mk "D3" "D3 — Which file extension?" "type:decision" "$B"

read -r -d '' B <<'EOF' || true
## Options
Keep the hand-rolled parser · switch to PyYAML

## Recommendation
**PyYAML** (`yaml.safe_load`, never `yaml.load`)

## Why
The current parser splits on the first `:` and stores every value as a string,
so `tags: [work, urgent]` becomes the 15-character string `"[work, urgent]"`.
Tag filtering is impossible until this changes.

It also cannot handle nested YAML at all — a line like `  - name: order_id`
produces the key `- name`. The dataset schema in the README is nested.

Implemented by {{E3.1}}.
EOF
mk "D4" "D4 — Hand-rolled YAML parser or PyYAML?" "type:decision" "$B"

read -r -d '' B <<'EOF' || true
## Options
Refuse · timestamp suffix · numeric suffix

## Recommendation
**Timestamp suffix** — `my-note-20250520-143022.md`

## Why
The current code refuses to create a second note with an existing title, which
blocks legitimate repeats like "Daily standup" or "Weekly review".

Source: PossiblePlan Task 2.1 specifies exactly this pattern.

Implemented by {{E3.4}}.
EOF
mk "D5" "D5 — What happens on duplicate titles?" "type:decision" "$B"

read -r -d '' B <<'EOF' || true
## Options
Hardcoded `~/.notes` · `NOTES_HOME` environment variable

## Recommendation
**`NOTES_HOME`, defaulting to `~/.notes`**

## Why
Without it, every test run reads and writes real notes. This is the single
change that makes testing safe, which is why it is the first task in the build
order.

Source: PossiblePlan Task 0.2.

Implemented by {{E1.2}}.
EOF
mk "D6" "D6 — Where do notes live, and how is that configured?" "type:decision" "$B"

read -r -d '' B <<'EOF' || true
## Options
Keep one `notes-shell.py` · split into `src/notes/`

## Recommendation
**Package.**

## Why
397 lines in one file with a ~200-line function inside it already exceeds what
the assignment's own clean-code checklist allows.

The core rule that makes the split work: **no module below `cli.py` or
`shell.py` may call `print()` or `input()`.** Core functions return data or
raise; interfaces decide how to display. That single discipline is what makes
the code unit-testable.

Implemented by {{E1.1}}.
EOF
mk "D7" "D7 — One file or a package?" "type:decision" "$B"

# ==================================================== REMAINING DEFECTS P5-12 =

read -r -d '' B <<'EOF' || true
## Severity: HIGH — graded

`command_loop` is roughly 200 lines and currently does input parsing, note
creation, note deletion, search, user prompting, and rendering.

PossiblePlan § Clean Code Methods:
- *"Single Responsibility: each function does ONE thing"*
- *"Small Functions: keep functions short (ideally 10-20 lines)"*

## Fix
Tracked in {{E6.5}}.
EOF
mk "P5" "P5 — command_loop is ~200 lines and does six different things" "type:bug,epic:E6,graded" "$B"

read -r -d '' B <<'EOF' || true
## Severity: MEDIUM

`parse_yaml_header` strips the brackets off `[work, urgent]` and stores the
string `"work, urgent"`. Good enough to display, impossible to filter.

Blocks {{E5.2}}. Resolved by {{D4}} / {{E3.1}}.
EOF
mk "P6" "P6 — Tags are stored as a string, never a list" "type:bug,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Severity: LOW

The same three-way glob for `*.md` / `*.note` / `*.txt` appears in both
`list_notes` and `search_notes`. Two copies means two places to update when the
extension decision lands.

Fixed by {{E3.5}}.
EOF
mk "P7" "P7 — Duplicated file-discovery logic in list_notes and search_notes" "type:bug,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Severity: LOW

`list_notes` returns a list on success and `None` on both early-return paths.
Callers do `if not note_files: continue`, which works by accident.

Return `[]` instead. Fixed by {{E4.2}}.
EOF
mk "P8" "P8 — list_notes has an inconsistent return type" "type:bug,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Severity: MEDIUM

The README's YAML Header Specification marks `author` as **Required** and lists
`modified` in the schema. The current `create` writes neither, and writes no
`id`.

Fixed by {{E4.1}}.
EOF
mk "P9" "P9 — New notes are missing author, modified, and id" "type:bug,epic:E4" "$B"

read -r -d '' B <<'EOF' || true
## Severity: HIGH — graded

The README is emphatic: *"There are 3-4 test For Every Method!!! Lots o'tests,
many, many tests. So Many Tests!!"*

Current count: zero.

This is the largest single gap between where the project is and where it is
graded. Tracked as epic E8 — but **only after** {{E8.1}} makes testing safe.
EOF
mk "P10" "P10 — No tests exist" "type:bug,epic:E8,graded" "$B"

read -r -d '' B <<'EOF' || true
## Severity: MEDIUM

Creating a second note with an existing title prints an error and gives up.
Legitimate repeats like "Daily standup" become impossible.

Resolved by {{D5}} / {{E3.4}}.
EOF
mk "P11" "P11 — Duplicate titles are refused rather than disambiguated" "type:bug,epic:E3" "$B"

read -r -d '' B <<'EOF' || true
## Severity: LOW probability, HIGH consequence

`note_path.write_text(...)` truncates the file first, then writes. A crash or
Ctrl-C in between leaves a zero-byte note.

For a project whose entire premise is data durability, this is worth the four
extra lines.

Fixed by {{E3.6}}.
EOF
mk "P12" "P12 — Writes are not atomic" "type:bug,epic:E3" "$B"

# ======================================================= E10 — EXTRA CREDIT ===

if $INCLUDE_EXTRA; then
read -r -d '' B <<'EOF' || true
Make the notes directory a git repo and commit on every write.

Listed as extra credit in the README's Phase 1 Technical Requirements.
EOF
mk "E10.1" "E10.1 — Git-backed note storage" "type:task,epic:E10,extra-credit" "$B"

read -r -d '' B <<'EOF' || true
Opt-in per-note encryption with key management.

Listed as extra credit in the README's Phase 1 Technical Requirements.
EOF
mk "E10.2" "E10.2 — Note encryption and key management" "type:task,epic:E10,extra-credit" "$B"

read -r -d '' B <<'EOF' || true
`notes stats` — total notes, total tags, total words, average words per note.

Source: README § Command Reference, PossiblePlan Task 7.1.
EOF
mk "E10.3" "E10.3 — stats command" "type:task,epic:E10,extra-credit" "$B"

read -r -d '' B <<'EOF' || true
Export a single note or the whole library to HTML and PDF.

Source: PossiblePlan Task 7.2.
EOF
mk "E10.4" "E10.4 — HTML and PDF export" "type:task,epic:E10,extra-credit" "$B"

read -r -d '' B <<'EOF' || true
Timestamped zip archive of the notes directory.

Source: PossiblePlan Task 7.3.
EOF
mk "E10.5" "E10.5 — Zip backup" "type:task,epic:E10,extra-credit" "$B"
fi

echo
echo "$COUNT issues prepared."
echo

# ------------------------------------------------------------- link fixup ----
# A few bodies reference issues that had not been created yet at the time. Now
# that every number is known, re-resolve and patch just those.
PENDING_COUNT=$(ls -1 "$PENDING_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$PENDING_COUNT" -gt 0 ]; then
  echo "Fixing $PENDING_COUNT forward reference(s)..."
  for f in "$PENDING_DIR"/*; do
    [ -e "$f" ] || continue
    num=$(basename "$f")
    if $DRY_RUN; then
      echo "  would patch cross-references in issue $num"
    else
      gh issue edit "$num" --repo "$REPO" --body "$(resolve "$(cat "$f")")" >/dev/null
      echo "  patched #$num"
    fi
  done
  echo
fi

# ------------------------------------------------------------------ project --
if $DRY_RUN; then
  echo "Dry run complete. Re-run without --dry-run to create everything."
  exit 0
fi

echo "Creating project board..."
PROJECT_NUMBER=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" \
                   --format json -q .number 2>/dev/null) || {
  echo
  echo "Could not create the project. The most likely cause is a missing scope."
  echo "Run this, then re-run the script (issues are already created):"
  echo "    gh auth refresh -s project"
  exit 1
}
echo "  project #$PROJECT_NUMBER"

echo "Adding issues to the board..."
while IFS=$'\t' read -r key num; do
  gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" \
     --url "https://github.com/$REPO/issues/$num" >/dev/null
  printf '.'
done < "$MAPFILE"
echo " done"

# --------------------------------------------- set Status=Todo on Step 1+2 ---
# Six issues are unblocked right now: NOTES_HOME, auto-init, and the four bug
# fixes. Everything else stays in the default (no status) column.
READY_KEYS="E1.2 E1.4 P1 P2 P3 P4"

if $HAS_JQ; then
  echo "Marking the six unblocked issues as Todo..."
  FIELDS=$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json)
  STATUS_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name=="Status") | .id')
  TODO_OPTION_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name=="Status") | .options[] | select(.name|test("Todo|To do";"i")) | .id' | head -1)
  PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json -q .id)
  ITEMS=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 200 --format json)

  if [ -n "$STATUS_FIELD_ID" ] && [ -n "$TODO_OPTION_ID" ]; then
    for key in $READY_KEYS; do
      num=$(lookup "$key")
      [ -z "$num" ] && continue
      item_id=$(echo "$ITEMS" | jq -r --arg n "$num" \
        '.items[] | select(.content.number == ($n|tonumber)) | .id')
      [ -z "$item_id" ] && continue
      gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" \
         --field-id "$STATUS_FIELD_ID" --single-select-option-id "$TODO_OPTION_ID" >/dev/null
      echo "  $key -> Todo (#$num)"
    done
  else
    echo "  (could not find the Status field; set the six manually)"
  fi
else
  echo "jq not installed — skipping automatic Status assignment."
  echo "Drag these six into Todo by hand: $READY_KEYS"
fi

# ------------------------------------------------------------------ summary --
cat <<SUMMARY

-------------------------------------------------------------------------------
Done.

  Repo:    https://github.com/$REPO/issues
  Board:   https://github.com/users/$OWNER/projects/$PROJECT_NUMBER
  Issues:  $COUNT

START HERE, in this order:

  1. $(lookup E1.2 | sed 's/^/#/')  NOTES_HOME            <- do this before ANY test
  2. $(lookup E1.4 | sed 's/^/#/')  ensure_notes_dir()
  3. $(lookup P1   | sed 's/^/#/')  the indented f-string bug
  4. $(lookup P2   | sed 's/^/#/')  break -> continue
  5. $(lookup P3   | sed 's/^/#/')  notes_dir shadowing
  6. $(lookup P4   | sed 's/^/#/')  stray import

Then ask your instructor about $(lookup D1 | sed 's/^/#/') before starting epic E6.

-------------------------------------------------------------------------------
SUMMARY
