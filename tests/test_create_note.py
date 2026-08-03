import pytest

from notegoat import create_note, parse_yaml_header, read_note_body

def test_a_new_note_has_every_required_field(notes_home):
    path = create_note(notes_home, "Meta", "body", "a, b")
    metadata = parse_yaml_header(path)

    for field in ("id", "title", "author", "created", "modified", "tags"):
        assert field in metadata


def test_created_and_modified_match_on_a_new_note(notes_home):
    metadata = parse_yaml_header(create_note(notes_home, "Meta", "body"))

    assert metadata["created"] == metadata["modified"]


def test_an_explicit_author_wins(notes_home, monkeypatch):
    monkeypatch.setenv("NOTEGOAT_AUTHOR", "Env Person")
    path = create_note(notes_home, "Meta", "body", author="H. Gaines")

    assert parse_yaml_header(path)["author"] == "H. Gaines"


def test_the_author_env_var_is_used_when_none_is_given(notes_home, monkeypatch):
    monkeypatch.setenv("NOTEGOAT_AUTHOR", "Env Person")
    path = create_note(notes_home, "Meta", "body")

    assert parse_yaml_header(path)["author"] == "Env Person"


def test_two_notes_get_different_ids(notes_home):
    one = parse_yaml_header(create_note(notes_home, "One", "body"))
    two = parse_yaml_header(create_note(notes_home, "Two", "body"))

    assert one["id"] != two["id"]

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
