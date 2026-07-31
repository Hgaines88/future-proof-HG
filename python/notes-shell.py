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

def setup(show_status=True):
    """Initialize the notes application."""
    notes_dir = Path.home() / ".notes"

    if show_status:
        print("""
        NoteGoat v002 presented by H.Gaines
        for ZipCode Data Cohort 2026.2:
        Plain UTF-8 Markdown in a folder you own.
        Notes that outlive the app that wrote them. 
        Any editor, any machine, any decade.
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

    if not lines or lines[0].strip() != "---":
        return metadata

    for line in lines[1:]:
        if line.strip() == "---":
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
                if isinstance(parsed_value, list):
                    parsed_value = ", ".join(str(tag) for tag in parsed_value)
                elif (
                    isinstance(parsed_value, str)
                    and parsed_value.startswith("[")
                    and parsed_value.endswith("]")
                ):
                    parsed_value = parsed_value[1:-1].strip()

            metadata[key] = parsed_value

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
        except (OSError, UnicodeError):
            continue

        metadata_text = " ".join(str(value) for value in metadata.values())

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
    tags = metadata.get("tags", "no tags")

    return f"{title} — {created} — Tags: {tags}"

def list_notes(notes_dir):
    """List note files and their titles."""
    note_files = find_note_files(notes_dir)

    if not note_files:
        print("No notes found.")
        return [], False

    had_errors = False

    for number, note_file in enumerate(note_files, start=1):
        try:
            line = format_note_line(note_file)
        except (OSError, UnicodeError) as error:
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

    return text

def display_note(note_file, title):
    """Display a note's title and body."""
    try:
        content = read_note_body(note_file)
    except (OSError, UnicodeError) as error:
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
  quit    - Exit the application
    """
    print(help_text)

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

def create_note(notes_dir, title, content, tags=""):
    """Create a note file and return its path."""
    filename = filename_from_title(title)

    notes_path = notes_dir / "notes"
    notes_path.mkdir(parents=True, exist_ok=True)

    note_path = notes_path / filename

    if note_path.exists():
        raise FileExistsError(f"A note named '{filename}' already exists.")

    title_value = json.dumps(title, ensure_ascii=False)
    tags_value = json.dumps(tags_from_input(tags), ensure_ascii=False)
    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = content.rstrip("\n")

    note_text = (
        f"---\n"
        f"title: {title_value}\n"
        f"tags: {tags_value}\n"
        f"created: {created}\n"
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
    except (OSError, UnicodeError) as error:
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
        except (OSError, UnicodeError) as error:
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
    except (OSError, UnicodeError) as error:
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
    except (OSError, UnicodeError) as error:
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

    subparsers.add_parser("list", help="List notes")
    subparsers.add_parser("help", help="Show command-line help")

    search_parser = subparsers.add_parser("search", help="Search notes")
    search_parser.add_argument("query", nargs="+", help="Words to search for")

    read_parser = subparsers.add_parser("read", help="Print one note")
    read_parser.add_argument("filename", help="Note filename")

    create_parser = subparsers.add_parser("create", help="Create a note")
    create_parser.add_argument("title", help="Title for the new note")
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
        _, had_errors = list_notes(notes_dir)

        if had_errors:
            exit_code = 1

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
                except (OSError, UnicodeError) as error:
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
            except (OSError, UnicodeError) as error:
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
                args.tags
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
