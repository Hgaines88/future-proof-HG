import pytest

from notegoat import filename_from_title


def test_simple_title_becomes_a_slug():
    assert filename_from_title("My First Note") == "my-first-note.md"


def test_japanese_title_is_preserved():
    assert filename_from_title("日本語のノート") == "日本語のノート.md"


def test_punctuation_only_title_is_rejected():
    with pytest.raises(ValueError):
        filename_from_title("...")


def test_long_title_fits_the_filesystem_limit():
    name = filename_from_title("ノ" * 200)
    assert len(name.encode("utf-8")) <= 255
