# Broll

Broll is a deliberately small, local-first Flutter prototype for reading books as a vertical reading feed.

The current build contains a local library with a generated demonstration story and five Project Gutenberg EPUB editions. It demonstrates:

- a home/library screen with book cards;
- a dynamic Continue Reading section for the most recently opened book;
- title search across the local library;
- a prominent EPUB/text import call-to-action on the home screen;
- tapping a book to open its reader;
- a lazy, continuous text reader with the chunk nearest the viewport center highlighted;
- a lightweight catalog loaded at startup, with full book content loaded only when opened;
- local card-position persistence using `shared_preferences`;
- a total-book progress bar, chapter navigation, and optional source-page metadata;
- smooth focus transitions while scrolling, without card or page snapping.
- an in-app import button for EPUB, TXT, and Markdown files;
- on-device conversion into reading chunks targeting about 20 words, usually staying under 30, with a small continuity allowance up to 40 words when preserving sentence flow;
- deletion of imported books, including their local converted data and saved position;
- a branded opening screen with a softly animated Broll mark and reading quotes while the book and saved position are prepared;
- a light Scandinavian paper-and-sage visual system shared by the library and reader;
- Literata typography for long-form reading;
- a soft click sound when focus moves to the next chunk;
- a compact, consistent inter-snippet rhythm that adapts the lazy list extent to chunk length.

The book content and reading position are intentionally separate. The included offline converter turns a legally accessible EPUB into the same JSON shape without changing the reader. EPUB page-break markers are preserved when present, so the reader can show a source page; EPUBs without them still show chapter information and total reading progress.

## Importing a book in the app

Tap the file button in the home screen’s app bar and choose an `.epub`, `.txt`, or `.md` file. The app parses it on the device, detects basic chapter headings, splits readable text into small deterministic chunks, and saves the converted JSON and catalog entry in the app’s private documents directory. Imported books and their reading positions remain available after restarting the app.

PDF import is not included yet. PDFs need a separate text-extraction layer because their text is positioned on a page rather than stored as an ordered document; scanned PDFs may also require OCR.

## Run locally

```text
/Users/lakshaydagar/Development/flutter/bin/flutter pub get
/Users/lakshaydagar/Development/flutter/bin/flutter test
/Users/lakshaydagar/Development/flutter/bin/flutter run
```

## Build and install on Android

```text
/Users/lakshaydagar/Development/flutter/bin/flutter build apk --debug
/Users/lakshaydagar/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The Samsung phone must be connected with USB debugging enabled. The debug APK has been tested on the connected Samsung SM-S721B device.

## Current content contract

The prototype reads `assets/books/library.json`, which contains lightweight metadata and paths to local book JSON assets. Each book has an `id`, `title`, `author`, optional cover asset/path, and ordered `chunks`; each chunk has an `id`, optional `chapter`, and `text`. EPUB imports preserve an embedded cover image when the EPUB exposes one.

The sample pipeline is:

```text
scripts/create_sample_pdf.py
scripts/pdf_to_book_json.py output/pdf/random_story.pdf assets/books/prototype_book.json --skip-first-page
```

Project Gutenberg EPUBs are converted with:

```text
scripts/epub_to_book_json.py source_books/epub/alice_in_wonderland.epub assets/books/alice_in_wonderland.json --book-id alice-in-wonderland
```

The current library includes:

- Alice's Adventures in Wonderland — Lewis Carroll
- The Time Machine — H. G. Wells
- Pride and Prejudice — Jane Austen
- The Adventures of Sherlock Holmes — Arthur Conan Doyle
- Frankenstein — Mary Wollstonecraft Shelley

The original EPUB files are kept in `source_books/epub/`; the app ships the converted JSON assets in `assets/books/`.

The bundled Literata font is distributed under the SIL Open Font License; its license is kept at `assets/fonts/OFL.txt`. The reader sound is a short, locally generated soft click in `assets/sounds/soft_click.wav`.

We will keep the selected book local and uncommitted when it is supplied. The app will not bypass DRM or include an unauthorized copy of a copyrighted book.
