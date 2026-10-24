
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'dart:io';

import '../main.dart';
import '../tglogs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: makes system UI match true-black style.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const GoPkgsApp());
}

class GoPkgsApp extends StatelessWidget {
  const GoPkgsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF000000);
    const surface = Color(0xFF0B0B0F);
    const surface2 = Color(0xFF111118);
    const border = Color(0xFF24242C);
    const accent = Color(0xFF7C4DFF); // premium violet accent
    const accent2 = Color(0xFF00E5FF); // cyan hint (used subtly)
     final base = ThemeData(
     brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        surfaceContainerHighest: surface2,
        primary: accent,
        secondary: accent2,
        outline: border,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1C1C24),
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: Color(0xFF9A9AAA)),
        labelStyle: const TextStyle(color: Color(0xFFEDEDF5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF111118),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 15, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, height: 1.35),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2),
      bodyLarge: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w500, height: 1.45),
      bodyMedium: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.45),
      labelLarge: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
      labelMedium: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2),
    );

    final theme = base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        titleTextStyle: textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
    

    return MaterialApp(
         

      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const GoPackageSearchPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. DATA MODEL (Updated for Python)
// ---------------------------------------------------------------------------
enum PkgSource {
  go,
  dart,
  python, // Added Python
  rust,
}

class PackageModel {
  final String name;
  final String urlPath;
  final String synopsis;
  final String info; // Composite info string
  final PkgSource source;
  final String? host;
  final String? owner;
  final String? repo;
  final int? imports;
  final String? version;
  final String? published;
  final String? license;
  final String? command;
  final List<String> alerts;
  final List<String> subPackages;
  final Map<String, String> meta;

  PackageModel({
    required this.name,
    required this.urlPath,
    required this.synopsis,
    required this.info,
    required this.source,
    this.host,
    this.owner,
    this.repo,
    this.imports,
    this.version,
    this.published,
    this.license,
    this.command,
    this.alerts = const [],
    this.subPackages = const [],
    this.meta = const {},
  });
}

// ---------------------------------------------------------------------------
// Helpers (quality UX)
// ---------------------------------------------------------------------------
void _hapticLight() {
  // Good haptics across platforms; vibrate on Android.
  HapticFeedback.lightImpact();
  if (Platform.isAndroid) {
    // A bit stronger for Android touch feel.
    HapticFeedback.selectionClick();
  }
}

EdgeInsets _adaptivePagePadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final horizontal = w >= 900 ? 24.0 : 16.0;
  return EdgeInsets.fromLTRB(horizontal, 12, horizontal, 16);
}

double _contentMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1200) return 960;
  if (w >= 900) return 820;
  return w;
}

class _GlassChip extends StatelessWidget {
  final Widget child;
  const _GlassChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101018),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF24242C)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFFB9B9C8)),
          child: child,
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double widthFactor;
  final double height;
  const _SkeletonLine({this.widthFactor = 1, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF12121A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1F1F2A)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. SEARCH PAGE

class GoPackageSearchPage extends StatefulWidget {
  const GoPackageSearchPage({super.key});

  @override
  State<GoPackageSearchPage> createState() => _GoPackageSearchPageState();
}

class _GoPackageSearchPageState extends State<GoPackageSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // State
  List<PackageModel> _packages = [];
  bool _isLoading = false;
  PkgSource _currentSource = PkgSource.go; // Default

  Future<void> searchPackages(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    _hapticLight();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _packages = [];
    });

    try {
      if (_currentSource == PkgSource.go) {
        await _searchGoDev(q);
      } else if (_currentSource == PkgSource.dart) {
        await _searchPubDev(q);
      } else if (_currentSource == PkgSource.python) {
        await _searchPyPi(q);
      } else if (_currentSource == PkgSource.rust) {
        await _searchCratesIo(q);
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- GO SEARCH LOGIC ---
  Future<void> _searchGoDev(String q) async {
    final url = Uri.parse('https://pkg.go.dev/search?q=$q');
    final response = await http.get(url);
    if (response.statusCode != 200) throw 'Network error: ${response.statusCode}';

    final soup = BeautifulSoup(response.body);
    final headerContainers = soup.findAll('div', class_: 'SearchSnippet-headerContainer');
    final List<PackageModel> foundPackages = [];

    for (var headerDiv in headerContainers) {
      final linkTag = headerDiv.find('h2')?.find('a');
      if (linkTag == null) continue;

      final name = linkTag.text.trim();
      final link = linkTag.attributes['href'] ?? '';
      final relativePath = link.replaceFirst(RegExp(r'^/'), '');
      final pathParts = relativePath.split('/');
      final host = pathParts.isNotEmpty ? pathParts.first : null;
      final owner = pathParts.length > 1 ? pathParts[1] : null;
      final repo = pathParts.length > 2 ? pathParts[2] : null;
      final parentBox = headerDiv.parent;

      String desc = '';
      String infoText = '';
      String? version;
      String? published;
      String? license;
      int? importedBy;
      String? command;
      List<String> alerts = [];
      List<String> subPackages = [];

      if (parentBox != null) {
        desc = parentBox.find('p', class_: 'SearchSnippet-synopsis')?.text.trim() ?? '';
        infoText = parentBox
                .find('div', class_: 'SearchSnippet-infoLabel')
                ?.getText()
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim() ??
            '';

        // Extract imported-by count
        final importedMatch = RegExp(r'Imported by\s+([\d,]+)').firstMatch(infoText);
        if (importedMatch != null) {
          importedBy = int.tryParse(importedMatch.group(1)!.replaceAll(',', ''));
        }

        // Extract version and published date (version ... (date))
        final versionMatch = RegExp(r'(v[\w\.\-\+]+)').firstMatch(infoText);
        if (versionMatch != null) version = versionMatch.group(1);
        final dateMatch = RegExp(r'\(([^)]+)\)').firstMatch(infoText);
        if (dateMatch != null) published = dateMatch.group(1);

        // Extract license
        final licenseMatch = RegExp(r'License\s+([^\s]+)').firstMatch(infoText);
        if (licenseMatch != null) license = licenseMatch.group(1);

        // Chips: vulnerabilities / commands
        final chipDivs = parentBox.findAll('div');
        for (final chip in chipDivs) {
          final cls = chip.attributes['class'] ?? '';
          if (cls.contains('go-Chip--alert')) {
            final text = chip.text.trim();
            if (text.isNotEmpty) alerts.add(text);
          } else if (cls.contains('go-Chip--inverted')) {
            final text = chip.text.trim();
            if (text.isNotEmpty) command = text;
          }
        }

        // Sub packages (other packages row)
        final subDiv = parentBox.find('div', class_: 'SearchSnippet-sub');
        if (subDiv != null) {
          final links = subDiv.findAll('a');
          for (final a in links) {
            final txt = a.text.trim();
            if (txt.isNotEmpty) subPackages.add(txt);
          }
        }
      }

      foundPackages.add(PackageModel(
        name: name,
        urlPath: link,
        synopsis: desc,
        info: infoText,
        source: PkgSource.go,
        host: host,
        owner: owner,
        repo: repo,
        imports: importedBy,
        version: version,
        published: published,
        license: license,
        command: command,
        alerts: alerts,
        subPackages: subPackages,
      ));
    }
    setState(() => _packages = foundPackages);
  }

  // --- DART (PUB.DEV) SEARCH LOGIC ---
  Future<void> _searchPubDev(String q) async {
    final url = Uri.parse('https://pub.dev/packages?q=$q');
    final response = await http.get(url);
    if (response.statusCode != 200) throw 'Network error: ${response.statusCode}';

    final soup = BeautifulSoup(response.body);
    final items = soup.findAll('div', class_: 'packages-item');
    final List<PackageModel> foundPackages = [];

    for (var item in items) {
      final titleTag = item.find('h3', class_: 'packages-title')?.find('a');
      final name = titleTag?.text.trim() ?? 'Unknown';
      final link = titleTag?.attributes['href'] ?? '';
      final desc = item.find('div', class_: 'packages-description')?.text.trim() ?? '';
      
      final metaBlock = item.find('p', class_: 'packages-metadata');
      final version = metaBlock?.find('span', class_: 'packages-metadata-block')?.find('a')?.text ?? '?';
      final timeAgo = metaBlock?.find('a', class_: '-x-ago')?.text ?? '';

      final likes = item.find('div', class_: 'packages-score-like')?.find('span', class_: 'packages-score-value-number')?.text ?? '0';
      final points = item.find('div', class_: 'packages-score-health')?.find('span', class_: 'packages-score-value-number')?.text ?? '0';
      
      final infoStr = "v$version • $timeAgo • 👍 $likes • $points pts";

      foundPackages.add(PackageModel(
        name: name,
        urlPath: link,
        synopsis: desc,
        info: infoStr,
        source: PkgSource.dart,
      ));
    }
    setState(() => _packages = foundPackages);
  }

  // --- PYTHON (PYPI) SEARCH LOGIC ---
  Future<void> _searchPyPi(String q) async {
    final url = Uri.parse('https://pypi.org/search/?q=$q');

    // FIX: Add a User-Agent header so PyPI thinks we are a browser
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    };

    final response = await http.get(url, headers: headers);

    sendTelegramLog('PyPI Search Status: ${response.statusCode}');

    if (response.statusCode != 200) throw 'Network error: ${response.statusCode}';

    final soup = BeautifulSoup(response.body);

    // FIX: PyPI often returns result items with class "package-snippet"
    final items = soup.findAll('a', class_: 'package-snippet');
    
    sendTelegramLog('PyPI Found Items count: ${items.length}');

    final List<PackageModel> foundPackages = [];

    for (var item in items) {
      // 1. Name & Link
      final name = item.find('span', class_: 'package-snippet__name')?.text.trim() ?? 'Unknown';
      final link = item.attributes['href'] ?? '';

      // 2. Description
      final desc = item.find('p', class_: 'package-snippet__description')?.text.trim() ?? '';

      // 3. Date
      final date = item.find('span', class_: 'package-snippet__created')?.find('time')?.text.trim() ?? '';

      // PyPI doesn't show likes/scores on search results, so we just show date
      final infoStr = "Updated: $date";

      foundPackages.add(PackageModel(
        name: name,
        urlPath: link, // e.g., /project/autogui/
        synopsis: desc,
        info: infoStr,
        source: PkgSource.python,
      ));
    }
    setState(() => _packages = foundPackages);
  }

  // --- RUST (CRATES.IO) SEARCH LOGIC ---
  Future<void> _searchCratesIo(String q) async {
    final url = Uri.parse('https://crates.io/search?q=$q');
    final response = await http.get(url);
    if (response.statusCode != 200) throw 'Network error: ${response.statusCode}';

    final soup = BeautifulSoup(response.body);
    final items = soup.findAll('li').where((li) {
      final cls = li.attributes['class'] ?? '';
      return cls.contains('crate-row');
    }).toList();

    final List<PackageModel> crates = [];

    Bs4Element? firstTagWithClass(Bs4Element root, String tag, String key) {
      for (final el in root.findAll(tag)) {
        final cls = el.attributes['class'] ?? '';
        if (cls.contains(key)) return el;
      }
      return null;
    }

    for (final item in items) {
      final row = item;
      final nameTag = firstTagWithClass(row, 'a', 'name');
      final versionTag = firstTagWithClass(row, 'span', 'version');
      final descTag = firstTagWithClass(row, 'div', 'description');

      final name = nameTag?.text.trim() ?? 'Unknown';
      final link = nameTag?.attributes['href'] ?? '';
      final version = versionTag?.text.trim();
      final synopsis = descTag?.text.trim() ?? '';

      String? allTime;
      String? recent;
      String? updated;

      for (final stat in row.findAll('*')) {
        final cls = stat.attributes['class'] ?? '';
        if (cls.contains('downloads') && !cls.contains('recent')) {
          allTime ??= stat.text.trim();
        } else if (cls.contains('recent-downloads')) {
          recent ??= stat.text.trim();
        } else if (cls.contains('updated-at')) {
          updated ??= stat.text.trim();
        }
      }

      final infoParts = <String>[];
      if (version != null && version.isNotEmpty) infoParts.add(version);
      if (allTime != null && allTime.isNotEmpty) infoParts.add('All-time: $allTime');
      if (recent != null && recent.isNotEmpty) infoParts.add('Recent: $recent');
      if (updated != null && updated.isNotEmpty) infoParts.add(updated);

      crates.add(PackageModel(
        name: name,
        urlPath: link,
        synopsis: synopsis,
        info: infoParts.join(' • '),
        source: PkgSource.rust,
        host: 'crates.io',
        version: version,
        published: updated,
        meta: {
          if (allTime != null) 'all_time': allTime,
          if (recent != null) 'recent': recent,
        },
      ));
    }

    setState(() => _packages = crates);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = _adaptivePagePadding(context);
    final maxW = _contentMaxWidth(context);

    // Dynamic Hint Text
    String hint = 'Search packages...';
    if (_currentSource == PkgSource.go) hint = 'Search Go (e.g., fiber)';
    if (_currentSource == PkgSource.dart) hint = 'Search Dart (e.g., dio)';
    if (_currentSource == PkgSource.python) hint = 'Search PyPI (e.g., pandas)';
    if (_currentSource == PkgSource.rust) hint = 'Search Rust crates (e.g., easytier)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Package Hunter'),
           leading: IconButton(
             icon: const Icon(Icons.arrow_back),
             onPressed: () {
                        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GitLoaderApp(),
          ),
        );// This pops the screen and goes back
             },
           ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _GlassChip(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 14, color: Color(0xFFCAB8FF)),
                  const SizedBox(width: 6),
                  Text('Black UI', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFFCAB8FF))),
                ],
              ),
            ),
          )
        ],
        bottom: _isLoading
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(
            children: [
              // --- LANGUAGE SELECTOR ---
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 10),
                child: Row(
                  children: [
                    _SourceChip(
                      label: 'Go',
                      isSelected: _currentSource == PkgSource.go,
                      onTap: () => setState(() => _currentSource = PkgSource.go),
                    ),
                    const SizedBox(width: 10),
                    _SourceChip(
                      label: 'Dart',
                      isSelected: _currentSource == PkgSource.dart,
                      onTap: () => setState(() => _currentSource = PkgSource.dart),
                    ),
                    const SizedBox(width: 10),
                    _SourceChip(
                      label: 'Python',
                      isSelected: _currentSource == PkgSource.python,
                      onTap: () => setState(() => _currentSource = PkgSource.python),
                    ),
                    const SizedBox(width: 10),
                    _SourceChip(
                      label: 'Rust',
                      isSelected: _currentSource == PkgSource.rust,
                      onTap: () => setState(() => _currentSource = PkgSource.rust),
                    ),
                  ],
                ),
              ),

              // --- SEARCH BAR ---
              Padding(
                padding: pad.copyWith(top: 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.search,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: hint,
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _hapticLight();
                                    setState(() => _controller.clear());
                                    _focusNode.requestFocus();
                                  },
                                ),
                        ),
                        onSubmitted: searchPackages,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : () => searchPackages(_controller.text),
                      child: const Text('Search'),
                    ),
                  ],
                ),
              ),

              // --- RESULTS ---
              Expanded(
                child: _isLoading
                    ? const _SearchSkeleton()
                    : _packages.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(22),
                            child: Center(
                              child: Text(
                                'Select a language and search to see results.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFFB4B4C4),
                                    ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
                            itemCount: _packages.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final pkg = _packages[index];
                              return _PackageCard(
                                pkg: pkg,
                                onTap: () {
                                  _hapticLight();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PackageDetailPage(package: pkg),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Updated PackageCard to handle Python styling
class _PackageCard extends StatelessWidget {
  final PackageModel pkg;
  final VoidCallback onTap;

  const _PackageCard({required this.pkg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB9B9C8),
        );
    final infoStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF8F8FA3),
        );

    // Identify source icon & color
    IconData srcIcon;
    Color srcColor;
    
    switch (pkg.source) {
      case PkgSource.dart:
        srcIcon = Icons.flutter_dash;
        srcColor = const Color(0xFF00E5FF);
        break;
      case PkgSource.python:
        srcIcon = Icons.terminal; // Used for Python
        srcColor = const Color(0xFF3776AB); // Python Blue
        break;
      case PkgSource.go:
        srcIcon = Icons.api;
        srcColor = const Color(0xFF7C4DFF);
        break;
      case PkgSource.rust:
        srcIcon = Icons.memory_rounded;
        srcColor = const Color(0xFFFF7043); // Rust-ish accent
        break;
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(srcIcon, size: 16, color: srcColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pkg.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF8F8FA3)),
                ],
              ),
              const SizedBox(height: 6),
              if (pkg.source == PkgSource.go)
                Text(
                  pkg.urlPath.replaceFirst(RegExp(r'^/'), ''),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFF8F8FA3)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (pkg.source == PkgSource.go) const SizedBox(height: 8),
              if (pkg.synopsis.isNotEmpty)
                Text(pkg.synopsis, style: subtitleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (pkg.synopsis.isNotEmpty) const SizedBox(height: 10),
              if (pkg.source == PkgSource.go) ...[
                if (pkg.alerts.isNotEmpty || (pkg.command?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ...pkg.alerts
                            .map((a) => _GlassChip(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded,
                                          size: 14, color: Color(0xFFFFB74D)),
                                      const SizedBox(width: 6),
                                      Text(a,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(color: Colors.white)),
                                    ],
                                  ),
                                )),
                        if (pkg.command != null && pkg.command!.isNotEmpty)
                          _GlassChip(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.code_rounded,
                                    size: 14, color: Color(0xFFB9B9C8)),
                                const SizedBox(width: 6),
                                Text(pkg.command!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: Colors.white)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                _GoMetaInfo(pkg: pkg, infoStyle: infoStyle),
              ] else if (pkg.source == PkgSource.rust) ...[
                if (pkg.info.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      pkg.info,
                      style: infoStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                _RustMetaInfo(pkg: pkg, infoStyle: infoStyle),
              ] else ...[
                if (pkg.info.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF8F8FA3)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(pkg.info, style: infoStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoMetaInfo extends StatelessWidget {
  final PackageModel pkg;
  final TextStyle? infoStyle;
  const _GoMetaInfo({required this.pkg, this.infoStyle});

  Widget _metaRow(IconData icon, String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8F8FA3)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: infoStyle ?? Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFF8F8FA3)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = [];

    final hostOwner = [
      if (pkg.host != null && pkg.host!.isNotEmpty) pkg.host,
      if (pkg.owner != null && pkg.owner!.isNotEmpty) pkg.owner,
      if (pkg.repo != null && pkg.repo!.isNotEmpty) pkg.repo,
    ].whereType<String>().join(' / ');
    if (hostOwner.isNotEmpty) {
      rows.add(_metaRow(Icons.link_rounded, hostOwner, context));
    }

    if (pkg.imports != null) {
      rows.add(_metaRow(Icons.import_export, "Imported by ${pkg.imports}", context));
    }

    final versionBits = [
      if (pkg.version != null && pkg.version!.isNotEmpty) pkg.version,
      if (pkg.published != null && pkg.published!.isNotEmpty) "(${pkg.published})",
    ].whereType<String>().join(' ');
    if (versionBits.isNotEmpty) {
      rows.add(_metaRow(Icons.update_rounded, versionBits, context));
    }

    if (pkg.license != null && pkg.license!.isNotEmpty) {
      rows.add(_metaRow(Icons.gavel_rounded, "License: ${pkg.license}", context));
    }

    if (pkg.subPackages.isNotEmpty) {
      rows.add(
        _metaRow(
          Icons.apps_rounded,
          "Also see: ${pkg.subPackages.take(4).join(', ')}",
          context,
        ),
      );
    }

    if (rows.isEmpty && pkg.info.isNotEmpty) {
      rows.add(_metaRow(Icons.info_outline_rounded, pkg.info, context));
    }

    return Column(children: rows);
  }
}

class _RustMetaInfo extends StatelessWidget {
  final PackageModel pkg;
  final TextStyle? infoStyle;
  const _RustMetaInfo({required this.pkg, this.infoStyle});

  Widget _row(IconData icon, String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8F8FA3)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: infoStyle ?? Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFF8F8FA3)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    final path = pkg.urlPath.replaceFirst(RegExp(r'^/'), '');
    if (path.isNotEmpty) rows.add(_row(Icons.link_rounded, path, context));

    if (pkg.version != null && pkg.version!.isNotEmpty) {
      rows.add(_row(Icons.update_rounded, "Version: ${pkg.version}", context));
    }

    final allTime = pkg.meta['all_time'];
    if (allTime != null && allTime.isNotEmpty) {
      rows.add(_row(Icons.download_rounded, "All-time downloads: $allTime", context));
    }

    final recent = pkg.meta['recent'];
    if (recent != null && recent.isNotEmpty) {
      rows.add(_row(Icons.trending_up_rounded, "Recent: $recent", context));
    }

    if (pkg.published != null && pkg.published!.isNotEmpty) {
      rows.add(_row(Icons.history_rounded, "Updated: ${pkg.published}", context));
    }

    return Column(children: rows);
  }
}

// Helper Widget for the Language Buttons
class _SourceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SourceChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.primary : const Color(0xFF1F1F2A);
    final textColor = isSelected ? Colors.white : const Color(0xFF8F8FA3);

    return InkWell(
      onTap: () {
        _hapticLight();
        onTap();
      },
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFF24242C),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// // Updated PackageCard to accept PackageModel
// class _PackageCard extends StatelessWidget {
//   final PackageModel pkg;
//   final VoidCallback onTap;

//   const _PackageCard({required this.pkg, required this.onTap});

//   @override
//   Widget build(BuildContext context) {
//     final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
//           color: Colors.white,
//           fontWeight: FontWeight.w800,
//           letterSpacing: 0.1,
//         );
//     final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
//           color: const Color(0xFFB9B9C8),
//         );
//     final infoStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
//           color: const Color(0xFF8F8FA3),
//         );

//     // Identify source icon
//     IconData srcIcon;
//     Color srcColor;
//     if (pkg.source == PkgSource.dart) {
//       srcIcon = Icons.flutter_dash;
//       srcColor = const Color(0xFF00E5FF);
//     } else {
//       srcIcon = Icons.api; // generic for Go
//       srcColor = const Color(0xFF7C4DFF);
//     }

//     return Card(
//       child: InkWell(
//         borderRadius: BorderRadius.circular(16),
//         onTap: onTap,
//         child: Padding(
//           padding: const EdgeInsets.all(14),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(srcIcon, size: 16, color: srcColor),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       pkg.name,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: titleStyle,
//                     ),
//                   ),
//                   const SizedBox(width: 10),
//                   const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF8F8FA3)),
//                 ],
//               ),
//               const SizedBox(height: 8),
//               if (pkg.synopsis.isNotEmpty)
//                 Text(pkg.synopsis, style: subtitleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
//               if (pkg.synopsis.isNotEmpty) const SizedBox(height: 10),
//               if (pkg.info.isNotEmpty)
//                 Row(
//                   children: [
//                     const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF8F8FA3)),
//                     const SizedBox(width: 6),
//                     Expanded(
//                       child: Text(pkg.info, style: infoStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
//                     ),
//                   ],
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: _adaptivePagePadding(context),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonLine(widthFactor: 0.55, height: 14),
                SizedBox(height: 10),
                _SkeletonLine(widthFactor: 1, height: 12),
                SizedBox(height: 8),
                _SkeletonLine(widthFactor: 0.92, height: 12),
                SizedBox(height: 10),
                _SkeletonLine(widthFactor: 0.45, height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

// class _PackageCard extends StatelessWidget {
//   final GoPackage pkg;
//   final VoidCallback onTap;

//   const _PackageCard({required this.pkg, required this.onTap});

//   @override
//   Widget build(BuildContext context) {
//     final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
//           color: Colors.white,
//           fontWeight: FontWeight.w800,
//           letterSpacing: 0.1,
//         );
//     final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
//           color: const Color(0xFFB9B9C8),
//         );
//     final infoStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
//           color: const Color(0xFF8F8FA3),
//         );

//     return Card(
//       child: InkWell(
//         borderRadius: BorderRadius.circular(16),
//         onTap: onTap,
//         child: Padding(
//           padding: const EdgeInsets.all(14),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Expanded(
//                     child: Text(
//                       pkg.name,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: titleStyle,
//                     ),
//                   ),
//                   const SizedBox(width: 10),
//                   const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF8F8FA3)),
//                 ],
//               ),
//               const SizedBox(height: 8),
//               if (pkg.synopsis.isNotEmpty)
//                 Text(pkg.synopsis, style: subtitleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
//               if (pkg.synopsis.isNotEmpty) const SizedBox(height: 10),
//               if (pkg.info.isNotEmpty)
//                 Row(
//                   children: [
//                     const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF8F8FA3)),
//                     const SizedBox(width: 6),
//                     Expanded(
//                       child: Text(pkg.info, style: infoStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
//                     ),
//                   ],
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// ---------------------------------------------------------------------------
// 3. DETAIL PAGE
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 3. DETAIL PAGE
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 3. DETAIL PAGE
// ---------------------------------------------------------------------------
class PackageDetailPage extends StatefulWidget {
  final PackageModel package;
  const PackageDetailPage({super.key, required this.package});

  @override
  State<PackageDetailPage> createState() => _PackageDetailPageState();
}

class _PackageDetailPageState extends State<PackageDetailPage> {
  String _htmlContent = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPageContent();
  }

  Future<void> fetchPageContent() async {
    if (widget.package.source == PkgSource.go) {
      await _fetchGoContent();
    } else if (widget.package.source == PkgSource.dart) {
      await _fetchDartContent();
    } else if (widget.package.source == PkgSource.python) {
      await _fetchPyPiContent();
    } else if (widget.package.source == PkgSource.rust) {
      await _fetchCrateContent();
    }
  }

  Future<void> _fetchGoContent() async {
    try {
      final url = Uri.parse('https://pkg.go.dev${widget.package.urlPath}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final soup = BeautifulSoup(response.body);

        var readmeHtml = "";
        final readmeDiv = soup.find('div', class_: 'UnitReadme-content') ??
            soup.find('div', class_: 'js-readmeContent');
        if (readmeDiv != null) readmeHtml = readmeDiv.outerHtml;

        var docHtml = "";
        final docDiv = soup.find('div', class_: 'UnitDoc');
        if (docDiv != null) docHtml = docDiv.outerHtml;

        final finalHtml = (readmeHtml.isEmpty && docHtml.isEmpty)
            ? "<p>No documentation found.</p>"
            : "$readmeHtml <br><br><hr><br><br> $docHtml";

        setState(() {
          _htmlContent = finalHtml;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      sendTelegramLog("Error fetching Go details: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDartContent() async {
    try {
      final url = Uri.parse('https://pub.dev${widget.package.urlPath}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final soup = BeautifulSoup(response.body);

        final readmeSection = soup.find('section', class_: 'detail-tab-readme-content');
        
        final content = readmeSection?.outerHtml 
            ?? soup.find('div', class_: 'markdown-body')?.outerHtml 
            ?? "<p>No Readme found for this package.</p>";

        setState(() {
          _htmlContent = content;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      sendTelegramLog("Error fetching Dart details: $e");
      setState(() => _isLoading = false);
    }
  }

// --- PYTHON CONTENT FETCHING ---
  Future<void> _fetchPyPiContent() async {
    try {
      final url = Uri.parse('https://pypi.org${widget.package.urlPath}');

      // FIX: Add User-Agent here as well
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final soup = BeautifulSoup(response.body);

        // 1. Get Install Command
        final pipCmd = soup.find('span', id: 'pip-command')?.text.trim();

        // 2. Get Description
        final descDiv = soup.find('div', class_: 'project-description');
        String content = descDiv?.outerHtml ?? "<p>No description found.</p>";

        // Prepend install command if found
        if (pipCmd != null) {
          content = """
            <h3>Installation</h3>
            <pre><code>$pipCmd</code></pre>
            <hr>
            $content
          """;
        }

        setState(() {
          _htmlContent = content;
          _isLoading = false;
        });
      } else {
        sendTelegramLog('PyPI Detail Error: Status ${response.statusCode}');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      sendTelegramLog("Error fetching Python details: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCrateContent() async {
    try {
      final url = Uri.parse('https://crates.io${widget.package.urlPath}');
      final response = await http.get(url);
      if (response.statusCode != 200) {
        setState(() => _isLoading = false);
        return;
      }

      final soup = BeautifulSoup(response.body);
      // Try to locate readme article
      Bs4Element? readme;
      for (final el in soup.findAll('article')) {
        final cls = el.attributes['class'] ?? '';
        if (cls.contains('readme')) {
          readme = el;
          break;
        }
      }
      readme ??= soup.find('div', class_: 'readme');

      final content = readme?.outerHtml ?? "<p>No readme found.</p>";

      setState(() {
        _htmlContent = content;
        _isLoading = false;
      });
    } catch (e) {
      sendTelegramLog("Error fetching Rust crate details: $e");
      setState(() => _isLoading = false);
    }
  }
  Future<void> exportMarkdownWindowsSafe() async {
    final html = _htmlContent.trim();
    if (html.isEmpty) return;

    final md = html2md.convert(html);
    final suggestedName = '${widget.package.name.replaceAll("/", "_")}.md';

    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Markdown', extensions: ['md']),
          XTypeGroup(label: 'Text', extensions: ['txt']),
        ],
      );

      if (location == null) return; 

      final xfile = XFile.fromData(
        utf8.encode(md),
        mimeType: 'text/markdown',
        name: suggestedName,
      );

      await xfile.saveTo(location.path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: ${location.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = _adaptivePagePadding(context);
    final maxW = _contentMaxWidth(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.package.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Export Markdown',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _isLoading ? null : exportMarkdownWindowsSafe,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: SingleChildScrollView(
                  padding: pad,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: HtmlWidget(
                        _htmlContent,
                        textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFFEDEDF5),
                              letterSpacing: 0.1,
                            ),
                        customStylesBuilder: (element) {
                          switch (element.localName) {
                            case 'a':
                              return {'color': '#C7B3FF', 'text-decoration': 'none'};
                            case 'p':
                              return {'margin': '10px 0', 'line-height': '1.6'};
                            case 'li':
                              return {'margin': '6px 0', 'line-height': '1.6'};
                            case 'h1':
                              return {
                                'font-size': '22px',
                                'font-weight': '800',
                                'margin': '14px 0 8px 0'
                              };
                            case 'h2':
                              return {
                                'font-size': '18px',
                                'font-weight': '800',
                                'margin': '14px 0 8px 0'
                              };
                            case 'h3':
                              return {
                                'font-size': '16px',
                                'font-weight': '800',
                                'margin': '12px 0 6px 0'
                              };
                            case 'code':
                              return {'font-family': 'monospace', 'font-size': '13px'};
                            case 'hr':
                              return {
                                'border': '0',
                                'border-top': '1px solid #24242C',
                                'margin': '16px 0',
                              };
                          }
                          return null;
                        },
                        customWidgetBuilder: (element) {
                          if (element.localName == 'pre') {
                            final code = element.text;

                            return Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(12, 12, 42, 12),
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D0D14),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF24242C)),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      code,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        height: 1.35,
                                        color: Color(0xFFEDEDF5),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: IconButton(
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 18, color: Color(0xFFB9B9C8)),
                                    tooltip: "Copy code",
                                    onPressed: () async {
                                      _hapticLight();
                                      await Clipboard.setData(ClipboardData(text: code));
                                      _snack('Copied');
                                    },
                                  ),
                                ),
                              ],
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
