import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../admin/pages/admin_quote_pdf_download.dart';
import '../services/annual_financial_export.dart';
import 'sphot_dropdown_visuals.dart';

/// Export documentaire annuel en lecture seule : aucune facturation.
class SuperAdminAnnualFinancialExportCard extends StatefulWidget {
  const SuperAdminAnnualFinancialExportCard({super.key});

  @override
  State<SuperAdminAnnualFinancialExportCard> createState() =>
      _SuperAdminAnnualFinancialExportCardState();
}

class _SuperAdminAnnualFinancialExportCardState
    extends State<SuperAdminAnnualFinancialExportCard> {
  int _year = DateTime.now().year;
  bool _working = false;
  final GlobalKey _yearFieldKey = GlobalKey();
  OverlayEntry? _yearOverlay;
  ScrollController? _yearScrollController;

  @override
  void dispose() {
    _closeYearMenu();
    super.dispose();
  }

  void _closeYearMenu() {
    final entry = _yearOverlay;
    _yearOverlay = null;
    entry?.remove();
    entry?.dispose();
    _yearScrollController?.dispose();
    _yearScrollController = null;
  }

  void _toggleYearMenu() {
    if (_working) return;
    if (_yearOverlay != null) {
      _closeYearMenu();
      return;
    }
    final target = _yearFieldKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject();
    if (target is! RenderBox || overlayBox is! RenderBox) return;

    final point = target.localToGlobal(Offset.zero, ancestor: overlayBox);
    final size = target.size;
    final remainingBelow =
        overlayBox.size.height - point.dy - size.height - 8;
    final remainingAbove = point.dy - 8;
    final above = remainingBelow < 160 &&
        remainingAbove > remainingBelow;
    final height = math.min(270.0,
        math.max(90.0, above ? remainingAbove : remainingBelow));
    final top = above ? point.dy - height : point.dy + size.height - 1;

    final scrollController = ScrollController();
    _yearScrollController = scrollController;
    final now = DateTime.now().year;
    final years = List<int>.generate(now - 2020 + 1, (i) => now - i);
    _yearOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeYearMenu,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: point.dx,
            top: top,
            width: size.width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxHeight: height),
                decoration: SphotDropdownVisuals.popupDecoration,
                child: ScrollbarTheme(
                  data: SphotDropdownVisuals.scrollbarTheme,
                  child: Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(10),
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final year in years)
                          InkWell(
                            onTap: () {
                              setState(() => _year = year);
                              _closeYearMenu();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    year == _year
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: year == _year
                                        ? SphotDropdownVisuals.red
                                        : SphotDropdownVisuals.blue,
                                    size: 21,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    year.toString(),
                                    style: TextStyle(
                                      color: year == _year
                                          ? SphotDropdownVisuals.red
                                          : SphotDropdownVisuals.blue,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_yearOverlay!);
  }

  Widget _yearSelector() => GestureDetector(
    key: _yearFieldKey,
    onTap: _toggleYearMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12,
        ),
        border: SphotDropdownVisuals.inputBorder(),
        enabledBorder: SphotDropdownVisuals.inputBorder(),
        focusedBorder: SphotDropdownVisuals.inputBorder(width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(_year.toString(),
              style: const TextStyle(
                color: SphotDropdownVisuals.blue,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              )),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded,
            color: SphotDropdownVisuals.blue, size: 25),
        ],
      ),
    ),
  );

  Future<void> _download() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('documents')
          .where('year', isEqualTo: _year)
          .get();
      final data = snapshot.docs.map((entry) => <String, dynamic>{
        'documentId': entry.id,
        ...entry.data(),
      }).toList();
      final report = SuperAdminAnnualFinancialExport.build(_year, data);
      if (!mounted) return;
      if (report.documentCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            'Aucune facture FA ou avoir AV émis et exploitable pour ' +
            _year.toString() + '. ' +
            (report.excludedCount > 0
                ? report.excludedCount.toString() +
                  ' pièce(s) à régulariser.'
                : 'Les devis et montants estimés ne sont pas exportés.'),
          )),
        );
        return;
      }
      downloadSuperAdminFinancialCsv(
        report.bytes,
        'SPHOT-PIECES-FINANCIERES-' + _year.toString() + '.csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          report.documentCount.toString() +
          ' pièce(s) émises exportées. ' +
          report.excludedCount.toString() +
          ' pièce(s) écartée(s) pour données incomplètes. ' +
          'Export à rapprocher avec la comptabilité et les paiements.',
        )),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Accès aux pièces financières refusé ou temporairement indisponible.',
        )),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    const blue = SphotDropdownVisuals.blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: blue.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PIÈCES FINANCIÈRES ANNUELLES',
            style: TextStyle(
              color: blue, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 8),
          const Text(
            'Export CSV destiné au suivi administratif et au cabinet '
            'comptable : uniquement les factures FA et avoirs AV '
            'réellement émis et archivés. Les devis, commandes, '
            'spécimens, estimations et encaissements non vérifiés '
            'sont exclus. Cet export ne constitue pas un FEC.',
            style: TextStyle(color: Color(0xFF64748B),
              fontSize: 12, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Exercice :', style: TextStyle(
                color: blue, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 12),
              SizedBox(width: 155, child: _yearSelector()),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _working ? null : _download,
              style: OutlinedButton.styleFrom(
                foregroundColor: blue,
                side: const BorderSide(color: blue, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              ),
              icon: _working
                  ? const SizedBox(height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
              label: Text(
                _working
                    ? 'PRÉPARATION DE L’EXPORT...'
                    : 'EXPORTER LES PIÈCES ÉMISES (CSV)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
