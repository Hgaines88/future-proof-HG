import pytest

from notegoat import create_note, read_note_body


def test_create_note_writes_a_file(notes_home):
    path = create_note(notes_home, "My Note", "Hello.")

    assert path.exists()
    assert path.name == "my-note.md"


def test_created_note_starts_with_a_yaml_header(notes_home):
    path = create_note(notes_home, "My Note", "Hello.")
    text = path.read_text(encoding="utf-8")

    assert text.startswith("---\n")


def test_body_round_trips(notes_home):
    path = create_note(notes_home, "My Note", "line one\nline two")

    assert read_note_body(path) == "line one\nline two\n"


def test_duplicate_title_is_refused(notes_home):
    create_note(notes_home, "My Note", "first")

    with pytest.raises(FileExistsError):
        create_note(notes_home, "My Note", "second")