import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../services/published_commercial_quote_service.dart';
import 'admin_quote_pdf_export.dart';

/// Exporte une SIMULATION NON CONTRACTUELLE, sans écriture Firestore.
/// Ne remplace jamais un devis émis, numéroté, fiscalisé et archivé côté serveur.
class AdminQuoteSimulationPdfService {
  const AdminQuoteSimulationPdfService();

  static const _blue = PdfColor.fromInt(0xFF1E3A8A);
  static const _red = PdfColor.fromInt(0xFFDC2626);
  static const _grey = PdfColor.fromInt(0xFF6B7280);

  // Les polices PDF standard peuvent mal afficher certains signes Unicode.
  // Convertir les apostrophes et tirets typographiques du contenu saisi.
  String _text(dynamic value) => (value?.toString().trim() ?? '')
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('–', '-')
      .replaceAll('—', '-');

  bool _validFrenchSiret(String value) =>
      value.length == 14 &&
      value.codeUnits.every((code) => code >= 48 && code <= 57);

  String _money(num value) =>
      '${value.toStringAsFixed(2).replaceAll('.', ',')} EUR';

  String _formatCivilDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 0.6)),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          ...children,
          pw.SizedBox(height: 10),
        ],
      );

  pw.Widget _detail(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 125,
              child: pw.Text(label,
                  style: const pw.TextStyle(fontSize: 9, color: _grey)),
            ),
            pw.Expanded(
              child: pw.Text(
                value.isEmpty ? 'À compléter' : value,
                style: const pw.TextStyle(fontSize: 9, color: _blue),
              ),
            ),
          ],
        ),
      );

  Future<void> share({
    required PublishedCommercialQuote quote,
    required Map<String, dynamic> billing,
    required List<Map<String, dynamic>> stations,
    required String administrativeReference,
    required int subscriptionYear,
    Rect? sharePositionOrigin,
  }) async {
    // Ces vérifications sont locales et propres à l'aperçu.
    // Le devis officiel devra refaire ses contrôles sur un serveur de confiance.
    if (quote.market != 'ADMIN' ||
        stations.isEmpty ||
        quote.amountExclTax <= 0 ||
        quote.details['numberOfRescueStations'] != stations.length) {
      throw StateError('Simulation tarifaire incohérente avec les postes.');
    }
    final rawLines = quote.details['lines'];
    if (rawLines is! List || rawLines.isEmpty) {
      throw StateError('Détail des tranches tarifaires indisponible.');
    }

    num auditedTotal = 0;
    final tierRows = <pw.Widget>[];
    for (final raw in rawLines) {
      if (raw is! Map ||
          raw['count'] is! num ||
          raw['unitExclTax'] is! num ||
          raw['amountExclTax'] is! num) {
        throw StateError('Détail de simulation incorrect.');
      }
      final count = (raw['count'] as num).toInt();
      final unit = raw['unitExclTax'] as num;
      final amount = raw['amountExclTax'] as num;
      if (count <= 0) continue;
      if (count * unit != amount) {
        throw StateError('Les montants publiés sont incohérents.');
      }
      auditedTotal += amount;
      final title = switch (raw['tier']) {
        1 => '1er poste de secours',
        2 => 'Du 2e au 4e poste',
        3 => 'Du 5e au 9e poste',
        4 => 'À partir du 10e poste',
        _ => 'Tranche tarifaire',
      };
      tierRows.add(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(title, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(
              width: 112,
              child: pw.Text('$count x ${_money(unit)}',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(
              width: 95,
              child: pw.Text(_money(amount),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      ));
    }
    if (auditedTotal != quote.amountExclTax || tierRows.isEmpty) {
      throw StateError('Le total de la simulation publiée est incohérent.');
    }

    // Réutilisation exacte des images de marque du site et du marker SVG
    // des emails ; aucun logo SPHOT recréé en simple texte.
    final headerBackgroundData =
        await rootBundle.load('data/images/map_background.jpg');
    final siteTitleData = await rootBundle.load('data/icons/title.png');
    final fireSvg = await rootBundle.loadString(
      'data/icons/fire_red_icon.svg',
    );
    final headerBackground = pw.MemoryImage(
      headerBackgroundData.buffer.asUint8List(
        headerBackgroundData.offsetInBytes,
        headerBackgroundData.lengthInBytes,
      ),
    );
    final siteTitle = pw.MemoryImage(
      siteTitleData.buffer.asUint8List(
        siteTitleData.offsetInBytes,
        siteTitleData.lengthInBytes,
      ),
    );

    final generatedAt = DateTime.now();
    final document = pw.Document(
      title: 'SPHOT - Simulation tarifaire non contractuelle',
      author: 'SPHOT - environnement de préparation',
      subject: 'Aperçu technique - ni devis ni facture',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            // Signature visuelle identique aux mails SPHOT :
            // l'asset SVG d'origine reste vectoriel dans le PDF.
            pw.Center(
              child: pw.SvgImage(
                svg: fireSvg,
                width: 42,
                height: 65,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              "L'équipe SPHOT",
              style: pw.TextStyle(
                color: _blue,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Divider(color: _blue),
            pw.Text(
              'SIMULATION NON CONTRACTUELLE - Document préparatoire '
              '- Ni devis, ni facture, ni bon de commande.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7, color: _red),
            ),
            pw.Text(
              'SPHOT - Page ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _grey),
            ),
          ],
        ),
        build: (context) => [
          // Bandeau de la page Web SPHOT : fond cartographique
          // et véritable titre graphique, centré comme sur le site.
          pw.SizedBox(
            width: double.infinity,
            height: 76,
            child: pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(
                    headerBackground,
                    fit: pw.BoxFit.cover,
                  ),
                ),
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Image(
                      siteTitle,
                      height: 51,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'DOCUMENT DE PRÉPARATION',
              style: pw.TextStyle(
                color: _blue,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text('SIMULATION TARIFAIRE - NON CONTRACTUELLE',
              style: pw.TextStyle(
                color: _red,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              )),
          pw.SizedBox(height: 7),
          pw.Text(
            'Simulation calculée le ${_formatCivilDate(generatedAt)} '
            '- Année d\'abonnement : $subscriptionYear',
            style: const pw.TextStyle(fontSize: 9, color: _grey),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Référence de dossier : '
            '${administrativeReference.isEmpty ? 'non renseignée' : administrativeReference}',
            style: const pw.TextStyle(fontSize: 9, color: _grey),
          ),
          pw.SizedBox(height: 16),
          _section('ORGANISME PAYEUR (DONNÉES DÉCLARÉES)', [
            _detail('Organisme', _text(billing['billingOrganisation'])),
            _detail(
              'Identifiant',
              _text(billing['billingSiret']).isNotEmpty
                  ? (_validFrenchSiret(_text(billing['billingSiret']))
                      ? 'SIRET ${_text(billing['billingSiret'])} (non verifie)'
                      : 'SIRET ${_text(billing['billingSiret'])} - FORMAT INVALIDE')
                  : _text(billing['billingLegalId']).isNotEmpty
                      ? '${_text(billing['billingLegalId'])} (non verifie)'
                      : 'Non renseigne',
            ),
            _detail('Adresse', [
              _text(billing['billingAddress']),
              _text(billing['billingAddressComplement']),
              '${_text(billing['billingPostalCode'])} ${_text(billing['billingCity'])}',
              _text(billing['billingCountry']),
            ].where((part) => part.trim().isNotEmpty).join(', ')),
            _detail('Contact', _text(billing['billingContactName'])),
            _detail('Email', _text(billing['billingContactEmail'])),
          ]),
          _section('POSTES CONCERNÉS', [
            for (final station in stations)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  [
                    _text(station['idSphot']),
                    _text(station['name']),
                  ].where((part) => part.isNotEmpty).join(' - '),
                  style: const pw.TextStyle(fontSize: 9, color: _blue),
                ),
              ),
          ]),
          _section('SIMULATION DE L\'OFFRE ANNUELLE', [
            _detail('Grille publiée', quote.pricingReference),
            _detail('Nombre de postes', '${stations.length}'),
            ...tierRows,
            pw.Divider(color: _blue),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text('TOTAL ANNUEL HORS TAXES',
                      style: pw.TextStyle(
                          color: _red,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10)),
                ),
                pw.Text(_money(quote.amountExclTax),
                    style: pw.TextStyle(
                        color: _red,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              'Taxes et montant TTC : non déterminés. '
              'Aucun taux de TVA n\'est présumé.',
              style: const pw.TextStyle(fontSize: 8, color: _grey),
            ),
          ]),
          _section('PÉRIODE ET CONDITIONS', [
            pw.Text(
              'Année civile $subscriptionYear : abonnement jusqu\'au '
              '31 décembre, renouvellement au 1er janvier. '
              'Tarif annuel sans prorata.',
              style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Un futur devis officiel sera valable 30 jours calendaires '
              'à compter de son émission (jour inclus), sans dépasser '
              'le 31 décembre de l\'année concernée.',
              style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
            ),
          ]),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFFFF1F2),
              border: pw.Border.all(color: _red),
            ),
            child: pw.Text(
              'DOCUMENT DE TEST - NON CONTRACTUEL. '
              'L\'émetteur SPHOT n\'est pas encore immatriculé. '
              'Aucun numéro de devis officiel, aucune TVA et aucune '
              'acceptation contractuelle ne sont attribués. '
              'Ce document ne peut servir de commande ni de justificatif '
              'pour engager une dépense.',
              style: pw.TextStyle(
                color: _red, fontSize: 9,
                fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    final bytes = Uint8List.fromList(await document.save());
    final dateTag = '${generatedAt.year}'
        '${generatedAt.month.toString().padLeft(2, '0')}'
        '${generatedAt.day.toString().padLeft(2, '0')}';
    await exportAdminQuotePdf(
      bytes,
      'SPHOT_SIMULATION_ADMIN_$dateTag.pdf',
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
