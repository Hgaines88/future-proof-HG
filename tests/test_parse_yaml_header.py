import pytest

from notegoat import NoteFormatError, parse_yaml_header

def test_messy_tag_spacing_is_cleaned(tmp_path):
    path = write_note(tmp_path, "---\ntitle: T\ntags: [ a ,  b , ]\n---\n\nbody\n")

    assert parse_yaml_header(path)["tags"] == ["a", "b"]


def test_empty_tags_parse_to_an_empty_list(tmp_path):
    path = write_note(tmp_path, '---\ntitle: "T"\ntags: []\n---\n\nbody\n')

    assert parse_yaml_header(path)["tags"] == []

    
def test_an_unterminated_header_is_rejected(tmp_path):
    path = write_note(tmp_path, "---\ntitle: Broken\ntags: []\n")

    with pytest.raises(NoteFormatError):
        parse_yaml_header(path)


def test_the_error_message_names_the_file(tmp_path):
    path = write_note(tmp_path, "---\ntitle: Broken\n")

    with pytest.raises(NoteFormatError, match="note.md"):
        parse_yaml_header(path)

def write_note(tmp_path, text):
    path = tmp_path / "note.md"
    path.write_text(text, encoding="utf-8")
    return path


def test_reads_a_json_quoted_header(tmp_path):
    path = write_note(tmp_path, '---\ntitle: "My Note"\ntags: ["work", "urgent"]\n---\n\nbody\n')

    metadata = parse_yaml_header(path)

    assert metadata["title"] == "My Note"
    assert metadata["tags"] == ["work", "urgent"]


def test_reads_a_legacy_unquoted_header(tmp_path):
    path = write_note(tmp_path, "---\ntitle: Data Structures\ntags: [coursework, algorithms]\n---\n\nbody\n")

    metadata = parse_yaml_header(path)

    assert metadata["title"] == "Data Structures"
    assert metadata["tags"] == ["coursework", "algorithms"]


def test_a_colon_in_the_title_survives(tmp_path):
    path = write_note(tmp_path, '---\ntitle: "Meeting: Q1"\n---\n\nbody\n')

    assert parse_yaml_header(path)["title"] == "Meeting: Q1"


def test_a_file_with_no_header_falls_back_to_the_filename(tmp_path):
    path = write_note(tmp_path, "just a plain markdown file\n")

    assert parse_yaml_header(path)["title"] == "note.md"


def test_an_empty_file_falls_back_to_the_filename(tmp_path):
    path = write_note(tmp_path, "")

    assert parse_yaml_header(path)["title"] == "note.md"


def test_a_header_line_without_a_colon_is_ignored(tmp_path):
    path = write_note(tmp_path, "---\ntitle: T\njust some words\n---\n\nbody\n")

    metadata = parse_yaml_header(path)

    assert metadata["title"] == "T"
    assert "just some words" not in metadata


def test_a_duplicate_key_keeps_the_last_value(tmp_path):
    path = write_note(tmp_path, "---\ntitle: First\ntitle: Second\n---\n\nbody\n")

    assert parse_yaml_header(path)["title"] == "Second"


def test_a_horizontal_rule_in_the_body_is_not_a_delimiter(tmp_path):
    path = write_note(tmp_path, "---\ntitle: T\n---\n\nbefore\n---\nafter\n")

    assert parse_yaml_header(path)["title"] == "T"