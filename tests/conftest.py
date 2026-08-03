import pytest


@pytest.fixture
def notes_home(tmp_path, monkeypatch):
    """A throwaway notes directory, isolated from the real one."""
    monkeypatch.setenv("NOTEGOAT_HOME", str(tmp_path))
    return tmp_path