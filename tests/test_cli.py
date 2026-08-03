import subprocess
import sys
from pathlib import Path

NOTEGOAT = Path(__file__).resolve().parent.parent / "python" / "notegoat.py"

def test_tags_command_lists_every_tag(notes_home):
    run_cli("create", "Alpha Note", "--tags", "alpha, shared", stdin="x\n")
    run_cli("create", "Beta Note", "--tags", "beta, shared", stdin="x\n")

    result = run_cli("tags")

    assert result.stdout == "alpha\nbeta\nshared\n"
    assert result.returncode == 0


def test_list_filters_by_tag(notes_home):
    run_cli("create", "Alpha Note", "--tags", "alpha", stdin="x\n")
    run_cli("create", "Beta Note", "--tags", "beta", stdin="x\n")

    result = run_cli("list", "--tag", "alpha")

    assert "Alpha Note" in result.stdout
    assert "Beta Note" not in result.stdout


def test_list_with_an_unknown_tag_exits_one(notes_home):
    result = run_cli("list", "--tag", "nope")

    assert result.returncode == 1
    assert result.stdout == ""

def test_list_survives_a_corrupt_note(notes_home):
    notes = notes_home / "notes"
    notes.mkdir(parents=True, exist_ok=True)
    (notes / "broken.md").write_text("---\ntitle: Never Closed\n", encoding="utf-8")
    (notes / "fine.md").write_text('---\ntitle: "Fine"\n---\n\nbody\n', encoding="utf-8")

    result = run_cli("list")

    assert "unreadable" in result.stdout
    assert "Fine" in result.stdout
    assert result.returncode == 1

def run_cli(*args, stdin=""):
    """Run notegoat as a real subprocess.

    Inherits NOTEGOAT_HOME from the notes_home fixture, so the whole program
    operates inside the temp directory.
    """
    return subprocess.run(
        [sys.executable, str(NOTEGOAT), *args],
        input=stdin,
        capture_output=True,
        text=True,
    )


def test_list_on_empty_notes_exits_zero(notes_home):
    result = run_cli("list")

    assert result.returncode == 0
    assert result.stdout == ""
    assert "No notes found" in result.stderr

def test_list_stdout_has_no_repl_chrome(notes_home):
    run_cli("create", "A Note", stdin="body\n")
    result = run_cli("list")

    assert "Goodbye" not in result.stdout
    assert "NoteGoat v" not in result.stdout


def test_read_missing_note_exits_one(notes_home):
    result = run_cli("read", "nope.md")

    assert result.returncode == 1
    assert result.stdout == ""
    assert "not found" in result.stderr.lower()


def test_search_with_no_match_exits_one(notes_home):
    result = run_cli("search", "zzznomatch")

    assert result.returncode == 1


def test_create_from_a_pipe_writes_the_file(notes_home):
    result = run_cli("create", "Piped Note", "--tags", "a,b", stdin="hello\n")

    assert result.returncode == 0
    assert (notes_home / "notes" / "piped-note.md").exists()