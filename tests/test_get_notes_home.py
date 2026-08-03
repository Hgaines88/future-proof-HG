from pathlib import Path

from notegoat import get_notes_home


def test_defaults_to_dot_notes_in_home(monkeypatch):
    monkeypatch.delenv("NOTEGOAT_HOME", raising=False)
    monkeypatch.delenv("NOTES_HOME", raising=False)

    assert get_notes_home() == Path.home() / ".notes"


def test_notegoat_home_overrides_the_default(monkeypatch):
    monkeypatch.setenv("NOTEGOAT_HOME", "/tmp/goat")

    assert get_notes_home() == Path("/tmp/goat")


def test_notes_home_is_honoured_too(monkeypatch):
    monkeypatch.delenv("NOTEGOAT_HOME", raising=False)
    monkeypatch.setenv("NOTES_HOME", "/tmp/plan")

    assert get_notes_home() == Path("/tmp/plan")


def test_notegoat_home_wins_over_notes_home(monkeypatch):
    monkeypatch.setenv("NOTEGOAT_HOME", "/tmp/goat")
    monkeypatch.setenv("NOTES_HOME", "/tmp/plan")

    assert get_notes_home() == Path("/tmp/goat")


def test_tilde_is_expanded(monkeypatch):
    monkeypatch.setenv("NOTEGOAT_HOME", "~/goatnotes")

    assert get_notes_home() == Path.home() / "goatnotes"