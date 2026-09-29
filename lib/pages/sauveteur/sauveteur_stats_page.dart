import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'widgets/sauveteur_adaptive_viewport.dart';

class SauveteurStatsPage extends StatefulWidget {
  final Color profileColor;
  final String territoireId;
  final String sphotMode;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;

  const SauveteurStatsPage({
    super.key,
    required this.profileColor,
    required this.territoireId,
    required this.sphotMode,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
  });

  @override
  State<SauveteurStatsPage> createState() => _SauveteurStatsPageState();
}

class _SauveteurStatsPageState extends State<SauveteurStatsPage> {
  static const Color _statsColor = Color(0xFF546E7A);

  final List<Map<String, String>> _spots = [];
  List<Map<String, dynamic>> _entries = [];

  String? _selectedSpotId;
  late DateTime _selectedMonth;

  bool _loading = true;
  bool _sharing = false;
  String? _error;

  bool get _isSphotOn => widget.sphotMode.toUpperCase() == 'ON';

  static const List<String> _monthNames = <String>[
    'JANVIER',
    'FÉVRIER',
    'MARS',
    'AVRIL',
    'MAI',
    'JUIN',
    'JUILLET',
    'AOÛT',
    'SEPTEMBRE',
    'OCTOBRE',
    'NOVEMBRE',
    'DÉCEMBRE',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadSpots();
  }

  String get _monthLabel {
    return '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  String get _selectedSpotLabel {
    final spotId = _selectedSpotId;
    if (spotId == null) return 'Choisir un poste';

    for (final spot in _spots) {
      if (spot['id'] == spotId) {
        return spot['label'] ?? spotId;
      }
    }

    return spotId;
  }

  Future<void> _loadSpots() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('territoires')
          .doc(widget.territoireId)
          .collection('spots')
          .where('typeSphot', isEqualTo: '🚨 POSTE DE SECOURS 🚨')
          .get();

      final assigned = widget.postesAffectes.toSet();

      final spots = snapshot.docs
          .where((doc) => assigned.contains(doc.id))
          .map((doc) {
            final data = doc.data();
            final label = [
              (data['nomSecours'] ?? '').toString().trim(),
              (data['nomSphot'] ?? '').toString().trim(),
            ].where((value) => value.isNotEmpty).join(' - ');

            return <String, String>{
              'id': doc.id,
              'label': label.isEmpty ? doc.id : label,
            };
          })
          .toList()
        ..sort((a, b) => (a['label'] ?? '').compareTo(b['label'] ?? ''));

      if (!mounted) return;

      setState(() {
        _spots
          ..clear()
          ..addAll(spots);

        final preferredId = widget.initialSpotId?.trim();
        final selected = _spots.isEmpty
            ? null
            : _spots.firstWhere(
                (spot) => spot['id'] == preferredId,
                orElse: () => _spots.first,
              );

        _selectedSpotId = selected?['id'];
      });

      await _loadStats();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les postes de secours.';
      });
    }
  }

  Future<void> _loadStats() async {
    final spotId = _selectedSpotId;

    if (!_isSphotOn || spotId == null || spotId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _error = !_isSphotOn
            ? 'Les statistiques opérationnelles sont accessibles lorsque SPHOT est ON.'
            : null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final start = DateTime(_selectedMonth.year, _selectedMonth.month);
      final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1);

      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'getSauveteurMainCourante',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'spotId': spotId,
          'dayStartMillis': start.millisecondsSinceEpoch,
          'dayEndMillis': end.millisecondsSinceEpoch,
        }),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _entries = [];
          _loading = false;
          _error = 'Les statistiques ne sont pas accessibles actuellement.';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map<String, dynamic> && decoded['entries'] is List
          ? decoded['entries'] as List
          : const [];

      final entries = raw
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();

      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _error = 'Impossible de calculer les statistiques pour le moment.';
      });
    }
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });

    await _loadStats();
  }

  int? _entryMillis(Map<String, dynamic> entry) {
    final raw = entry['occurredAt'];
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString());
  }

  String _normalizedType(Map<String, dynamic> entry) {
    return (entry['type'] ?? 'Observation')
        .toString()
        .trim()
        .toLowerCase();
  }

  _DailyStats _statsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end =
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;

    final entries = _entries.where((entry) {
      final millis = _entryMillis(entry);
      return millis != null && millis >= start && millis < end;
    }).toList();

    int green = 0;
    int yellow = 0;
    int red = 0;

    final facts = <String, int>{};
    final rescueQualifications = <String, int>{};

    for (final entry in entries) {
      final type = _normalizedType(entry);
      final description = (entry['description'] ?? '').toString().toLowerCase();

      if (type == 'drapeau') {
        if (description.contains('couleur du drapeau')) {
          if (description.contains('→ vert')) green++;
          if (description.contains('→ jaune')) yellow++;
          if (description.contains('→ rouge')) red++;
        }
        continue;
      }

      if (type == 'présence' || type == 'presence') {
        continue;
      }

      String displayType = (entry['type'] ?? 'Observation').toString().trim();

      if (type == 'vérification matériel' ||
          type == 'verification materiel') {
        displayType = 'Matériel';
      }

      facts[displayType] = (facts[displayType] ?? 0) + 1;

      if (type == 'secours' && entry['victim'] is Map) {
        final victim = Map<String, dynamic>.from(entry['victim'] as Map);
        final qualification =
            (victim['qualification'] ?? '').toString().trim();
        if (qualification.isNotEmpty) {
          rescueQualifications[qualification] =
              (rescueQualifications[qualification] ?? 0) + 1;
        }
      }
    }

    return _DailyStats(
      date: day,
      greenFlags: green,
      yellowFlags: yellow,
      redFlags: red,
      facts: facts,
      rescueQualifications: rescueQualifications,
    );
  }

  List<_DailyStats> get _dailyStats {
    final days = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;

    final now = DateTime.now();
    final currentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    final lastDay = currentMonth ? now.day : days;

    return List.generate(
      lastDay,
      (index) => _statsForDay(
        DateTime(
          _selectedMonth.year,
          _selectedMonth.month,
          index + 1,
        ),
      ),
    );
  }

  bool _hasActivity(_DailyStats stats) {
    return stats.greenFlags > 0 ||
        stats.yellowFlags > 0 ||
        stats.redFlags > 0 ||
        stats.facts.isNotEmpty;
  }

  String _formatDay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Widget _spotSelector() {
    if (_spots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSpotId,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _statsColor,
          ),
          items: _spots
              .map(
                (spot) => DropdownMenuItem<String>(
                  value: spot['id'],
                  child: Text(
                    spot['label'] ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _selectedSpotId = value);
            await _loadStats();
          },
        ),
      ),
    );
  }

  Widget _monthNavigation() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeMonth(-1),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: _statsColor,
            ),
          ),
          Expanded(
            child: Text(
              _monthLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _statsColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeMonth(1),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: _statsColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flagCount({
    required String label,
    required int value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Column(
          children: [
            Icon(Icons.flag_rounded, color: color, size: 18),
            const SizedBox(height: 2),
            Text(
              '$value $label',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCard(_DailyStats stats) {
    final factEntries = stats.facts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statsColor,
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDay(stats.date),
            style: const TextStyle(
              color: _statsColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _flagCount(
                label: 'VERT',
                value: stats.greenFlags,
                color: const Color(0xFF22C55E),
              ),
              const SizedBox(width: 5),
              _flagCount(
                label: 'JAUNE',
                value: stats.yellowFlags,
                color: const Color(0xFFFDE047),
              ),
              const SizedBox(width: 5),
              _flagCount(
                label: 'ROUGE',
                value: stats.redFlags,
                color: const Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (factEntries.isEmpty)
            const Text(
              'Aucun fait enregistré.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            const Text(
              'FAITS',
              style: TextStyle(
                color: _statsColor,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            ...factEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: _statsColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (stats.rescueQualifications.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(height: 8),
            const Text(
              'QUALIFICATION DES SECOURS',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            ...stats.rescueQualifications.entries.map(
              (entry) => Text(
                '${entry.key} : ${entry.value}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<Uint8List> _buildPdf() async {
    final document = pw.Document();
    final stats = _dailyStats;

    final totals = <String, int>{};
    int green = 0;
    int yellow = 0;
    int red = 0;

    for (final day in stats) {
      green += day.greenFlags;
      yellow += day.yellowFlags;
      red += day.redFlags;
      for (final entry in day.facts.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'SPHOT - STATS',
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Poste : $_selectedSpotLabel',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.Text(
            'Période : $_monthLabel',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Drapeaux - total période',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Vert : $green   Jaune : $yellow   Rouge : $red',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Faits - total période',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          if (totals.isEmpty)
            pw.Text(
              'Aucun fait enregistré.',
              style: const pw.TextStyle(fontSize: 9),
            )
          else
            ...totals.entries.map(
              (entry) => pw.Text(
                '${entry.key} : ${entry.value}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Détail jour par jour',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          ...stats.map((day) {
            final facts = day.facts.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(' | ');
            final rescue = day.rescueQualifications.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(' | ');

            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 5),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey600,
                  width: 0.5,
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _formatDay(day.date),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Drapeaux - Vert: ${day.greenFlags} | '
                    'Jaune: ${day.yellowFlags} | Rouge: ${day.redFlags}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    facts.isEmpty ? 'Faits : aucun' : 'Faits : $facts',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  if (rescue.isNotEmpty)
                    pw.Text(
                      'Secours : $rescue',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 8),
          pw.Text(
            'Document généré depuis SPHOT.',
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  String _pdfFileName() {
    final rawSpot = _selectedSpotLabel
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return 'SPHOT_STATS_${rawSpot.isEmpty ? 'poste' : rawSpot}_'
        '${_selectedMonth.year}-'
        '${_selectedMonth.month.toString().padLeft(2, '0')}.pdf';
  }

  Future<void> _share() async {
    if (_sharing || _selectedSpotId == null) return;

    setState(() => _sharing = true);

    try {
      final bytes = await _buildPdf();

      Rect? shareOrigin;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        shareOrigin =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
      }

      await SharePlus.instance.share(
        ShareParams(
          subject: 'STATS SPHOT - $_monthLabel',
          text: 'Statistiques SPHOT du poste $_selectedSpotLabel - $_monthLabel.',
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: _pdfFileName(),
            ),
          ],
          sharePositionOrigin: shareOrigin,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _dailyStats;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SauveteurAdaptiveViewport(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    Image.asset(
                      'data/icons/title.png',
                      height: 56,
                      fit: BoxFit.contain,
                    ),
                    const Text(
                      'STATS',
                      style: TextStyle(
                        color: _statsColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            _spotSelector(),
                            const SizedBox(height: 8),
                            _monthNavigation(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _error != null
                                      ? Center(
                                          child: Text(
                                            _error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        )
                                      : ListView(
                                          children: [
                                            ...stats.map(_dayCard),
                                            if (!stats.any(_hasActivity))
                                              const Padding(
                                                padding: EdgeInsets.all(14),
                                                child: Text(
                                                  'Aucune activité enregistrée '
                                                  'sur cette période.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 46,
                                              child: ElevatedButton.icon(
                                                onPressed:
                                                    _sharing ? null : _share,
                                                icon: _sharing
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: _statsColor,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.share_rounded,
                                                        color: _statsColor,
                                                      ),
                                                label: const Text(
                                                  'PARTAGER',
                                                  style: TextStyle(
                                                    color: _statsColor,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                  ),
                                                ),
                                                style:
                                                    ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  foregroundColor: _statsColor,
                                                  elevation: 0,
                                                  side: const BorderSide(
                                                    color: _statsColor,
                                                    width: 2,
                                                  ),
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.black,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyStats {
  final DateTime date;
  final int greenFlags;
  final int yellowFlags;
  final int redFlags;
  final Map<String, int> facts;
  final Map<String, int> rescueQualifications;

  const _DailyStats({
    required this.date,
    required this.greenFlags,
    required this.yellowFlags,
    required this.redFlags,
    required this.facts,
    required this.rescueQualifications,
  });
}
