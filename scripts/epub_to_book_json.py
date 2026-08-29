import argparse
import html
import json
import posixpath
import re
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
from xml.etree import ElementTree


BLOCK_TAGS = {
    "article",
    "blockquote",
    "div",
    "li",
    "p",
    "pre",
    "section",
    "td",
    "th",
    "tr",
}
HEADING_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
SKIP_TAGS = {"head", "nav", "script", "style", "svg"}
TARGET_WORDS = 20
SOFT_MAX_WORDS = 30
HARD_MAX_WORDS = 36
TAIL_MERGE_MAX_WORDS = 40


def local_name(tag):
    return tag.rsplit("}", 1)[-1].lower()


def normalize_text(value):
    value = html.unescape(value)
    value = re.sub(r"\s+", " ", value).strip()
    value = re.sub(r"\s+([,.;:!?])", r"\1", value)
    return value


class EpubTextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.current = []
        self.current_kind = "paragraph"
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in SKIP_TAGS:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag in HEADING_TAGS:
            self._flush()
            self.current_kind = "heading"
        elif tag in BLOCK_TAGS:
            self._flush()
            self.current_kind = "paragraph"
        elif tag == "br":
            self.current.append(" ")

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in SKIP_TAGS:
            self.skip_depth = max(0, self.skip_depth - 1)
            return
        if self.skip_depth:
            return
        if tag in BLOCK_TAGS or tag in HEADING_TAGS:
            self._flush()

    def handle_data(self, data):
        if not self.skip_depth:
            self.current.append(data)

    def close(self):
        super().close()
        self._flush()

    def _flush(self):
        text = normalize_text(" ".join(self.current))
        self.current = []
        if text:
            self.blocks.append((self.current_kind, text))


def read_epub(epub_path):
    with zipfile.ZipFile(epub_path) as archive:
        container = ElementTree.fromstring(archive.read("META-INF/container.xml"))
        rootfile = next(
            element
            for element in container.iter()
            if local_name(element.tag) == "rootfile"
        )
        opf_path = unquote(rootfile.attrib["full-path"])
        opf_dir = posixpath.dirname(opf_path)
        opf = ElementTree.fromstring(archive.read(opf_path))

        metadata = {}
        for element in opf.iter():
            name = local_name(element.tag)
            if name in {"title", "creator"} and element.text:
                metadata[name] = normalize_text(element.text)

        manifest = {}
        for element in opf.iter():
            if local_name(element.tag) == "item":
                manifest[element.attrib["id"]] = unquote(element.attrib["href"])

        spine_ids = [
            element.attrib["idref"]
            for element in opf.iter()
            if local_name(element.tag) == "itemref"
        ]

        sections = []
        for spine_id in spine_ids:
            href = manifest.get(spine_id)
            if not href:
                continue
            content_path = posixpath.normpath(posixpath.join(opf_dir, href.split("#", 1)[0]))
            if content_path not in archive.namelist():
                continue
            parser = EpubTextParser()
            parser.feed(archive.read(content_path).decode("utf-8", errors="replace"))
            parser.close()
            sections.extend(parser.blocks)

    return metadata, sections


def is_gutenberg_start(text):
    upper = text.upper()
    return "START OF THE PROJECT GUTENBERG" in upper


def is_gutenberg_end(text):
    upper = text.upper()
    return "END OF THE PROJECT GUTENBERG" in upper or "THE FULL PROJECT GUTENBERG" in upper


def sentence_split(text):
    return [part.strip() for part in re.split(r"(?<=[.!?])\s+", text) if part.strip()]


def chapter_heading(text):
    if len(text) > 100:
        return None
    if re.search(
        r"\b(chapter|part|book|volume|prologue|epilogue|preface|introduction|letter|act|scene)\b",
        text,
        flags=re.IGNORECASE,
    ):
        return text
    if re.fullmatch(r"[IVXLCDM]+[.)]?", text.strip(), flags=re.IGNORECASE):
        return text
    if text.isupper() and len(text.split()) <= 10:
        return text
    return None


def is_clause_boundary(word):
    word = re.sub(r'''["'”’)\]}]+$''', "", word)
    return word.endswith((",", ";", ":", "—", "–"))


def split_long_sentence(words):
    piece_count = (len(words) + SOFT_MAX_WORDS - 1) // SOFT_MAX_WORDS
    pieces = []
    start = 0

    for piece_index in range(piece_count):
        remaining_words = len(words) - start
        remaining_pieces = piece_count - piece_index
        if remaining_pieces == 1:
            pieces.append(words[start:])
            break

        ideal_length = (remaining_words + remaining_pieces - 1) // remaining_pieces
        minimum_length = max(1, ideal_length - 5)
        maximum_length = min(
            remaining_words - (remaining_pieces - 1),
            ideal_length + 5,
        )
        length = ideal_length
        for candidate in range(minimum_length, maximum_length + 1):
            if is_clause_boundary(words[start + candidate - 1]):
                length = candidate
                break
        pieces.append(words[start : start + length])
        start += length
    return pieces


def split_into_chunks(sections):
    chunks = []
    current_chapter = None
    current_words = []
    has_gutenberg_markers = any(
        is_gutenberg_start(text) or is_gutenberg_end(text)
        for _, text in sections
    )
    started = not has_gutenberg_markers

    def flush(allow_short_merge=False):
        nonlocal current_words
        if current_words:
            if (
                allow_short_merge
                and len(current_words) < TARGET_WORDS
                and chunks
                and chunks[-1]["chapter"] == current_chapter
                and len(chunks[-1]["text"].split()) + len(current_words)
                <= TAIL_MERGE_MAX_WORDS
            ):
                chunks[-1]["text"] += " " + " ".join(current_words)
                current_words = []
                return
            chunks.append(
                {
                    "chapter": current_chapter,
                    "text": " ".join(current_words),
                }
            )
            current_words = []

    def add_sentence(words):
        nonlocal current_words
        if not words:
            return

        if current_words and len(current_words) + len(words) > SOFT_MAX_WORDS:
            combined_words = len(current_words) + len(words)
            if len(current_words) < TARGET_WORDS and combined_words <= TAIL_MERGE_MAX_WORDS:
                current_words.extend(words)
                flush()
                return
            flush(allow_short_merge=True)

        current_words.extend(words)
        if len(current_words) >= TARGET_WORDS:
            flush()

    for kind, text in sections:
        if is_gutenberg_start(text):
            started = True
            continue
        if is_gutenberg_end(text):
            break
        if not started:
            continue
        if kind == "heading":
            heading = chapter_heading(text)
            if heading is not None:
                flush(allow_short_merge=True)
                current_chapter = heading
            continue

        paragraph_heading = chapter_heading(text)
        if paragraph_heading is not None and len(text.split()) <= 8:
            flush(allow_short_merge=True)
            current_chapter = paragraph_heading
            continue

        for sentence in sentence_split(text):
            words = sentence.split()
            if not words:
                continue

            if len(words) > HARD_MAX_WORDS:
                for part in split_long_sentence(words):
                    add_sentence(part)
                continue

            add_sentence(words)

    flush(allow_short_merge=True)
    return coalesce_short_chunks(chunks)


def coalesce_short_chunks(chunks):
    result = list(chunks)
    changed = True
    while changed:
        changed = False
        for index, current in enumerate(result):
            current_words = len(current["text"].split())
            if current_words >= TARGET_WORDS:
                continue

            if (
                index + 1 < len(result)
                and result[index + 1]["chapter"] == current["chapter"]
                and current_words + len(result[index + 1]["text"].split())
                <= TAIL_MERGE_MAX_WORDS
            ):
                current["text"] += " " + result.pop(index + 1)["text"]
                changed = True
                break

            if index > 0 and result[index - 1]["chapter"] == current["chapter"]:
                previous = result[index - 1]
                if len(previous["text"].split()) + current_words <= TAIL_MERGE_MAX_WORDS:
                    previous["text"] += " " + result.pop(index)["text"]
                    changed = True
                    break
    return result


def main():
    parser = argparse.ArgumentParser(description="Convert a DRM-free EPUB into Bookwheel JSON.")
    parser.add_argument("input_epub", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--book-id", required=True)
    parser.add_argument("--title")
    parser.add_argument("--author")
    args = parser.parse_args()

    metadata, sections = read_epub(args.input_epub)
    chunks = split_into_chunks(sections)
    if not chunks:
        raise SystemExit("No readable book text was extracted from the EPUB.")

    book = {
        "id": args.book_id,
        "title": args.title or metadata.get("title", args.book_id),
        "author": args.author or metadata.get("creator", "Unknown author"),
        "chunks": [
            {"id": f"chunk-{index:04d}", **chunk}
            for index, chunk in enumerate(chunks, start=1)
        ],
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(book, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"Converted {len(chunks)} chunks to {args.output_json}")


if __name__ == "__main__":
    main()
