import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

class ImportedCoverData {
  const ImportedCoverData({required this.bytes, required this.extension});

  final List<int> bytes;
  final String extension;
}

class ImportedBookData {
  const ImportedBookData({
    required this.id,
    required this.title,
    required this.author,
    required this.chunks,
    this.pageCount,
    this.pageLabel,
    this.cover,
  });

  final String id;
  final String title;
  final String author;
  final List<ImportedChunk> chunks;
  final int? pageCount;
  final String? pageLabel;
  final ImportedCoverData? cover;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      if (pageCount != null) 'pageCount': pageCount,
      if (pageLabel != null) 'pageLabel': pageLabel,
      'chunks': chunks
          .asMap()
          .entries
          .map(
            (entry) => {
              'id': 'chunk-${(entry.key + 1).toString().padLeft(4, '0')}',
              'chapter': entry.value.chapter,
              if (entry.value.page != null) 'page': entry.value.page,
              'text': entry.value.text,
            },
          )
          .toList(growable: false),
    };
  }
}

class ImportedChunk {
  const ImportedChunk({required this.text, this.chapter, this.page});

  final String text;
  final String? chapter;
  final int? page;
}

class BookImporter {
  // The target keeps the reading rhythm compact without forcing every
  // sentence to be cut at an arbitrary word. The upper limits are safety
  // rails used only when natural sentence boundaries cannot do the job.
  static const _targetWords = 20;
  static const _softMaxWords = 30;
  static const _hardMaxWords = 36;
  static const _tailMergeMaxWords = 40;
  static const _blockTags = {
    'article',
    'blockquote',
    'div',
    'li',
    'p',
    'pre',
    'section',
    'td',
    'th',
    'tr',
  };
  static const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  static const _skipTags = {'head', 'nav', 'script', 'style', 'svg'};

  static Future<ImportedBookData> fromFile(File file) async {
    final bytes = await file.readAsBytes();
    return fromBytes(bytes, file.path);
  }

  static ImportedBookData fromBytes(List<int> bytes, String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'epub':
        return _fromEpub(bytes, fileName);
      case 'txt':
      case 'md':
        return _fromPlainText(
          utf8.decode(bytes, allowMalformed: true),
          fileName,
        );
      default:
        throw FormatException(
          'Unsupported file type .$extension. Choose an EPUB, TXT, or MD file.',
        );
    }
  }

  static ImportedBookData _fromPlainText(String source, String filePath) {
    final title = _titleFromFile(filePath);
    final sections = source
        .split(RegExp(r'\n\s*\n'))
        .map(_normalizeText)
        .where((text) => text.isNotEmpty)
        .map((text) => _ImportedSection('paragraph', text))
        .toList(growable: false);
    final chunks = _splitIntoChunks(sections);
    if (chunks.isEmpty) {
      throw const FormatException('No readable text was found in this file.');
    }
    return ImportedBookData(
      id: _slugify(title),
      title: title,
      author: 'Imported text',
      chunks: chunks,
    );
  }

  static ImportedBookData _fromEpub(List<int> bytes, String filePath) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final containerXml = _archiveText(archive, 'META-INF/container.xml');
    final container = XmlDocument.parse(containerXml);
    final rootfile = container.descendants.whereType<XmlElement>().firstWhere(
      (element) => element.name.local == 'rootfile',
      orElse: () =>
          throw const FormatException('This EPUB is missing its package file.'),
    );
    final opfPath = Uri.decodeFull(rootfile.getAttribute('full-path') ?? '');
    if (opfPath.isEmpty) {
      throw const FormatException('This EPUB has no readable package path.');
    }

    final opf = XmlDocument.parse(_archiveText(archive, opfPath));
    final title = _metadataValue(opf, 'title') ?? _titleFromFile(filePath);
    final author = _metadataValue(opf, 'creator') ?? 'Imported EPUB';
    final cover = _coverFromEpub(archive, opfPath, opf);
    final manifest = <String, String>{};
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'item') {
        continue;
      }
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id != null && href != null) {
        manifest[id] = href;
      }
    }

    final sections = <_ImportedSection>[];
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'itemref') {
        continue;
      }
      final idref = element.getAttribute('idref');
      final href = idref == null ? null : manifest[idref];
      if (href == null) {
        continue;
      }
      final contentPath = _resolveEpubPath(opfPath, href);
      final content = _archiveTextOrNull(archive, contentPath);
      if (content == null) {
        continue;
      }
      sections.addAll(_htmlSections(content));
    }

    final chunks = _splitIntoChunks(sections);
    if (chunks.isEmpty) {
      throw const FormatException('No readable text was found in this EPUB.');
    }
    final pageCount = sections
        .map((section) => section.page)
        .whereType<int>()
        .fold<int?>(null, (maximum, page) {
          if (maximum == null || page > maximum) {
            return page;
          }
          return maximum;
        });
    return ImportedBookData(
      id: _slugify(title),
      title: title,
      author: author,
      chunks: chunks,
      pageCount: pageCount,
      pageLabel: pageCount == null ? null : 'Page',
      cover: cover,
    );
  }

  static List<_ImportedSection> _htmlSections(String source) {
    final document = html_parser.parse(source);
    final body = document.body;
    if (body == null) {
      return const [];
    }

    final sections = <_ImportedSection>[];
    int? currentPage;
    void visit(Node node) {
      if (node is! Element) {
        return;
      }
      final tag = node.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) {
        return;
      }
      final page = _pageNumberFromElement(node);
      if (page != null) {
        currentPage = page;
        return;
      }
      if (_headingTags.contains(tag)) {
        final text = _normalizeText(node.text);
        if (text.isNotEmpty) {
          sections.add(_ImportedSection('heading', text, page: currentPage));
        }
        return;
      }
      if (_blockTags.contains(tag)) {
        final text = _normalizeText(node.text);
        if (text.isNotEmpty) {
          sections.add(_ImportedSection('paragraph', text, page: currentPage));
        }
        return;
      }
      for (final child in node.nodes) {
        visit(child);
      }
    }

    for (final child in body.nodes) {
      visit(child);
    }
    return sections;
  }

  static List<ImportedChunk> _splitIntoChunks(List<_ImportedSection> sections) {
    final chunks = <ImportedChunk>[];
    String? currentChapter;
    int? currentPage;
    final currentWords = <String>[];
    final hasGutenbergMarkers = sections.any(
      (section) =>
          _isGutenbergStart(section.text) || _isGutenbergEnd(section.text),
    );
    var started = !hasGutenbergMarkers;

    void flush({bool allowShortMerge = false}) {
      if (currentWords.isEmpty) {
        return;
      }
      final currentText = currentWords.join(' ');
      if (allowShortMerge &&
          currentWords.length < _targetWords &&
          chunks.isNotEmpty &&
          chunks.last.chapter == currentChapter) {
        final previous = chunks.last;
        final previousWords = previous.text.split(' ');
        final combinedWords = previousWords.length + currentWords.length;
        if (combinedWords <= _tailMergeMaxWords) {
          chunks.removeLast();
          chunks.add(
            ImportedChunk(
              chapter: previous.chapter,
              page: previous.page ?? currentPage,
              text: '${previous.text} $currentText',
            ),
          );
          currentWords.clear();
          currentPage = null;
          return;
        }
      }
      chunks.add(
        ImportedChunk(
          chapter: currentChapter,
          page: currentPage,
          text: currentText,
        ),
      );
      currentWords.clear();
      currentPage = null;
    }

    void addSentence(List<String> words, int? page) {
      if (words.isEmpty) {
        return;
      }
      currentPage ??= page;

      if (currentWords.isNotEmpty &&
          currentWords.length + words.length > _softMaxWords) {
        final combinedWords = currentWords.length + words.length;
        if (currentWords.length < _targetWords &&
            combinedWords <= _tailMergeMaxWords) {
          currentWords.addAll(words);
          flush();
          return;
        }
        flush(allowShortMerge: true);
        currentPage = page;
      }

      currentWords.addAll(words);
      if (currentWords.length >= _targetWords) {
        flush();
      }
    }

    for (final section in sections) {
      if (_isGutenbergStart(section.text)) {
        started = true;
        continue;
      }
      if (_isGutenbergEnd(section.text)) {
        break;
      }
      if (!started) {
        continue;
      }

      if (section.kind == 'heading') {
        final heading = _chapterHeading(section.text);
        if (heading != null) {
          flush(allowShortMerge: true);
          currentChapter = heading;
        }
        continue;
      }

      final paragraphHeading = _chapterHeading(section.text);
      if (paragraphHeading != null && section.text.split(' ').length <= 8) {
        flush(allowShortMerge: true);
        currentChapter = paragraphHeading;
        continue;
      }

      for (final sentence in _sentenceSplit(section.text)) {
        final words = sentence.split(' ');
        if (words.isEmpty) {
          continue;
        }
        if (words.length > _hardMaxWords) {
          for (final part in _splitLongSentence(words)) {
            addSentence(part, section.page);
          }
          continue;
        }
        addSentence(words, section.page);
      }
    }
    flush(allowShortMerge: true);
    return _coalesceShortChunks(chunks);
  }

  static List<ImportedChunk> _coalesceShortChunks(List<ImportedChunk> chunks) {
    final result = List<ImportedChunk>.of(chunks);
    var changed = true;
    while (changed) {
      changed = false;
      for (var index = 0; index < result.length; index++) {
        final current = result[index];
        if (_wordCount(current.text) >= _targetWords) {
          continue;
        }

        if (index + 1 < result.length &&
            result[index + 1].chapter == current.chapter &&
            _wordCount(current.text) + _wordCount(result[index + 1].text) <=
                _tailMergeMaxWords) {
          final next = result.removeAt(index + 1);
          result[index] = ImportedChunk(
            chapter: current.chapter,
            page: current.page ?? next.page,
            text: '${current.text} ${next.text}',
          );
          changed = true;
          break;
        }

        if (index > 0 && result[index - 1].chapter == current.chapter) {
          final previous = result[index - 1];
          if (_wordCount(previous.text) + _wordCount(current.text) <=
              _tailMergeMaxWords) {
            result[index - 1] = ImportedChunk(
              chapter: previous.chapter,
              page: previous.page ?? current.page,
              text: '${previous.text} ${current.text}',
            );
            result.removeAt(index);
            changed = true;
            break;
          }
        }
      }
    }
    return result;
  }

  static int _wordCount(String text) => text.split(' ').length;

  static List<List<String>> _splitLongSentence(List<String> words) {
    final pieceCount = (words.length / _softMaxWords).ceil();
    final pieces = <List<String>>[];
    var start = 0;

    for (var pieceIndex = 0; pieceIndex < pieceCount; pieceIndex++) {
      final remainingWords = words.length - start;
      final remainingPieces = pieceCount - pieceIndex;
      if (remainingPieces == 1) {
        pieces.add(words.sublist(start));
        break;
      }

      final idealLength = (remainingWords / remainingPieces).ceil();
      final minimumLength = math.max(1, idealLength - 5);
      final maximumLength = math.min(
        remainingWords - (remainingPieces - 1),
        idealLength + 5,
      );
      var length = idealLength;
      for (
        var candidate = minimumLength;
        candidate <= maximumLength;
        candidate++
      ) {
        if (_isClauseBoundary(words[start + candidate - 1])) {
          length = candidate;
          break;
        }
      }
      pieces.add(words.sublist(start, start + length));
      start += length;
    }
    return pieces;
  }

  static bool _isClauseBoundary(String word) {
    final withoutClosingPunctuation = word.replaceAll(
      RegExp(r'''["'”’)\]}]+$'''),
      '',
    );
    return withoutClosingPunctuation.endsWith(',') ||
        withoutClosingPunctuation.endsWith(';') ||
        withoutClosingPunctuation.endsWith(':') ||
        withoutClosingPunctuation.endsWith('—') ||
        withoutClosingPunctuation.endsWith('–');
  }

  static String _archiveText(Archive archive, String path) {
    final text = _archiveTextOrNull(archive, path);
    if (text == null) {
      throw FormatException('The EPUB is missing $path.');
    }
    return text;
  }

  static String? _archiveTextOrNull(Archive archive, String path) {
    final bytes = _archiveBytesOrNull(archive, path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  static List<int>? _archiveBytesOrNull(Archive archive, String path) {
    return archive.findFile(path)?.content;
  }

  static String _resolveEpubPath(String opfPath, String href) {
    final parts = <String>[];
    final base = opfPath.split('/')..removeLast();
    for (final part in [
      ...base,
      ...Uri.decodeFull(href).split('#').first.split('/'),
    ]) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static String? _metadataValue(XmlDocument document, String localName) {
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName &&
          element.innerText.trim().isNotEmpty) {
        return _normalizeText(element.innerText);
      }
    }
    return null;
  }

  static ImportedCoverData? _coverFromEpub(
    Archive archive,
    String opfPath,
    XmlDocument opf,
  ) {
    final manifest = <String, _EpubManifestItem>{};
    String? metadataCoverId;
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'item') {
        final id = element.getAttribute('id');
        final href = element.getAttribute('href');
        final mediaType = element.getAttribute('media-type');
        if (id != null && href != null && mediaType != null) {
          manifest[id] = _EpubManifestItem(
            href: href,
            mediaType: mediaType,
            properties: element.getAttribute('properties') ?? '',
          );
        }
      } else if (element.name.local == 'meta' &&
          element.getAttribute('name')?.toLowerCase() == 'cover') {
        metadataCoverId = element.getAttribute('content');
      }
    }

    _EpubManifestItem? coverItem = metadataCoverId == null
        ? null
        : manifest[metadataCoverId];
    if (coverItem == null) {
      for (final item in manifest.values) {
        if (item.properties.split(' ').contains('cover-image')) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem == null) {
      for (final item in manifest.values) {
        if (item.mediaType.startsWith('image/') &&
            item.href.toLowerCase().contains('cover')) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem == null || !coverItem.mediaType.startsWith('image/')) {
      return null;
    }

    final coverPath = _resolveEpubPath(opfPath, coverItem.href);
    final coverBytes = _archiveBytesOrNull(archive, coverPath);
    if (coverBytes == null || coverBytes.isEmpty) {
      return null;
    }
    final extension = switch (coverItem.mediaType.toLowerCase()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
    return ImportedCoverData(bytes: coverBytes, extension: extension);
  }

  static int? _pageNumberFromElement(Element element) {
    final type = [
      element.attributes['epub:type'],
      element.attributes['type'],
      element.attributes['role'],
    ].whereType<String>().join(' ').toLowerCase();
    if (!type.contains('pagebreak') &&
        !type.contains('page-break') &&
        !type.contains('page break')) {
      return null;
    }

    for (final attribute in ['data-page', 'title', 'aria-label', 'id']) {
      final value = element.attributes[attribute];
      final match = value == null ? null : RegExp(r'\d+').firstMatch(value);
      if (match != null) {
        return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  static List<String> _sentenceSplit(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map(_normalizeText)
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  static String? _chapterHeading(String text) {
    if (text.length > 100) {
      return null;
    }
    if (RegExp(
      r'\b(chapter|part|book|volume|prologue|epilogue|preface|introduction|letter|act|scene)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return text;
    }
    if (RegExp(r'^[IVXLCDM]+[.)]?$', caseSensitive: false).hasMatch(text)) {
      return text;
    }
    if (RegExp(r'[A-Z]').hasMatch(text) &&
        text == text.toUpperCase() &&
        text.split(' ').length <= 10) {
      return text;
    }
    return null;
  }

  static bool _isGutenbergStart(String text) {
    return text.toUpperCase().contains('START OF THE PROJECT GUTENBERG');
  }

  static bool _isGutenbergEnd(String text) {
    final upper = text.toUpperCase();
    return upper.contains('END OF THE PROJECT GUTENBERG') ||
        upper.contains('THE FULL PROJECT GUTENBERG');
  }

  static String _normalizeText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([,.;:!?])'), r'\1')
        .trim();
  }

  static String _titleFromFile(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final withoutExtension = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final words = withoutExtension.replaceAll(RegExp(r'[_-]+'), ' ').split(' ');
    return words
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  static String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'imported-book' : slug;
  }
}

class _ImportedSection {
  const _ImportedSection(this.kind, this.text, {this.page});

  final String kind;
  final String text;
  final int? page;
}

class _EpubManifestItem {
  const _EpubManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String href;
  final String mediaType;
  final String properties;
}
