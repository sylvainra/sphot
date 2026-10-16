import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../admin/pages/admin_quote_pdf_download.dart';
import '../services/annual_financial_export.dart';

/// Outil Super Admin : export des pièces réellement émises, jamais des
/// estimations d'abonnement ni des spécimens. Ce n'est pas un FEC fiscal.
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
    const blue = Color(0xFF1E3A8A);
    final now = DateTime.now().year;
    final years = List<int>.generate(now - 2020 + 1, (index) => now - index);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: blue.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PIÈCES FINANCIÈRES ANNUELLES',
            style: TextStyle(color: blue,
              fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 8),
          const Text(
            'Export CSV destiné au suivi administratif et au cabinet '
            'comptable : uniquement les factures FA et avoirs AV '
            'réellement émis et archivés. Les devis, commandes, '
            'spécimens, estimations et encaissements non vérifiés '
            'sont exclus. Cet export ne constitue pas un FEC.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12,
                height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Exercice :', style: TextStyle(
                color: blue, fontWeight: FontWeight.w800)),
              DropdownButton<int>(
                value: _year,
                items: [
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text(year.toString())),
                ],
                onChanged: _working ? null : (year) {
                  if (year != null) setState(() => _year = year);
                },
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _download,
                icon: _working
                    ? const SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download_outlined),
                label: const Text('EXPORTER LES PIÈCES ÉMISES (CSV)'),
              ),
            ]),
        ]),
    );
  }
}
