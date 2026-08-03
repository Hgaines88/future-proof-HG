from notegoat import create_note, filter_notes_by_tag, get_all_tags


def corrupt_note(notes_dir):
    """Drop a note with an unterminated header into the library."""
    notes = notes_dir / "notes"
    notes.mkdir(parents=True, exist_ok=True)
    (notes / "broken.md").write_text("---\ntitle: Broken\n", encoding="utf-8")


def test_get_all_tags_is_deduplicated_and_sorted(notes_home):
    create_note(notes_home, "One", "body", "zebra, apple")
    create_note(notes_home, "Two", "body", "apple, Mango")

    assert get_all_tags(notes_home) == ["apple", "Mango", "zebra"]


def test_get_all_tags_on_an_empty_library(notes_home):
    assert get_all_tags(notes_home) == []


def test_get_all_tags_skips_a_corrupt_note(notes_home):
    create_note(notes_home, "Good", "body", "keeper")
    corrupt_note(notes_home)

    assert get_all_tags(notes_home) == ["keeper"]


def test_filter_by_tag_finds_the_right_note(notes_home):
    create_note(notes_home, "Tagged", "body", "coursework")
    create_note(notes_home, "Other", "body", "personal")

    matches = filter_notes_by_tag(notes_home, "coursework")

    assert [path.name for path in matches] == ["tagged.md"]


def test_filter_by_tag_is_case_insensitive(notes_home):
    create_note(notes_home, "Tagged", "body", "CourseWork")

    assert len(filter_notes_by_tag(notes_home, "coursework")) == 1


def test_filter_by_an_unknown_tag_returns_nothing(notes_home):
    create_note(notes_home, "Tagged", "body", "coursework")

    assert filter_notes_by_tag(notes_home, "nope") == []


def test_filter_matches_whole_tags_not_substrings(notes_home):
    create_note(notes_home, "Tagged", "body", "coursework")

    assert filter_notes_by_tag(notes_home, "course") == []


def test_filter_skips_a_corrupt_note(notes_home):
    create_note(notes_home, "Good", "body", "keeper")
    corrupt_note(notes_home)

    assert len(filter_notes_by_tag(notes_home, "keeper")) == 1
