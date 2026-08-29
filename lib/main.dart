import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_importer.dart';

void _openingLog(String message) {
  if (kDebugMode) {
    debugPrint('[Broll.Opening] ${DateTime.now().toIso8601String()} $message');
  }
}

Map<String, dynamic> _decodeBookJson(String source) {
  return jsonDecode(source) as Map<String, dynamic>;
}

void main() {
  runApp(const BookWheelApp());
}

class BookWheelApp extends StatefulWidget {
  const BookWheelApp({super.key});

  @override
  State<BookWheelApp> createState() => _BookWheelAppState();
}

class _BookWheelAppState extends State<BookWheelApp> {
  static const _themePreferenceKey = 'bookwheel.theme.dark';

  bool _isDarkTheme = false;
  bool _themeChangedByUser = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemePreference());
  }

  Future<void> _loadThemePreference() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || _themeChangedByUser) {
      return;
    }
    setState(() {
      _isDarkTheme = preferences.getBool(_themePreferenceKey) ?? false;
    });
  }

  void _toggleTheme() {
    _themeChangedByUser = true;
    setState(() {
      _isDarkTheme = !_isDarkTheme;
    });
    unawaited(_saveThemePreference(_isDarkTheme));
  }

  Future<void> _saveThemePreference(bool isDarkTheme) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_themePreferenceKey, isDarkTheme);
  }

  @override
  Widget build(BuildContext context) {
    const lightPaper = Color(0xFFF4F6F2);
    const lightPaperSurface = Color(0xFFFFFFFF);
    const lightInk = Color(0xFF202824);
    const lightSage = Color(0xFF607A6C);
    const lightSageWash = Color(0xFFDDE8E1);
    const lightPaperTrack = Color(0xFFDCE5DF);
    const darkPaper = Color(0xFF171B18);
    const darkPaperSurface = Color(0xFF222823);
    const darkInk = Color(0xFFEEF2EE);
    const darkSage = Color(0xFF9BB6A7);
    const darkSageWash = Color(0xFF34473D);
    const darkPaperTrack = Color(0xFF46564C);

    final paper = _isDarkTheme ? darkPaper : lightPaper;
    final paperSurface = _isDarkTheme ? darkPaperSurface : lightPaperSurface;
    final ink = _isDarkTheme ? darkInk : lightInk;
    final sage = _isDarkTheme ? darkSage : lightSage;
    final sageWash = _isDarkTheme ? darkSageWash : lightSageWash;
    final paperTrack = _isDarkTheme ? darkPaperTrack : lightPaperTrack;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: sage,
          brightness: _isDarkTheme ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: sage,
          onPrimary: _isDarkTheme ? darkPaper : Colors.white,
          primaryContainer: sageWash,
          onPrimaryContainer: _isDarkTheme ? darkInk : const Color(0xFF25372D),
          surface: paper,
          onSurface: ink,
          surfaceContainerLowest: paperSurface,
          surfaceContainerHighest: _isDarkTheme
              ? const Color(0xFF332C27)
              : const Color(0xFFECE2D5),
        );

    return MaterialApp(
      title: 'Broll',
      theme: ThemeData(
        colorScheme: colorScheme,
        brightness: _isDarkTheme ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: paper,
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 72,
          titleSpacing: 20,
          iconTheme: IconThemeData(color: ink),
        ),
        cardTheme: CardThemeData(
          color: paperSurface,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: ink.withValues(alpha: .08)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: paperSurface,
          hintStyle: TextStyle(color: ink.withValues(alpha: .46)),
          prefixIconColor: ink.withValues(alpha: .62),
          suffixIconColor: ink.withValues(alpha: .58),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: ink.withValues(alpha: .08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: sage.withValues(alpha: .72)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: sage,
          linearTrackColor: paperTrack,
        ),
        useMaterial3: true,
      ),
      home: BrollLaunchScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class BrollLaunchScreen extends StatefulWidget {
  const BrollLaunchScreen({required this.onToggleTheme, super.key});

  final VoidCallback onToggleTheme;

  @override
  State<BrollLaunchScreen> createState() => _BrollLaunchScreenState();
}

class _BrollLaunchScreenState extends State<BrollLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  bool _showLibrary = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final fadeAndSlide = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(fadeAndSlide);
    _scale = Tween<double>(
      begin: .82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _slide = Tween<Offset>(
      begin: const Offset(0, .06),
      end: Offset.zero,
    ).animate(fadeAndSlide);
    unawaited(_controller.forward());
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1250), () {
        if (mounted) {
          setState(() {
            _showLibrary = true;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showLibrary
          ? LibraryScreen(
              key: const ValueKey('broll-library-screen'),
              onToggleTheme: widget.onToggleTheme,
            )
          : _BrollLaunchView(
              key: const ValueKey('broll-launch-view'),
              fade: _fade,
              scale: _scale,
              slide: _slide,
            ),
    );
  }
}

class _BrollLaunchView extends StatelessWidget {
  const _BrollLaunchView({
    required this.fade,
    required this.scale,
    required this.slide,
    super.key,
  });

  final Animation<double> fade;
  final Animation<double> scale;
  final Animation<Offset> slide;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/branding/broll_logo.png',
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Broll',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: const Color(0xFF173A71),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Read the next page.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6F665E),
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.chunks,
    this.pageCount,
    this.pageLabel,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    final rawChunks = json['chunks'] as List<dynamic>;
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      pageCount: json['pageCount'] as int?,
      pageLabel: json['pageLabel'] as String?,
      chunks: rawChunks
          .map((chunk) => BookChunk.fromJson(chunk as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String id;
  final String title;
  final String author;
  final List<BookChunk> chunks;
  final int? pageCount;
  final String? pageLabel;
}

class BookChunk {
  const BookChunk({
    required this.id,
    required this.text,
    this.chapter,
    this.page,
  });

  factory BookChunk.fromJson(Map<String, dynamic> json) {
    return BookChunk(
      id: json['id'] as String,
      text: json['text'] as String,
      chapter: json['chapter'] as String?,
      page: json['page'] as int?,
    );
  }

  final String id;
  final String text;
  final String? chapter;
  final int? page;
}

class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.totalChunks,
    this.asset,
    this.localPath,
    this.coverAsset,
    this.coverPath,
  });

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      totalChunks: json['chunks'] as int,
      asset: json['asset'] as String?,
      localPath: json['localPath'] as String?,
      coverAsset: json['coverAsset'] as String?,
      coverPath: json['coverPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'chunks': totalChunks,
      if (asset != null) 'asset': asset,
      if (localPath != null) 'localPath': localPath,
      if (coverAsset != null) 'coverAsset': coverAsset,
      if (coverPath != null) 'coverPath': coverPath,
    };
  }

  final String id;
  final String title;
  final String author;
  final int totalChunks;
  final String? asset;
  final String? localPath;
  final String? coverAsset;
  final String? coverPath;
}

class BookLibrary {
  static const _manifestAsset = 'assets/books/library.json';
  static const _localBooksDirectory = 'bookwheel_books';
  static const _localCatalogFile = 'bookwheel_imports.json';

  static Future<List<LibraryEntry>> loadCatalog() async {
    final manifestSource = await rootBundle.loadString(_manifestAsset);
    final manifest = jsonDecode(manifestSource) as Map<String, dynamic>;
    final bundledBooks = (manifest['books'] as List<dynamic>)
        .map((book) => LibraryEntry.fromJson(book as Map<String, dynamic>))
        .toList(growable: false);
    final importedBooks = await _loadImportedCatalogSafely();
    return [...bundledBooks, ...importedBooks];
  }

  static Future<Book> loadBook(LibraryEntry entry) async {
    final stopwatch = Stopwatch()..start();
    _openingLog(
      'book-load start id=${entry.id} title="${entry.title}" '
      'expectedChunks=${entry.totalChunks} '
      'source=${entry.localPath == null ? 'asset' : 'file'}',
    );
    final source = entry.localPath == null
        ? await rootBundle.loadString(entry.asset!)
        : await File(entry.localPath!).readAsString();
    _openingLog(
      'book-load read-complete chars=${source.length} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    final decodeInBackground = source.length >= 64 * 1024;
    _openingLog(
      'book-load decode-start mode=${decodeInBackground ? 'isolate' : 'ui'}',
    );
    final decoded = decodeInBackground
        ? await compute(_decodeBookJson, source)
        : _decodeBookJson(source);
    _openingLog(
      'book-load json-decoded elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    final book = Book.fromJson(decoded);
    _openingLog(
      'book-load model-complete chunks=${book.chunks.length} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return book;
  }

  static Future<LibraryEntry> importFile({
    required String fileName,
    String? sourcePath,
    List<int>? bytes,
  }) async {
    final imported = bytes != null
        ? BookImporter.fromBytes(bytes, fileName)
        : await BookImporter.fromFile(File(sourcePath!));
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final booksDirectory = Directory(
      '${documentsDirectory.path}/$_localBooksDirectory',
    );
    await booksDirectory.create(recursive: true);

    final id =
        '${imported.id}-${DateTime.now().millisecondsSinceEpoch.toString()}';
    final bookFile = File('${booksDirectory.path}/$id.json');
    String? coverPath;
    final cover = imported.cover;
    if (cover != null) {
      final coverFile = File('${booksDirectory.path}/$id.${cover.extension}');
      await coverFile.writeAsBytes(cover.bytes, flush: true);
      coverPath = coverFile.path;
    }
    final bookJson = imported.toJson()..['id'] = id;
    await bookFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bookJson),
    );

    final entry = LibraryEntry(
      id: id,
      title: imported.title,
      author: imported.author,
      totalChunks: imported.chunks.length,
      localPath: bookFile.path,
      coverPath: coverPath,
    );
    final existing = await _loadImportedCatalog();
    await _writeImportedCatalog([...existing, entry]);
    return entry;
  }

  static Future<void> deleteImportedBook(LibraryEntry entry) async {
    final localPath = entry.localPath;
    if (localPath == null) {
      throw ArgumentError('Bundled books cannot be deleted.');
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final importedBooksDirectory = Directory(
      '${documentsDirectory.path}/$_localBooksDirectory',
    ).absolute.path;
    final file = File(localPath).absolute;
    final expectedPrefix = '$importedBooksDirectory${Platform.pathSeparator}';
    if (!file.path.startsWith(expectedPrefix)) {
      throw const FileSystemException('The imported book path is invalid.');
    }

    if (await file.exists()) {
      await file.delete();
    }
    final coverPath = entry.coverPath;
    if (coverPath != null) {
      final coverFile = File(coverPath).absolute;
      if (!coverFile.path.startsWith(expectedPrefix)) {
        throw const FileSystemException('The imported cover path is invalid.');
      }
      if (await coverFile.exists()) {
        await coverFile.delete();
      }
    }
    final existing = await _loadImportedCatalog();
    await _writeImportedCatalog(
      existing.where((candidate) => candidate.id != entry.id).toList(),
    );
  }

  static Future<List<LibraryEntry>> _loadImportedCatalog() async {
    final catalogFile = await _localCatalogPath();
    if (!await catalogFile.exists()) {
      return const [];
    }
    final source = await catalogFile.readAsString();
    final catalog = jsonDecode(source) as Map<String, dynamic>;
    return (catalog['books'] as List<dynamic>)
        .map((book) => LibraryEntry.fromJson(book as Map<String, dynamic>))
        .toList(growable: false);
  }

  static Future<List<LibraryEntry>> _loadImportedCatalogSafely() async {
    try {
      return await _loadImportedCatalog().timeout(
        const Duration(milliseconds: 500),
      );
    } on MissingPluginException {
      return const [];
    } on FileSystemException {
      return const [];
    } on TimeoutException {
      return const [];
    }
  }

  static Future<void> _writeImportedCatalog(List<LibraryEntry> entries) async {
    final catalogFile = await _localCatalogPath();
    await catalogFile.writeAsString(
      JsonEncoder.withIndent('  ').convert({
        'books': entries.map((entry) => entry.toJson()).toList(growable: false),
      }),
    );
  }

  static Future<File> _localCatalogPath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return File('${documentsDirectory.path}/$_localCatalogFile');
  }
}

class ReaderProgress {
  static const _keyPrefix = 'bookwheel.reader.card';
  static const lastOpenedKey = 'bookwheel.reader.lastOpened';

  static String keyForId(String id) => '$_keyPrefix.$id';

  static String keyFor(Book book) => keyForId(book.id);

  static Future<int> loadForId(String id) async {
    final stopwatch = Stopwatch()..start();
    final preferences = await SharedPreferences.getInstance();
    final savedIndex = preferences.getInt(keyForId(id)) ?? 0;
    _openingLog(
      'position-load id=$id savedIndex=$savedIndex '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return savedIndex;
  }

  static Future<int> load(Book book) {
    return loadForId(book.id);
  }

  static Future<void> markLastOpened(String id) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(lastOpenedKey, id);
  }

  static Future<void> clearLastOpenedIf(String id) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(lastOpenedKey) == id) {
      await preferences.remove(lastOpenedKey);
    }
  }
}

class LibraryItem {
  const LibraryItem({
    required this.entry,
    required this.currentIndex,
    required this.isLastOpened,
  });

  final LibraryEntry entry;
  final int currentIndex;
  final bool isLastOpened;
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const ValueKey('theme-toggle-button'),
      tooltip: isDark ? 'Use light theme' : 'Use dark theme',
      onPressed: onPressed,
      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.onToggleTheme, super.key});

  final VoidCallback onToggleTheme;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<LibraryItem>> _libraryFuture;
  late final TextEditingController _searchController;
  String _searchQuery = '';
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _libraryFuture = _loadLibrary();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery || !mounted) {
      return;
    }
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<List<LibraryItem>> _loadLibrary() async {
    final entries = await BookLibrary.loadCatalog();
    final preferences = await SharedPreferences.getInstance();
    final lastOpenedId = preferences.getString(ReaderProgress.lastOpenedKey);
    return entries
        .map(
          (entry) => LibraryItem(
            entry: entry,
            currentIndex:
                preferences.getInt(ReaderProgress.keyForId(entry.id)) ?? 0,
            isLastOpened: entry.id == lastOpenedId,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _openBook(LibraryEntry entry) async {
    await ReaderProgress.markLastOpened(entry.id);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => BookLoadingScreen(
          entry: entry,
          onToggleTheme: widget.onToggleTheme,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _libraryFuture = _loadLibrary();
      });
    }
  }

  Future<void> _deleteBook(LibraryEntry entry) async {
    if (entry.localPath == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this book?'),
        content: Text('“${entry.title}” will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await BookLibrary.deleteImportedBook(entry);
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(ReaderProgress.keyForId(entry.id));
      await ReaderProgress.clearLastOpenedIf(entry.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryFuture = _loadLibrary();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book removed from your library.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove this book: $error')),
        );
      }
    }
  }

  Future<void> _importBook() async {
    if (_isImporting) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt', 'md'],
      withData: true,
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final pickedFile = result.files.single;
      if (pickedFile.bytes == null && pickedFile.path == null) {
        throw const FormatException('The selected file could not be read.');
      }
      await BookLibrary.importFile(
        fileName: pickedFile.name,
        sourcePath: pickedFile.path,
        bytes: pickedFile.bytes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryFuture = _loadLibrary();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book added to your library.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import this file: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Broll',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          ThemeToggleButton(onPressed: widget.onToggleTheme),
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              key: const ValueKey('import-book-button'),
              tooltip: 'Import EPUB or text',
              onPressed: _importBook,
              icon: const Icon(Icons.upload_file_rounded),
            ),
        ],
      ),
      body: FutureBuilder<List<LibraryItem>>(
        future: _libraryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text('Could not load your library: ${snapshot.error}'),
            );
          }

          final items = snapshot.data!;
          final matchingItems = _searchQuery.isEmpty
              ? items
              : items
                    .where(
                      (item) =>
                          item.entry.title.toLowerCase().contains(_searchQuery),
                    )
                    .toList(growable: false);
          LibraryItem? continuedItem;
          if (_searchQuery.isEmpty) {
            for (final item in items) {
              if (item.isLastOpened) {
                continuedItem = item;
                break;
              }
            }
            final startedItems = items
                .where((item) => item.currentIndex > 0)
                .toList(growable: false);
            if (continuedItem == null && startedItems.isNotEmpty) {
              continuedItem = startedItems.first;
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Search your library',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              _ImportBookCta(isImporting: _isImporting, onTap: _importBook),
              if (continuedItem != null) ...[
                const SizedBox(height: 32),
                Text(
                  'Continue reading',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: .64),
                    fontWeight: FontWeight.w600,
                    letterSpacing: .1,
                  ),
                ),
                const SizedBox(height: 10),
                BookCard(
                  item: continuedItem,
                  eyebrow: 'Pick up where you left off',
                  onTap: () => _openBook(continuedItem!.entry),
                  onDelete: continuedItem.entry.localPath == null
                      ? null
                      : () => _deleteBook(continuedItem!.entry),
                ),
              ],
              const SizedBox(height: 32),
              Text(
                _searchQuery.isEmpty ? 'Your library' : 'Search results',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: .64),
                  fontWeight: FontWeight.w600,
                  letterSpacing: .1,
                ),
              ),
              const SizedBox(height: 10),
              if (matchingItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'Your library is empty.'
                        : 'No books match “${_searchController.text.trim()}”.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: .56),
                    ),
                  ),
                )
              else
                ...matchingItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BookCard(
                      item: item,
                      onTap: () => _openBook(item.entry),
                      onDelete: item.entry.localPath == null
                          ? null
                          : () => _deleteBook(item.entry),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ImportBookCta extends StatelessWidget {
  const _ImportBookCta({required this.isImporting, required this.onTap});

  final bool isImporting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rounded = BorderRadius.circular(20);
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: rounded,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('import-book-cta'),
        onTap: isImporting ? null : onTap,
        borderRadius: rounded,
        overlayColor: WidgetStatePropertyAll(
          colorScheme.onPrimaryContainer.withValues(alpha: .07),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: isImporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      )
                    : Icon(
                        Icons.upload_file_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add a book',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Import an EPUB or text file',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: .72,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 19,
                color: colorScheme.onPrimaryContainer.withValues(alpha: .72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreparedBook {
  const _PreparedBook({required this.book, required this.initialIndex});

  final Book book;
  final int initialIndex;
}

class BookLoadingScreen extends StatefulWidget {
  const BookLoadingScreen({
    required this.entry,
    required this.onToggleTheme,
    super.key,
  });

  final LibraryEntry entry;
  final VoidCallback onToggleTheme;

  @override
  State<BookLoadingScreen> createState() => _BookLoadingScreenState();
}

class _BookLoadingScreenState extends State<BookLoadingScreen> {
  static const _minimumLoaderVisible = Duration(seconds: 1);

  late final Future<_PreparedBook> _openFuture;
  late final Stopwatch _openingStopwatch;
  Timer? _minimumLoaderTimer;
  bool _readerReady = false;
  bool _readerPrepared = false;
  bool _openCompletionLogged = false;
  bool _timingsCallbackAttached = false;

  @override
  void initState() {
    super.initState();
    _openingStopwatch = Stopwatch()..start();
    _openingLog(
      'open-start title="${widget.entry.title}" '
      'expectedChunks=${widget.entry.totalChunks}',
    );
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    _timingsCallbackAttached = true;
    _openFuture = _prepareBook();
  }

  Future<_PreparedBook> _prepareBook() async {
    _openingLog('open-preparation start parallel=book-load+position-load');
    final results = await Future.wait<Object>([
      BookLibrary.loadBook(widget.entry),
      ReaderProgress.loadForId(widget.entry.id),
    ]);
    final book = results[0] as Book;
    final savedIndex = results[1] as int;
    final initialIndex = book.chunks.isEmpty
        ? 0
        : savedIndex.clamp(0, book.chunks.length - 1);
    _openingLog(
      'open-preparation complete savedIndex=$savedIndex '
      'initialIndex=$initialIndex chunks=${book.chunks.length} '
      'elapsedMs=${_openingStopwatch.elapsedMilliseconds}',
    );
    return _PreparedBook(book: book, initialIndex: initialIndex);
  }

  void _stopFrameTimings() {
    if (!_timingsCallbackAttached) {
      return;
    }
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timingsCallbackAttached = false;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (_readerReady) {
      return;
    }
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      if (totalMs >= 20) {
        _openingLog(
          'slow-frame totalMs=${totalMs.toStringAsFixed(1)} '
          'buildMs=${(timing.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
          'rasterMs=${(timing.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)}',
        );
      }
    }
  }

  void _showReader() {
    if (!mounted || _readerReady || _readerPrepared) {
      return;
    }
    _readerPrepared = true;
    final remaining = _minimumLoaderVisible - _openingStopwatch.elapsed;
    if (remaining > Duration.zero) {
      _openingLog(
        'reader-prepared holding-loader remainingMs=${remaining.inMilliseconds}',
      );
      _minimumLoaderTimer = Timer(remaining, _revealReader);
      return;
    }
    _revealReader();
  }

  void _revealReader() {
    if (!mounted || _readerReady) {
      return;
    }
    _openingStopwatch.stop();
    _openingLog(
      'open-ready elapsedMs=${_openingStopwatch.elapsedMilliseconds} '
      'loaderExit=reader-restored',
    );
    _stopFrameTimings();
    setState(() {
      _readerReady = true;
    });
  }

  @override
  void dispose() {
    _minimumLoaderTimer?.cancel();
    _stopFrameTimings();
    _openingStopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PreparedBook>(
      future: _openFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !_openCompletionLogged) {
          _openCompletionLogged = true;
          _openingLog(
            'open-future done hasData=${snapshot.hasData} '
            'hasError=${snapshot.hasError} '
            'elapsedMs=${_openingStopwatch.elapsedMilliseconds}',
          );
        }

        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasData)) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.entry.title),
              actions: [ThemeToggleButton(onPressed: widget.onToggleTheme)],
            ),
            body: Center(
              child: Text('Could not open this book: ${snapshot.error}'),
            ),
          );
        }

        final prepared = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: !_readerReady,
              child: prepared == null
                  ? const SizedBox.expand(
                      key: ValueKey('broll-reader-placeholder'),
                    )
                  : ReaderScreen(
                      book: prepared.book,
                      initialIndex: prepared.initialIndex,
                      onToggleTheme: widget.onToggleTheme,
                      onReady: _showReader,
                    ),
            ),
            IgnorePointer(
              ignoring: true,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final fade = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutCubic,
                  );
                  return FadeTransition(opacity: fade, child: child);
                },
                child: _readerReady
                    ? const SizedBox.expand(
                        key: ValueKey('broll-book-opening-empty'),
                      )
                    : BrollBookOpeningView(
                        key: const ValueKey('broll-book-opening-screen'),
                        title: widget.entry.title,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class BrollBookOpeningView extends StatefulWidget {
  const BrollBookOpeningView({required this.title, super.key});

  final String title;

  @override
  State<BrollBookOpeningView> createState() => _BrollBookOpeningViewState();
}

class _BrollBookOpeningViewState extends State<BrollBookOpeningView>
    with SingleTickerProviderStateMixin {
  static const _quotes = [
    'A good story changes the pace of a day.',
    'Find your place. Then keep going.',
    'A few quiet minutes can take you far.',
  ];

  late final AnimationController _motionController;
  late final Animation<double> _float;
  late final Animation<double> _scale;
  Timer? _quoteTimer;
  int _quoteIndex = 0;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    final motion = CurvedAnimation(
      parent: _motionController,
      curve: Curves.easeInOutCubic,
    );
    _float = Tween<double>(begin: -5, end: 5).animate(motion);
    _scale = Tween<double>(begin: .97, end: 1.02).animate(motion);
    _quoteTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _quoteIndex = (_quoteIndex + 1) % _quotes.length;
      });
    });
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('broll-book-opening-scaffold'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _motionController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _float.value),
                      child: Transform.scale(scale: _scale.value, child: child),
                    );
                  },
                  child: Container(
                    width: 152,
                    height: 152,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: .12),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: RepaintBoundary(
                      child: Image.asset(
                        'assets/branding/broll_logo.png',
                        cacheWidth: 512,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Opening your place',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: .62),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 44,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Text(
                      _quotes[_quoteIndex],
                      key: ValueKey(_quotes[_quoteIndex]),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.primary,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Finding your place…',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: .48),
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookCard extends StatelessWidget {
  const BookCard({
    required this.item,
    required this.onTap,
    this.eyebrow,
    this.onDelete,
    super.key,
  });

  final LibraryItem item;
  final VoidCallback onTap;
  final String? eyebrow;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = item.entry;
    final totalChunks = entry.totalChunks;
    final currentIndex = totalChunks == 0
        ? 0
        : item.currentIndex.clamp(0, totalChunks - 1);
    final progress = totalChunks == 0 ? 0.0 : (currentIndex + 1) / totalChunks;

    final rounded = BorderRadius.circular(22);
    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: rounded,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: rounded,
        overlayColor: WidgetStatePropertyAll(
          colorScheme.primary.withValues(alpha: .07),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: rounded,
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: .08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCover(
                asset: entry.coverAsset,
                path: entry.coverPath,
                title: entry.title,
                width: 68,
                height: 96,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: .58),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0).toDouble(),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          '${(progress * 100).round()}% read',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: .52),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: onDelete == null ? 26 : 38,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'Delete imported book',
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: colorScheme.onSurface.withValues(alpha: .52),
                        ),
                      ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: .42),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookCover extends StatelessWidget {
  const BookCover({
    this.asset,
    this.path,
    required this.title,
    this.width = 64,
    this.height = 84,
    super.key,
  });

  final String? asset;
  final String? path;
  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? '?' : title.trim()[0];
    final fallback = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Widget image;
    if (asset != null) {
      image = Image.asset(
        asset!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (path != null) {
      image = Image.file(
        File(path!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.book,
    required this.initialIndex,
    required this.onToggleTheme,
    this.onReady,
    super.key,
  });

  final Book book;
  final int initialIndex;
  final VoidCallback onToggleTheme;
  final VoidCallback? onReady;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  // Imported chunks target 20 words and are capped at 36. We estimate each
  // chunk's height from its word count so the visible gap stays consistent;
  // the prefix offsets keep restoration cheap without measuring every
  // paragraph on the UI isolate during book opening.
  static const _focusLineFraction = 0.40;
  static const _audioOperationTimeout = Duration(milliseconds: 500);
  static const _restoreRetryDelay = Duration(milliseconds: 16);
  static const _maxRestoreAttempts = 60;

  late final ScrollController _scrollController;
  late final AudioPlayer _focusClickPlayer;
  late final Future<void> _focusClickReady;
  late final List<_ChapterMarker> _chapterMarkers;
  late final List<int> _chunkWordCounts;
  late final List<double> _estimatedChunkOffsets;
  final GlobalKey _readerViewportKey = GlobalKey();
  final Map<int, BuildContext> _mountedChunkContexts = {};
  SharedPreferences? _preferences;
  Timer? _restoreRetryTimer;
  Future<void> _positionSaveQueue = Future<void>.value();
  int _currentIndex = 0;
  bool _focusUpdateScheduled = false;
  bool _restoreStarted = false;
  bool _restoreAttemptScheduled = false;
  bool _isRestoring = false;
  int _restoreAttempts = 0;
  bool _hasEstablishedFocus = false;
  bool _isDisposed = false;
  bool _readyNotified = false;
  Future<void> _clickPlayback = Future<void>.value();
  Stopwatch? _restoreStopwatch;
  bool _restoreFirstAttemptLogged = false;
  bool _restoreEstimatedJumpLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController()..addListener(_onScroll);
    _chapterMarkers = _buildChapterMarkers(widget.book);
    _chunkWordCounts = widget.book.chunks
        .map((chunk) => chunk.text.trim().split(RegExp(r'\s+')).length)
        .toList(growable: false);
    _estimatedChunkOffsets = _buildEstimatedChunkOffsets();
    _currentIndex = widget.book.chunks.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.book.chunks.length - 1);
    _openingLog(
      'reader-init title="${widget.book.title}" '
      'chunks=${widget.book.chunks.length} chapters=${_chapterMarkers.length} '
      'initialIndex=$_currentIndex',
    );
    _focusClickPlayer = AudioPlayer();
    _focusClickReady = _prepareFocusClickPlayer().timeout(
      _audioOperationTimeout,
      onTimeout: () {},
    );
  }

  Future<void> _prepareFocusClickPlayer() async {
    await _focusClickPlayer.setPlayerMode(PlayerMode.lowLatency);
    await _focusClickPlayer.setReleaseMode(ReleaseMode.stop);
  }

  static List<_ChapterMarker> _buildChapterMarkers(Book book) {
    final markers = <_ChapterMarker>[];
    String? previousChapter;
    for (var index = 0; index < book.chunks.length; index++) {
      final chapter = book.chunks[index].chapter;
      if (chapter != null && chapter != previousChapter) {
        markers.add(_ChapterMarker(title: chapter, index: index));
      }
      previousChapter = chapter;
    }
    return markers;
  }

  List<double> _buildEstimatedChunkOffsets() {
    final offsets = List<double>.filled(widget.book.chunks.length + 1, 0);
    for (var index = 0; index < widget.book.chunks.length; index++) {
      offsets[index + 1] = offsets[index] + _chunkExtentForIndex(index);
    }
    return offsets;
  }

  double _chunkExtentForIndex(int index) {
    final chunk = widget.book.chunks[index];
    final lineCount = math.max(1, (_chunkWordCounts[index] / 6).ceil());
    final chapterHeight = _startsChapterAt(index) && chunk.chapter != null
        ? 28.0
        : 0.0;
    // The 18dp remainder is the same visible gap after every text block.
    return (lineCount * 27.0 + chapterHeight + 18.0)
        .clamp(64.0, 280.0)
        .toDouble();
  }

  void _onScroll() {
    if (!_isRestoring) {
      _scheduleFocusUpdate();
    }
  }

  void _scheduleFocusUpdate() {
    if (_focusUpdateScheduled) {
      return;
    }

    _focusUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusUpdateScheduled = false;
      if (mounted && !_isRestoring) {
        _updateFocusedChunk();
      }
    });
  }

  void _updateFocusedChunk() {
    final viewportRenderObject = _readerViewportKey.currentContext
        ?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize) {
      return;
    }

    final viewportOrigin = viewportRenderObject.localToGlobal(Offset.zero);
    final viewportTop = viewportOrigin.dy;
    final viewportBottom = viewportTop + viewportRenderObject.size.height;
    final focusLine =
        viewportTop + viewportRenderObject.size.height * _focusLineFraction;
    var closestIndex = _currentIndex;
    var closestDistance = double.infinity;

    for (final entry in _mountedChunkContexts.entries) {
      final renderObject = entry.value.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached) {
        continue;
      }

      final origin = renderObject.localToGlobal(Offset.zero);
      final center = origin.dy + renderObject.size.height / 2;
      if (center < viewportTop - renderObject.size.height ||
          center > viewportBottom + renderObject.size.height) {
        continue;
      }

      final distance = (center - focusLine).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = entry.key;
      }
    }

    if (closestIndex == _currentIndex) {
      _hasEstablishedFocus = true;
      return;
    }

    final shouldPlayClick = _hasEstablishedFocus;
    _hasEstablishedFocus = true;
    setState(() {
      _currentIndex = closestIndex;
    });
    unawaited(_savePosition());
    if (shouldPlayClick) {
      _playFocusClick();
    }
  }

  void _playFocusClick() {
    _clickPlayback = _clickPlayback.then((_) => _playFocusClickSafely());
  }

  Future<void> _playFocusClickSafely() async {
    try {
      await _focusClickReady;
      if (_isDisposed) {
        return;
      }
      await _focusClickPlayer.stop().timeout(_audioOperationTimeout);
      await _focusClickPlayer
          .play(
            AssetSource('sounds/soft_click.wav'),
            volume: 0.10,
            mode: PlayerMode.lowLatency,
          )
          .timeout(_audioOperationTimeout);
    } catch (_) {
      // Audio feedback should never interfere with reading.
    }
  }

  void _onChunkMounted(int index, BuildContext chunkContext) {
    _mountedChunkContexts[index] = chunkContext;
    if (_isRestoring && index == _currentIndex) {
      _openingLog(
        'restore target-mounted index=$index attempts=$_restoreAttempts '
        'elapsedMs=${_restoreStopwatch?.elapsedMilliseconds ?? 0}',
      );
    }
    if (_isRestoring && index == _currentIndex) {
      _scheduleRestoreAttempt();
    }
  }

  void _onChunkUnmounted(int index, BuildContext chunkContext) {
    if (identical(_mountedChunkContexts[index], chunkContext)) {
      _mountedChunkContexts.remove(index);
    }
  }

  Future<void> _jumpToChunk(int index) async {
    if (widget.book.chunks.isEmpty) {
      return;
    }
    final targetIndex = index.clamp(0, widget.book.chunks.length - 1).toInt();
    if (mounted) {
      setState(() {
        _currentIndex = targetIndex;
      });
    }
    unawaited(_savePosition());

    final targetContext = _mountedChunkContexts[targetIndex];
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: _focusLineFraction,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final estimatedOffset = _estimatedChunkOffsets[targetIndex].clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(estimatedOffset.toDouble());
    }
    if (mounted) {
      _scheduleFocusUpdate();
    }
  }

  void _showChapterNavigation() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Chapters',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              ..._chapterMarkers.map(
                (marker) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(marker.title),
                  trailing: marker.index == _currentIndex
                      ? Icon(
                          Icons.bookmark_rounded,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_jumpToChunk(marker.index));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePosition() async {
    if (widget.book.chunks.isEmpty) {
      return;
    }

    final indexToSave = _currentIndex;
    _positionSaveQueue = _positionSaveQueue
        .then<void>((_) => _writePosition(indexToSave))
        .catchError((_) {});
    await _positionSaveQueue;
  }

  Future<void> _writePosition(int index) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await preferences.setInt(ReaderProgress.keyFor(widget.book), index);
  }

  void _restorePosition() {
    if (_restoreStarted) {
      return;
    }

    _restoreStarted = true;
    _isRestoring = true;
    _restoreAttempts = 0;
    _restoreStopwatch = Stopwatch()..start();
    _restoreFirstAttemptLogged = false;
    _restoreEstimatedJumpLogged = false;
    _openingLog('restore-start targetIndex=$_currentIndex');
    _scheduleRestoreAttempt();
  }

  void _scheduleRestoreAttempt() {
    if (!mounted || !_isRestoring || _restoreAttemptScheduled) {
      return;
    }

    _restoreAttemptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreAttemptScheduled = false;
      if (mounted && _isRestoring) {
        _attemptRestorePosition();
      }
    });
  }

  void _attemptRestorePosition() {
    if (!mounted || !_isRestoring) {
      return;
    }

    _restoreAttempts += 1;
    if (!_restoreFirstAttemptLogged) {
      _restoreFirstAttemptLogged = true;
      _openingLog(
        'restore-first-attempt hasClients=${_scrollController.hasClients} '
        'targetMounted=${_mountedChunkContexts.containsKey(_currentIndex)}',
      );
    }
    if (_restoreAttempts > _maxRestoreAttempts) {
      _openingLog(
        'restore-max-attempts reached=$_restoreAttempts '
        'elapsedMs=${_restoreStopwatch?.elapsedMilliseconds ?? 0}',
      );
      _finishRestoring();
      return;
    }

    if (!_scrollController.hasClients) {
      _restoreRetryTimer?.cancel();
      _restoreRetryTimer = Timer(_restoreRetryDelay, () {
        _restoreRetryTimer = null;
        if (mounted && _isRestoring) {
          WidgetsBinding.instance.scheduleFrame();
          _scheduleRestoreAttempt();
        }
      });
      return;
    }

    if (widget.book.chunks.isEmpty) {
      _finishRestoring();
      return;
    }

    final targetContext = _mountedChunkContexts[_currentIndex];
    final targetRenderObject = targetContext?.findRenderObject();
    final viewportRenderObject = _readerViewportKey.currentContext
        ?.findRenderObject();
    if (targetRenderObject is RenderBox &&
        targetRenderObject.hasSize &&
        targetRenderObject.attached &&
        viewportRenderObject is RenderBox &&
        viewportRenderObject.hasSize) {
      final targetOrigin = targetRenderObject.localToGlobal(Offset.zero);
      final viewportOrigin = viewportRenderObject.localToGlobal(Offset.zero);
      final targetCenter = targetOrigin.dy + targetRenderObject.size.height / 2;
      final focusLine =
          viewportOrigin.dy +
          viewportRenderObject.size.height * _focusLineFraction;
      final position = _scrollController.position;
      final estimatedOffset = (position.pixels + targetCenter - focusLine)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - estimatedOffset).abs() > 1) {
        _openingLog(
          'restore-measured-correction from=${position.pixels.toStringAsFixed(1)} '
          'to=${estimatedOffset.toStringAsFixed(1)} '
          'attempt=$_restoreAttempts',
        );
        _scrollController.jumpTo(estimatedOffset);
      }
      _finishRestoring();
      return;
    }

    final position = _scrollController.position;
    final estimatedOffset = _estimatedOffsetForIndex(_currentIndex, position);
    if ((position.pixels - estimatedOffset).abs() > 1) {
      if (!_restoreEstimatedJumpLogged) {
        _restoreEstimatedJumpLogged = true;
        _openingLog(
          'restore-estimated-jump from=${position.pixels.toStringAsFixed(1)} '
          'to=${estimatedOffset.toStringAsFixed(1)} '
          'targetIndex=$_currentIndex attempt=$_restoreAttempts',
        );
      }
      _scrollController.jumpTo(estimatedOffset);
    }

    _scheduleRestoreAttempt();
  }

  bool _startsChapterAt(int index) {
    if (index == 0) {
      return true;
    }
    return widget.book.chunks[index].chapter !=
        widget.book.chunks[index - 1].chapter;
  }

  double _estimatedOffsetForIndex(int index, ScrollPosition position) {
    final viewportRenderObject = _readerViewportKey.currentContext
        ?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize) {
      return _estimatedChunkOffsets[index]
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
    }

    final viewportHeight = viewportRenderObject.size.height;
    final targetTop = viewportHeight * 0.32 + _estimatedChunkOffsets[index];
    final targetCenter = targetTop + _chunkExtentForIndex(index) / 2;
    final focusLine = viewportHeight * _focusLineFraction;
    return (targetCenter - focusLine)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  void _finishRestoring() {
    if (!_isRestoring) {
      return;
    }
    _isRestoring = false;
    _restoreRetryTimer?.cancel();
    _restoreRetryTimer = null;
    _restoreStopwatch?.stop();
    _openingLog(
      'restore-complete targetIndex=$_currentIndex attempts=$_restoreAttempts '
      'elapsedMs=${_restoreStopwatch?.elapsedMilliseconds ?? 0} '
      'pixels=${_scrollController.hasClients ? _scrollController.position.pixels.toStringAsFixed(1) : 'none'}',
    );
    _scheduleFocusUpdate();
    _notifyReady();
  }

  void _notifyReady() {
    if (_readyNotified) {
      return;
    }
    _readyNotified = true;
    widget.onReady?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_savePosition());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_savePosition());
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _restoreRetryTimer?.cancel();
    _scrollController.dispose();
    unawaited(_focusClickPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    _restorePosition();
    final progress = book.chunks.isEmpty
        ? 0.0
        : (_currentIndex + 1) / book.chunks.length;
    final currentChunk = book.chunks.isEmpty
        ? null
        : book.chunks[_currentIndex.clamp(0, book.chunks.length - 1).toInt()];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
        actions: [
          if (_chapterMarkers.isNotEmpty)
            IconButton(
              key: const ValueKey('chapter-navigation-button'),
              tooltip: 'Browse chapters',
              onPressed: _showChapterNavigation,
              icon: const Icon(Icons.list_alt_rounded),
            ),
          ThemeToggleButton(onPressed: widget.onToggleTheme),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: .08),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        key: const ValueKey('book-progress'),
                        value: progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_currentIndex + 1} / ${book.chunks.length}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: .64),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (currentChunk?.chapter != null || currentChunk?.page != null)
            Padding(
              key: const ValueKey('reader-metadata'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  if (currentChunk?.chapter != null)
                    Expanded(
                      child: Text(
                        currentChunk!.chapter!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .1,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (currentChunk?.page != null)
                    Text(
                      '${book.pageLabel ?? 'Page'} ${currentChunk!.page}'
                      '${book.pageCount == null ? '' : ' / ${book.pageCount}'}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: .58),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final focusPadding = constraints.maxHeight * 0.32;
                return SizedBox(
                  key: _readerViewportKey,
                  width: double.infinity,
                  child: ListView.builder(
                    key: const ValueKey('reader-scroll-view'),
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      focusPadding,
                      16,
                      focusPadding,
                    ),
                    itemCount: book.chunks.length,
                    itemExtentBuilder: (index, _) =>
                        _chunkExtentForIndex(index),
                    itemBuilder: (context, index) {
                      final chunk = book.chunks[index];

                      return ReaderChunk(
                        key: ValueKey('reader-chunk-$index'),
                        index: index,
                        chunk: chunk,
                        startsChapter: _startsChapterAt(index),
                        isFocused: index == _currentIndex,
                        onMounted: _onChunkMounted,
                        onUnmounted: _onChunkUnmounted,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterMarker {
  const _ChapterMarker({required this.title, required this.index});

  final String title;
  final int index;
}

class ReaderChunk extends StatefulWidget {
  const ReaderChunk({
    required this.index,
    required this.chunk,
    required this.startsChapter,
    required this.isFocused,
    required this.onMounted,
    required this.onUnmounted,
    super.key,
  });

  final int index;
  final BookChunk chunk;
  final bool startsChapter;
  final bool isFocused;
  final void Function(int index, BuildContext context) onMounted;
  final void Function(int index, BuildContext context) onUnmounted;

  @override
  State<ReaderChunk> createState() => _ReaderChunkState();
}

class _ReaderChunkState extends State<ReaderChunk> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onMounted(widget.index, context);
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.index, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: AnimatedOpacity(
        key: ValueKey('reader-focus-${widget.index}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: widget.isFocused ? 1 : 0.32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.startsChapter && widget.chunk.chapter != null) ...[
              Text(
                widget.chunk.chapter!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: -.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              widget.chunk.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                height: 1.5,
                fontWeight: FontWeight.normal,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
