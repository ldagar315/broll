import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_wheel/book_importer.dart';

void main() {
  test('converts plain text into small reading chunks', () {
    final book = BookImporter.fromBytes(
      utf8.encode(
        'The first paragraph begins with a quiet observation about the river. '
        'It continues with enough detail to make the opening scene feel complete and grounded.\n\n'
        'The second paragraph introduces a traveler who carries a worn notebook. '
        'Every page contains a small memory, a question, and a map of the road ahead.',
      ),
      'my_sample_story.txt',
    );

    expect(book.title, 'My Sample Story');
    expect(book.author, 'Imported text');
    expect(book.chunks, isNotEmpty);
    expect(
      book.chunks.every((chunk) {
        final wordCount = chunk.text.split(' ').length;
        return wordCount <= 40;
      }),
      isTrue,
    );
  });

  test('combines short sentences and keeps long sentences readable', () {
    final shortSentences = BookImporter.fromBytes(
      utf8.encode(
        'The rain arrived early. The windows became silver. The room grew quiet. '
        'A kettle began to sing. Someone opened a book and waited.',
      ),
      'short_sentences.txt',
    );
    expect(shortSentences.chunks, hasLength(1));
    expect(shortSentences.chunks.single.text.split(' '), hasLength(23));

    final longSentence = List<String>.generate(
      80,
      (index) => 'word${index + 1}${index % 20 == 19 ? ',' : ''}',
    ).join(' ');
    final longSentenceBook = BookImporter.fromBytes(
      utf8.encode('$longSentence.'),
      'long_sentence.txt',
    );
    expect(longSentenceBook.chunks, hasLength(3));
    expect(
      longSentenceBook.chunks.every(
        (chunk) => chunk.text.split(' ').length <= 40,
      ),
      isTrue,
    );
    expect(
      longSentenceBook.chunks.every(
        (chunk) => chunk.text.split(' ').length >= 20,
      ),
      isTrue,
    );
  });

  test('reads EPUB metadata, spine order, and chapter headings', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>River Notebook</dc:title>
    <dc:creator>Test Author</dc:creator>
  </metadata>
  <manifest>
    <item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="chapter-1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter-1"/>
  </spine>
</package>''',
        ),
      )
      ..addFile(ArchiveFile('OEBPS/cover.jpg', 4, [1, 2, 3, 4]))
      ..addFile(
        ArchiveFile.string(
          'OEBPS/chapter-1.xhtml',
          '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <h1>Chapter 1</h1>
    <span epub:type="pagebreak" id="page-7" title="7"></span>
    <p>The first paragraph begins with a quiet observation about the river. It continues with enough detail to make the opening scene feel complete and grounded.</p>
    <p>The second paragraph introduces a traveler who carries a worn notebook. Every page contains a small memory, a question, and a map of the road ahead.</p>
  </body>
</html>''',
        ),
      );

    final book = BookImporter.fromBytes(
      ZipEncoder().encodeBytes(archive),
      'river_notebook.epub',
    );

    expect(book.title, 'River Notebook');
    expect(book.author, 'Test Author');
    expect(book.chunks, isNotEmpty);
    expect(book.chunks.first.chapter, 'Chapter 1');
    expect(book.pageLabel, 'Page');
    expect(book.pageCount, 7);
    expect(book.chunks.first.page, 7);
    expect(book.cover?.extension, 'jpg');
    expect(book.cover?.bytes, [1, 2, 3, 4]);
  });

  test('rejects unsupported files', () {
    expect(
      () => BookImporter.fromBytes(utf8.encode('not a PDF parser'), 'book.pdf'),
      throwsA(isA<FormatException>()),
    );
  });
}
