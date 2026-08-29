import argparse
import json
import re
from pathlib import Path

import pdfplumber


def normalize_text(value: str) -> str:
    value = re.sub(r"\s+", " ", value).strip()
    value = re.sub(r"\s+([,.;:!?])", r"\1", value)
    return value


def page_lines(page):
    words = page.extract_words(x_tolerance=2, y_tolerance=3, keep_blank_chars=False)
    if not words:
        return []

    lines = []
    for word in words:
        if not lines or abs(word["top"] - lines[-1]["top"]) > 3:
            lines.append({"top": word["top"], "bottom": word["bottom"], "words": [word]})
        else:
            lines[-1]["bottom"] = max(lines[-1]["bottom"], word["bottom"])
            lines[-1]["words"].append(word)

    return [
        {
            "top": line["top"],
            "bottom": line["bottom"],
            "text": normalize_text(" ".join(word["text"] for word in sorted(line["words"], key=lambda item: item["x0"]))),
        }
        for line in lines
    ]


def is_heading(text: str) -> bool:
    return bool(re.match(r"^Chapter\s+\d+\s*:", text, flags=re.IGNORECASE))


def extract_chunks(pdf_path: Path, skip_first_page: bool = False):
    chunks = []
    current_chapter = None
    pending_lines = []
    chunk_number = 1

    def flush_paragraph():
        nonlocal pending_lines, chunk_number
        if not pending_lines:
            return
        text = normalize_text(" ".join(pending_lines))
        if text and not re.match(r"^The Lantern at Lake Merrow - \d+$", text):
            chunks.append(
                {
                    "id": f"chunk-{chunk_number:03d}",
                    "chapter": current_chapter,
                    "text": text,
                }
            )
            chunk_number += 1
        pending_lines = []

    with pdfplumber.open(pdf_path) as pdf:
        for page_number, page in enumerate(pdf.pages):
            if skip_first_page and page_number == 0:
                continue
            lines = page_lines(page)
            if not lines:
                continue
            line_heights = [line["bottom"] - line["top"] for line in lines]
            typical_height = sorted(line_heights)[len(line_heights) // 2]
            paragraph_gap = max(8, typical_height * 1.35)

            previous_bottom = None
            for line in lines:
                text = line["text"]
                if re.match(r"^The Lantern at Lake Merrow - \d+$", text):
                    continue
                if is_heading(text):
                    flush_paragraph()
                    current_chapter = text
                    continue
                if previous_bottom is not None and line["top"] - previous_bottom > paragraph_gap:
                    flush_paragraph()
                pending_lines.append(text)
                previous_bottom = line["bottom"]
            flush_paragraph()

    return chunks


def main():
    parser = argparse.ArgumentParser(description="Convert a text PDF into Bookwheel JSON.")
    parser.add_argument("input_pdf", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--book-id", default="lantern-at-lake-merrow")
    parser.add_argument("--title", default="The Lantern at Lake Merrow")
    parser.add_argument("--author", default="Avery Finch")
    parser.add_argument(
        "--skip-first-page",
        action="store_true",
        help="Skip a title/cover page before extracting story content.",
    )
    args = parser.parse_args()

    chunks = extract_chunks(args.input_pdf, skip_first_page=args.skip_first_page)
    if not chunks:
        raise SystemExit("No readable text was extracted from the PDF.")

    book = {
        "id": args.book_id,
        "title": args.title,
        "author": args.author,
        "chunks": chunks,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(book, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Converted {len(chunks)} chunks to {args.output_json}")


if __name__ == "__main__":
    main()
