#!/usr/bin/env bash
#
# check.sh — full test run: the pytest unit suite, then end-to-end smoke tests.
#
# Not a test suite. It catches the five specific regressions the refactor is
# meant to fix, so you can run it after each step and know you have not broken
# anything. Real pytest cases replace this once NOTES_HOME exists.
#
#   ./check.sh
#
# Runs against a scratch notes directory in /tmp. Never touches your real notes.

set -u

APP="${APP:-python/notegoat.py}"
PYTEST="${PYTEST:-python3 -m pytest}"
SANDBOX=/tmp/notes-check-home
PASS=0
FAIL=0
SKIP=0

# --------------------------------------------------------------- helpers ----
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
run()  { HOME="$SANDBOX" python3 "$APP" "$@"; }

[ -f "$APP" ] || { echo "Cannot find $APP — run this from the repo root."; exit 1; }

rm -rf "$SANDBOX"; mkdir -p "$SANDBOX/.notes/notes"
cp test-notes/*.md "$SANDBOX/.notes/notes/" 2>/dev/null || {
  echo "Cannot find test-notes/*.md — run this from the repo root."; exit 1; }

echo
echo "Checking $APP against $SANDBOX"
echo

# ------------------------------------------------- 0. unit tests ------------
# The pytest suite runs first: it is faster and more precise, so a broken core
# surfaces before the slower end-to-end checks below.
echo "0. Unit tests"
if $PYTEST --version >/dev/null 2>&1; then
  if pytest_output=$($PYTEST -q 2>&1); then
    ok "pytest — $(printf '%s' "$pytest_output" | tail -1)"
  else
    bad "pytest suite failed" "$(printf '%s' "$pytest_output" | tail -15)"
  fi
else
  skip "pytest not installed — run: pip3 install pytest"
fi

# ------------------------------------------------- 1. clean stdout ----------
echo
echo "1. CLI output is clean enough to pipe"
out=$(run list 2>/dev/null)
case "$out" in
  *Goodbye*) bad "'list' must not print the REPL farewell" "found 'Goodbye!' in stdout" ;;
  *)         ok  "'list' stdout has no REPL chrome" ;;
esac
case "$out" in
  *"Future Proof Notes Manager"*) bad "'list' must not print the startup banner" ;;
  *)                              ok  "'list' stdout has no startup banner" ;;
esac

# ------------------------------------------------- 2. exit codes ------------
echo
echo "2. Exit codes are meaningful"
run read no-such-note.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "missing note exits 1" || bad "missing note must exit 1" "got $rc"

run list >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "successful list exits 0" || bad "successful list must exit 0" "got $rc"

run search zzzz-no-such-word >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "search with no match exits 1 (like grep)" || bad "no-match search must exit 1" "got $rc"

if run read no-such-note.md >/dev/null 2>&1; then
  bad "'&&' chaining must not run after a failed read"
else
  ok "'&&' chaining correctly short-circuits on failure"
fi

# ------------------------------------------------- 3. errors on stderr ------
echo
echo "3. Errors go to stderr, not stdout"
stdout_only=$(run read no-such-note.md 2>/dev/null)
[ -z "$stdout_only" ] && ok "error message is absent from stdout" \
                      || bad "error message leaked into stdout" "$stdout_only"

# ------------------------------------------------- 4. one note body ---------
echo
echo "4. The two interfaces agree"
body=$(run read sample-note-1.md 2>/dev/null)
case "$body" in
  ---*) bad "'read' must strip the YAML header, as the REPL does" ;;
  *)    ok  "'read' strips the YAML header" ;;
esac
case "$body" in
  *"title: Data Structures"*) bad "'read' is leaking raw front matter" ;;
  *)                          ok  "'read' shows no raw front-matter keys" ;;
esac

cli_line=$(run search algorithms 2>/dev/null | head -1)
repl_line=$(printf 'search\nalgorithms\n0\nquit\n' | HOME="$SANDBOX" python3 "$APP" 2>/dev/null \
            | grep -m1 '^1\. ' | sed 's/^1\. //')
if [ -n "$cli_line" ] && [ "$cli_line" = "$repl_line" ]; then
  ok "CLI and REPL render a note the same way"
else
  bad "CLI and REPL disagree on a note's summary line" "CLI:  $cli_line
        REPL: $repl_line"
fi

# ------------------------------------------------- 5. writes clean md -------
echo
echo "5. Created notes are valid Markdown"
printf 'create\nCheck Script Note\nBody line one.\nBody line two.\n.\nsmoke, test\nquit\n' \
  | HOME="$SANDBOX" python3 "$APP" >/dev/null 2>&1
NOTE="$SANDBOX/.notes/notes/check-script-note.md"
if [ -f "$NOTE" ]; then
  ok "REPL create wrote the file"
  if grep -qE '^[[:space:]]+(title|tags|created):' "$NOTE"; then
    bad "YAML header lines are indented (the f-string bug is back)"
  else
    ok "YAML header has no leading whitespace"
  fi
  head -1 "$NOTE" | grep -qx -- '---' && ok "file starts with ---" \
                                      || bad "file must start with ---"
else
  bad "REPL create did not write $NOTE"
fi

# ------------------------------------------------- 6. unicode durability ----
# The whole project rests on "plain UTF-8 text stays readable forever". These
# checks are what make that claim true rather than aspirational.
echo
echo "6. Unicode survives (the future-proof promise)"

# Byte sequences rather than \u escapes, so this works on macOS bash 3.2 too.
JP=$(printf '\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e')             # 日本語
CAFE_NFC=$(printf 'caf\xc3\xa9')                                 # café  (é as one codepoint)
CAFE_NFD=$(printf 'cafe\xcc\x81')                                # café  (e + combining acute)
EMOJI=$(printf '\xf0\x9f\x92\xa1')                               # 💡

make_note() {  # make_note <title> <body>
  printf 'create\n%s\n%s\n.\n\nquit\n' "$1" "$2" | HOME="$SANDBOX" python3 "$APP" >/dev/null 2>&1
}

# 6a. every file-access call pins the encoding explicitly
unpinned=$(grep -nE '\b(open|read_text|write_text)\(' "$APP" | grep -v 'encoding=' || true)
if [ -z "$unpinned" ]; then
  ok "every open/read_text/write_text pins encoding=\"utf-8\""
else
  bad "a file call does not pin encoding (falls back to system locale)" "$unpinned"
fi

# 6b. a non-ASCII title produces a real filename, not an empty one
make_note "$JP" "body"
made=$(ls "$SANDBOX/.notes/notes/" | grep -c "$JP" || true)
if [ "$made" -ge 1 ]; then
  ok "non-ASCII title produces a usable filename"
else
  bad "non-ASCII title produced no file (ASCII-only slug drops the characters)"
fi

# 6c. that note is findable and readable end to end
# The filename lookup normalises both sides: macOS hands back NFD from the
# filesystem even when the name was written as NFC.
make_note "$CAFE_NFC" "Body with an emoji: $EMOJI"
fname=$(python3 - "$SANDBOX/.notes/notes" <<'PY'
import pathlib, sys, unicodedata
target = unicodedata.normalize("NFC", "caf\u00e9")
for path in sorted(pathlib.Path(sys.argv[1]).iterdir()):
    if target in unicodedata.normalize("NFC", path.name):
        print(path.name)
        break
PY
)
if [ -n "$fname" ]; then
  ok "accented title keeps its accent in the filename ($fname)"

  run list 2>/dev/null | grep -q "$CAFE_NFC" \
    && ok "'list' shows the accented title intact" \
    || bad "'list' mangled or dropped the accented title"

  run search "$CAFE_NFC" >/dev/null 2>&1 \
    && ok "'search' matches a non-ASCII query" \
    || bad "'search' cannot find a note by its non-ASCII title"

  run read "$fname" 2>/dev/null | grep -q "$EMOJI" \
    && ok "emoji in the body survives write then read" \
    || bad "emoji in the body did not round-trip"
else
  bad "accented title lost its accent in the filename" \
      "expected a name containing 'caf\xc3\xa9', got: $(ls "$SANDBOX/.notes/notes/" | grep caf | tr '\n' ' ')"
  FAIL=$((FAIL+3))
fi

# 6d. composed and decomposed forms of the same title agree
# macOS filesystems hand back decomposed (NFD) names, Linux composed (NFC).
# Without unicodedata.normalize the same title yields two different files.
if python3 - "$APP" "$CAFE_NFC" "$CAFE_NFD" <<'PY'
import importlib.util, sys

path, nfc, nfd = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("notesapp", path)
mod = importlib.util.module_from_spec(spec)
sys.argv = [path]
try:
    spec.loader.exec_module(mod)
except SystemExit:
    pass

try:
    sys.exit(0 if mod.filename_from_title(nfc) == mod.filename_from_title(nfd) else 1)
except Exception:
    sys.exit(1)
PY
then
  ok "NFC and NFD spellings of one title map to one filename"
else
  bad "NFC and NFD spellings produce different filenames" \
      'add unicodedata.normalize("NFC", title) in filename_from_title'
fi

# 6e. a long non-ASCII title stays inside the 255-byte filename limit
if python3 - "$APP" <<'PY'
import importlib.util, sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("notesapp", path)
mod = importlib.util.module_from_spec(spec)
sys.argv = [path]
try:
    spec.loader.exec_module(mod)
except SystemExit:
    pass

try:
    name = mod.filename_from_title("\u30ce" * 200)
except Exception:
    sys.exit(1)
# must keep its characters AND fit the filesystem limit
sys.exit(0 if len(name) > 3 and len(name.encode("utf-8")) <= 255 else 1)
PY
then
  ok "long non-ASCII title is preserved and fits the 255-byte limit"
else
  bad "long non-ASCII title is dropped or exceeds 255 bytes" \
      "cap the slug length; CJK is 3 bytes per character in UTF-8"
fi

# 6f. a title with nothing usable in it is rejected clearly, not silently
printf 'create\n...\nbody\n.\n\nquit\n' | HOME="$SANDBOX" python3 "$APP" >/dev/null 2>&1
[ -f "$SANDBOX/.notes/notes/.md" ] \
  && bad "a punctuation-only title created a hidden file named '.md'" \
  || ok "a punctuation-only title is rejected rather than creating '.md'"

# 6g. works when the shell locale claims ASCII
locale_out=$(LC_ALL=C LANG=C HOME="$SANDBOX" python3 "$APP" list 2>&1)
case "$locale_out" in
  *UnicodeDecodeError*|*UnicodeEncodeError*|*Traceback*)
    bad "crashes under LC_ALL=C" "a file call is falling back to the locale encoding" ;;
  *) ok "still works when the locale claims ASCII (LC_ALL=C)" ;;
esac

# ------------------------------------------------- 7. no real notes hit -----
echo
echo "7. Nothing escaped the sandbox"
if [ -d "$HOME/.notes/notes" ] && [ -f "$HOME/.notes/notes/check-script-note.md" ]; then
  bad "a note was written to your REAL notes directory"
else
  ok "your real notes directory was not touched"
fi

# --------------------------------------------------------------- summary ----
echo
echo "-------------------------------------------"
if [ "$SKIP" -gt 0 ]; then
  printf ' %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
else
  printf ' %d passed, %d failed\n' "$PASS" "$FAIL"
fi
echo "-------------------------------------------"
[ "$FAIL" -eq 0 ] || exit 1
