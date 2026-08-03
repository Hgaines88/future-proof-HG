#!/usr/bin/env python3
"""
Future Proof Notes Manager - Version Zero
A personal notes manager using text files with YAML headers.
"""


import os
import sys
from pathlib import Path
from datetime import datetime, timezone
import re
import shlex
import subprocess
import argparse
import unicodedata
import json
import getpass
import uuid

class NoteFormatError(Exception):
    """Raised when a note's YAML front matter cannot be parsed."""


# Everything that can go wrong while reading a note off disk.
NOTE_READ_ERRORS = (OSError, UnicodeError, NoteFormatError)

def filename_from_title(title, max_chars=80):
    """Convert a note title into a safe filename, preserving non-ASCII letters.

    Raises ValueError if no usable characters remain.
    """
    normalized = unicodedata.normalize("NFC", title).strip().lower()
    cleaned = re.sub(r"[^\w\s-]", "", normalized)
    cleaned = re.sub(r"[\s_-]+", "-", cleaned).strip("-")

    if not cleaned:
        raise ValueError("Title must contain at least one letter or number.")

    return f"{cleaned[:max_chars]}.md"

def get_author():
    """Return the note author: $NOTEGOAT_AUTHOR, else the OS username."""
    return os.environ.get("NOTEGOAT_AUTHOR") or getpass.getuser()

def get_notes_home():
    """Return the notes directory.

    Precedence:
      1. $NOTEGOAT_HOME
      2. $NOTES_HOME   (the name used in PossiblePlan)
      3. ~/.notes
    """
    configured = os.environ.get("NOTEGOAT_HOME") or os.environ.get("NOTES_HOME")

    if configured:
        return Path(configured).expanduser()

    return Path.home() / ".notes"

def setup(show_status=True):
    """Initialize the notes application."""
    notes_dir = get_notes_home()

    if show_status:
        print("""
NoteGoat v0.1.0 · instantiated by (h)gaines.

Notes that outlive the app that wrote them.
### Any editor · Any machine · Any decade

Zip Code Wilmington :: Data Cohort 7.2 · 2026
        """)
        print("=" * 40)

        if not notes_dir.exists():
            print(f"Notes directory not found at {notes_dir}")
            print("Create a note to initialize it.")
        else:
            print(f"Notes directory: {notes_dir}")

        print()

    return notes_dir

def parse_yaml_header(file_path):
    """Return metadata from a note's YAML front matter."""
    with open(file_path, encoding="utf-8") as file:
        lines = file.readlines()

    metadata = {"title": file_path.name}
    header_closed = False

    if not lines or lines[0].strip() != "---":
        return metadata

    for line in lines[1:]:
        if line.strip() == "---":
            header_closed = True
            break
        if ":" in line:
            key, value = line.split(":", 1)
            key = key.strip()
            raw_value = value.strip()
            parsed_value = raw_value

            if raw_value.startswith(('"', "[", "{")):
                try:
                    parsed_value = json.loads(raw_value)
                except json.JSONDecodeError:
                    pass

            if key == "tags":
                parsed_value = normalize_tags(parsed_value)

            metadata[key] = parsed_value

    if not header_closed:
        raise NoteFormatError(f"{file_path.name}: YAML header is never closed")

    return metadata

def edit_note(note_path):
    """Open the selected note in the user's text editor."""
    if not note_path.exists():
        print("That note no longer exists.")
        return False

    editor = os.environ.get("EDITOR", "nano")
    command = shlex.split(editor) + [str(note_path)]

    try:
        subprocess.run(command, check=True)
    except FileNotFoundError:
        print(f"Could not find the editor: {editor}")
        return False
    except subprocess.CalledProcessError as error:
        print(f"Editor closed with an error: {error}")
        return False
    else:
        print(f"Finished editing: {note_path.name}")
        return True

def find_note_files(notes_dir):
    """Return supported note files from the standard or legacy notes folder."""
    notes_subdir = notes_dir / "notes"
    search_dir = notes_subdir if notes_subdir.is_dir() else notes_dir

    if not search_dir.is_dir():
        return []

    return sorted(
        list(search_dir.glob("*.md"))
        + list(search_dir.glob("*.note"))
        + list(search_dir.glob("*.txt"))
    )

def find_note_by_filename(notes_dir, filename):
    """Return a note path by exact filename, or None if it does not exist."""
    return next(
        (
            note_file
            for note_file in find_note_files(notes_dir)
            if note_file.name == filename
        ),
        None
    )

def search_notes(notes_dir, query):
    """Return note files whose metadata or content contains the query."""


    note_files = find_note_files(notes_dir)

    if not note_files:
        return []

    query = query.casefold()
    matches = []

    for note_file in note_files:
        try:
            metadata = parse_yaml_header(note_file)
            content = note_file.read_text(encoding="utf-8")
        except NOTE_READ_ERRORS:
            continue

        parts = []

        for value in metadata.values():
            if isinstance(value, list):
                parts.extend(str(item) for item in value)
            else:
                parts.append(str(value))

        metadata_text = " ".join(parts)

        if query in metadata_text.casefold() or query in content.casefold():
            matches.append(note_file)

    return matches

def choose_note(note_files, prompt):
    """Prompt for a numbered note and return its file path or None."""
    while True:
        selection = input(prompt).strip()

        if selection == "0":
            return None

        if not selection.isdigit():
            print("Please enter a note number.")
            continue

        note_number = int(selection)

        if note_number < 1 or note_number > len(note_files):
            print(f"Choose a number from 1 to {len(note_files)}.")
            continue

        return note_files[note_number - 1]

def select_note_from_menu(note_files, prompt):
    """Prompt for a note selection and announce a cancelled menu."""
    selected_file = choose_note(note_files, prompt)

    if selected_file is None:
        print("Returning to the main menu.")

    return selected_file


def get_note_title(note_path):
    """Return a note's title from its metadata."""
    metadata = parse_yaml_header(note_path)
    return metadata.get("title", note_path.name)

def format_note_line(note_path):
    """Return one consistent summary line for a note."""
    metadata = parse_yaml_header(note_path)
    title = metadata.get("title", note_path.name)
    created = metadata.get("created", "unknown date")
    tags = metadata.get("tags", [])
    tags_text = ", ".join(tags) if tags else "no tags"

    return f"{title} — {created} — Tags: {tags_text}"

def get_all_tags(notes_dir):
    """Return every tag in use, deduplicated and sorted. Corrupt notes are skipped."""
    tags = set()

    for note_file in find_note_files(notes_dir):
        try:
            metadata = parse_yaml_header(note_file)
        except NOTE_READ_ERRORS:
            continue

        tags.update(metadata.get("tags", []))

    return sorted(tags, key=str.casefold)


def filter_notes_by_tag(notes_dir, tag):
    """Return note files carrying the given tag, matched case-insensitively."""
    wanted = tag.casefold()
    matches = []

    for note_file in find_note_files(notes_dir):
        try:
            metadata = parse_yaml_header(note_file)
        except NOTE_READ_ERRORS:
            continue

        if any(str(each).casefold() == wanted for each in metadata.get("tags", [])):
            matches.append(note_file)

    return matches

def get_stats(notes_dir):
    """Return counts describing the note library. Corrupt notes are counted, not read."""
    note_files = find_note_files(notes_dir)
    total_words = 0
    readable = 0

    for note_file in note_files:
        try:
            body = read_note_body(note_file)
        except NOTE_READ_ERRORS:
            continue

        total_words += len(body.split())
        readable += 1

    return {
        "notes": len(note_files),
        "unreadable": len(note_files) - readable,
        "tags": len(get_all_tags(notes_dir)),
        "words": total_words,
        "average_words": round(total_words / readable) if readable else 0,
    }


def print_stats(notes_dir):
    """Print library statistics. Used by both interfaces."""
    stats = get_stats(notes_dir)

    print(f"Notes:          {stats['notes']}")
    print(f"Tags:           {stats['tags']}")
    print(f"Words:          {stats['words']}")
    print(f"Average words:  {stats['average_words']}")

    if stats["unreadable"]:
        print(f"Unreadable:     {stats['unreadable']}", file=sys.stderr)

def list_notes(notes_dir, tag=None):
    """List notes, optionally filtering them by tag."""
    if tag:
        note_files = filter_notes_by_tag(notes_dir, tag)
    else:
        note_files = find_note_files(notes_dir)

    if not note_files:
        print("No notes found.", file=sys.stderr)
        return [], False

    had_errors = False

    for number, note_file in enumerate(note_files, start=1):
        try:
            line = format_note_line(note_file)
        except NOTE_READ_ERRORS as error:
            line = f"{note_file.name} — unreadable: {error}"
            had_errors = True

        print(f"{number}. {line}")

    print(f"\n{len(note_files)} note(s) found.")
    return note_files, had_errors

def read_note_body(note_path):
    """Return a note's body without its YAML front matter."""
    text = note_path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    if not lines or lines[0].strip() != "---":
        return text

    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "".join(lines[index + 1:]).lstrip("\n")

    raise NoteFormatError(f"{note_path.name}: YAML header is never closed")

def display_note(note_file, title):
    """Display a note's title and body."""
    try:
        content = read_note_body(note_file)
    except NOTE_READ_ERRORS as error:
        print(f"Could not display '{note_file.name}': {error}")
        return

    print("\n" + "=" * 40)
    print(title)
    print("=" * 40)
    print(content)
    print("=" * 40)

    input("\nPress Enter to return to the main menu.")

def show_help():
    """Display help information."""
    help_text = """
  
  help    - Display this help information
  list    - List all notes
  create  - Create a new note
  edit   - Edit an existing note
  delete  - Delete a note
  search  - Search by title, content, tags or metadata
  tags    - List every tag in use
  stats   - Show library statistics
  quit    - Exit the application

    # NoteGoat v0.1.0
    ### Plain UTF-8 Markdown in a folder you own.
    """
    print(help_text)

def normalize_tags(value):
    """Return tags as a list of strings, whatever form they arrived in."""
    if isinstance(value, list):
        return [str(tag).strip() for tag in value if str(tag).strip()]

    text = str(value).strip()

    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]

    return tags_from_input(text)

def tags_from_input(tags):
    """Convert comma-separated tag input into a clean list of strings."""
    return [
        tag.strip()
        for tag in tags.split(",")
        if tag.strip()
    ]

def delete_note(note_path):
    """Delete a note file. Raises OSError if it cannot be removed."""
    note_path.unlink()

def create_note(notes_dir, title, content, tags="", author=None):
    """Create a note file and return its path."""
    filename = filename_from_title(title)

    notes_path = notes_dir / "notes"
    notes_path.mkdir(parents=True, exist_ok=True)

    note_path = notes_path / filename

    if note_path.exists():
        raise FileExistsError(f"A note named '{filename}' already exists.")

    title_value = json.dumps(title, ensure_ascii=False)
    author_value = json.dumps(author or get_author(), ensure_ascii=False)
    tags_value = json.dumps(tags_from_input(tags), ensure_ascii=False)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    note_id = uuid.uuid4()
    body = content.rstrip("\n")

    note_text = (
        f"---\n"
        f"id: {note_id}\n"
        f"title: {title_value}\n"
        f"author: {author_value}\n"
        f"created: {now}\n"
        f"modified: {now}\n"
        f"tags: {tags_value}\n"
        f"---\n"
        f"\n"
        f"{body}\n"
    )

    note_path.write_text(note_text, encoding="utf-8")

    return note_path

def handle_list(notes_dir):
    """Handle the REPL list-and-read flow."""
    note_files, _ = list_notes(notes_dir)

    if not note_files:
        return

    selected_file = select_note_from_menu(
        note_files,
        "Choose a note number (0 to go back): "
    )

    if selected_file is None:
        return

    try:
        selected_title = get_note_title(selected_file)
    except NOTE_READ_ERRORS as error:
        print(f"Could not open '{selected_file.name}': {error}")
        return

    display_note(selected_file, selected_title)

def handle_create(notes_dir):
    """Handle the REPL create flow."""
    title = input("New note title: ").strip()

    if not title:
        print("A note needs a title.")
        return

    print(
        "Enter note content. "
        "Type a single period (.) on a line by itself when finished:"
    )

    content_lines = []

    while True:
        line = input()

        if line == ".":
            break

        content_lines.append(line)

    content = "\n".join(content_lines)
    tags = input("Tags (comma-separated, optional): ").strip()

    try:
        note_path = create_note(notes_dir, title, content, tags)
    except ValueError as error:
        print(error)
    except FileExistsError as error:
        print(error)
    except OSError as error:
        print(f"Could not create note: {error}")
    else:
        print(f"Created note: {note_path.name}")

def handle_edit(notes_dir):
    """Handle the REPL edit flow."""
    note_files, _ = list_notes(notes_dir)

    if not note_files:
        return

    selected_file = select_note_from_menu(
        note_files,
        "Choose a note number to edit (0 to go back): "
    )

    if selected_file is None:
        return

    edit_note(selected_file)

def handle_search(notes_dir):
    """Handle the REPL search-and-read flow."""
    query = input("Search for: ").strip()

    if not query:
        print("Enter something to search for.")
        return

    matches = search_notes(notes_dir, query)

    if not matches:
        print(f"No notes found for: {query}")
        return

    print(f"\nFound {len(matches)} matching note(s):")

    for number, note_file in enumerate(matches, start=1):
        try:
            line = format_note_line(note_file)
        except NOTE_READ_ERRORS as error:
            line = f"{note_file.name} — unreadable: {error}"

        print(f"{number}. {line}")

    selected_file = select_note_from_menu(
        matches,
        "Choose a note number (0 to go back): "
    )

    if selected_file is None:
        return

    try:
        selected_title = get_note_title(selected_file)
    except NOTE_READ_ERRORS as error:
        print(f"Could not open '{selected_file.name}': {error}")
        return

    display_note(selected_file, selected_title)

def handle_delete(notes_dir):
    """Handle the REPL delete flow."""
    note_files, _ = list_notes(notes_dir)

    if not note_files:
        return

    selected_file = select_note_from_menu(
        note_files,
        "Choose a note number to delete (0 to go back): "
    )

    if selected_file is None:
        return

    try:
        selected_title = get_note_title(selected_file)
    except NOTE_READ_ERRORS as error:
        print(f"Could not prepare '{selected_file.name}' for deletion: {error}")
        return

    print(f"Preparing to delete: {selected_title}")
    confirm = input(
        f"Are you sure you want to delete '{selected_title}'? (y/n): "
    ).strip().lower()

    if confirm != "y":
        print("Deletion cancelled.")
        return

    try:
        delete_note(selected_file)
    except OSError as error:
        print(f"Could not delete '{selected_title}': {error}")
    else:
        print(f"Deleted: {selected_title}")

def handle_tags(notes_dir):
    """Print every tag in use."""
    all_tags = get_all_tags(notes_dir)

    if not all_tags:
        print("No tags found.", file=sys.stderr)
        return

    for tag in all_tags:
        print(tag)

def command_loop(notes_dir):
    """Main command loop for processing user input."""
    while True:
        try:
            # Get user input
            command = input("notes> ").strip().lower()

            # Handle empty input
            if not command:
                continue

            # Process commands
            if command == "quit":
                break
            elif command == "help":
                show_help()
            elif command == "list":
                handle_list(notes_dir)
            elif command == "create":
                handle_create(notes_dir)
            elif command == "edit":
                handle_edit(notes_dir)
            elif command == "delete":
                handle_delete(notes_dir)
            elif command == "tags":
                handle_tags(notes_dir)
            elif command == "stats":
                print_stats(notes_dir)
            elif command == "search":
                handle_search(notes_dir)
            else:
                print(f"Unknown command: '{command}'")
                print("Type 'help' for available commands.")

        except EOFError:
            # Handle Ctrl+D
            print()
            break
        except KeyboardInterrupt:
            # Handle Ctrl+C
            print("\nUse 'quit' to exit.")


def finish():
    """Clean up the interactive shell."""
    print("\nGoodbye!")

class NotesArgumentParser(argparse.ArgumentParser):
    """Argument parser that uses exit code 1 for command errors."""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, f"{self.prog}: error: {message}\n")

def build_parser():
    """Create the command-line parser for non-interactive use."""
    parser = NotesArgumentParser(
        prog="notes",
        description="Future Proof Notes Manager"
    )

    subparsers = parser.add_subparsers(dest="command")

    list_parser = subparsers.add_parser("list", help="List notes")
    list_parser.add_argument("--tag", help="Only notes carrying this tag")

    subparsers.add_parser("tags", help="List every tag in use")
    subparsers.add_parser("stats", help="Show library statistics")
    subparsers.add_parser("help", help="Show command-line help")

    search_parser = subparsers.add_parser("search", help="Search notes")
    search_parser.add_argument("query", nargs="+", help="Words to search for")

    read_parser = subparsers.add_parser("read", help="Print one note")
    read_parser.add_argument("filename", help="Note filename")

    create_parser = subparsers.add_parser("create", help="Create a note")
    create_parser.add_argument("title", help="Title for the new note")
    create_parser.add_argument(
        "--author",
        default=None,
        help="Override the note author"
    )
    create_parser.add_argument(
        "--tags",
        default="",
        help="Comma-separated tags"
    )

    edit_parser = subparsers.add_parser("edit", help="Edit one note")
    edit_parser.add_argument("filename", help="Note filename")

    delete_parser = subparsers.add_parser("delete", help="Delete one note")
    delete_parser.add_argument("filename", help="Note filename")
    delete_parser.add_argument(
        "--yes",
        action="store_true",
        help="Confirm deletion without a prompt"
    )

    return parser

def main():
    """Main entry point for the notes application."""
    is_interactive = len(sys.argv) == 1
    notes_dir = setup(show_status=is_interactive)

    if is_interactive:
        command_loop(notes_dir)
        finish()
        return

    parser = build_parser()
    args = parser.parse_args()
    exit_code = 0

    if args.command == "list":
        note_files, had_errors = list_notes(notes_dir, tag=args.tag)

        if had_errors:
            exit_code = 1
        elif args.tag and not note_files:
            exit_code = 1

    elif args.command == "tags":
        tags = get_all_tags(notes_dir)

        if not tags:
            print("No tags found.", file=sys.stderr)
        else:
            for tag in tags:
                print(tag)

    elif args.command == "stats":
        print_stats(notes_dir)

    elif args.command == "help":
        parser.print_help()

    elif args.command == "search":
        query = " ".join(args.query)
        matches = search_notes(notes_dir, query)

        if not matches:
            print(f"No notes found for: {query}", file=sys.stderr)
            exit_code = 1
        else:
            for note_file in matches:
                try:
                    print(format_note_line(note_file))
                except NOTE_READ_ERRORS as error:
                    print(f"Could not format '{note_file.name}': {error}", file=sys.stderr)
                    exit_code = 1

    elif args.command == "read":
        selected_file = find_note_by_filename(notes_dir, args.filename)

        if selected_file is None:
            print(f"Note not found: {args.filename}", file=sys.stderr)
            exit_code = 1
        else:
            try:
                sys.stdout.write(read_note_body(selected_file))
            except NOTE_READ_ERRORS as error:
                print(f"Could not read '{args.filename}': {error}", file=sys.stderr)
                exit_code = 1

    elif args.command == "create":
        piped = not sys.stdin.isatty()
        content = sys.stdin.read() if piped else ""

        try:
            note_path = create_note(
                notes_dir,
                args.title,
                content,
                args.tags,
                args.author
            )
        except ValueError as error:
            print(error, file=sys.stderr)
            exit_code = 1
        except FileExistsError as error:
            print(error, file=sys.stderr)
            exit_code = 1
        except OSError as error:
            print(f"Could not create note: {error}", file=sys.stderr)
            exit_code = 1
        else:
            print(note_path.name)

            if not piped and not edit_note(note_path):
                print(
                    "Note was created, but the editor could not be opened.",
                    file=sys.stderr
                )
                exit_code = 1

    elif args.command == "edit":
        selected_file = find_note_by_filename(notes_dir, args.filename)

        if selected_file is None:
            print(f"Note not found: {args.filename}", file=sys.stderr)
            exit_code = 1
        elif not edit_note(selected_file):
            exit_code = 1

    elif args.command == "delete":
        selected_file = find_note_by_filename(notes_dir, args.filename)

        if selected_file is None:
            print(f"Note not found: {args.filename}", file=sys.stderr)
            exit_code = 1
        elif not args.yes:
            print(
                "Refusing to delete without --yes.",
                file=sys.stderr
            )
            exit_code = 1
        else:
            try:
                delete_note(selected_file)
            except OSError as error:
                print(
                    f"Could not delete '{args.filename}': {error}",
                    file=sys.stderr
                )
                exit_code = 1
            else:
                print(f"Deleted: {args.filename}")

    else:
        parser.error(f"Command not implemented yet: {args.command}")

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
