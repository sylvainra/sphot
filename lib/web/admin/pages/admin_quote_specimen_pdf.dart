import 'dart:typed_data';


import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../services/published_commercial_quote_service.dart';
import 'admin_financial_pdf_brand.dart';

/// Spécimen de consultation SPHOT ADMIN.
/// Gabarit aligné sur simplePdfBuffer de functions/admin_workflow.js :
/// cartouche SPHOT, référence, rubriques rouge/bleu, lignes libellé/valeur,
/// information importante, signature et pied de page.
/// Ne crée aucun numéro DV, email, paiement ou document Firestore.
Future<Uint8List> buildAdminQuoteSpecimenPdf({
  required Map<String, dynamic> subscription,
  required Map<String, dynamic> issuer,
  required PublishedCommercialQuote? quote,
}) async {
  String value(dynamic input) => input?.toString().trim() ?? '';
  String filled(Map<String, dynamic> source, String key) {
    final input = value(source[key]);
    return input.isEmpty ? 'À compléter' : input;
  }
  String money(num input) =>
      input.toStringAsFixed(2).replaceAll('.', ',') + ' EUR';
  String address(
    Map<String, dynamic> source,
    String street, String postal, String city, String country,
  ) {
    final parts = <String>[
      value(source[street]),
      [value(source[postal]), value(source[city])]
          .where((part) => part.isNotEmpty).join(' '),
      value(source[country]),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'À compléter' : parts.join(', ');
  }

  final rawSelection = subscription['selectedRescueStationIds'];
  final stationIds = rawSelection is Iterable
      ? rawSelection.whereType<String>()
          .where((id) => id.trim().isNotEmpty).toSet()
      : <String>{};
  final namesById = <String, String>{};
  final savedStations = subscription['selectedRescueStations'];
  if (savedStations is Iterable) {
    for (final station in savedStations) {
      if (station is! Map) continue;
      final id = value(station['spotDocumentId']);
      if (!stationIds.contains(id)) continue;
      namesById[id] = [
        value(station['idSphot']),
        value(station['name']),
      ].where((part) => part.isNotEmpty).join(' - ');
    }
  }
  final stations = stationIds.map((id) =>
      namesById[id]?.isNotEmpty == true ? namesById[id]! :
      'Poste à identifier : $id').toList()..sort();

  // Ne jamais utiliser un montant soumis par le navigateur comme tarif.
  final rawLines = quote?.details['lines'];
  final lines = rawLines is List
      ? rawLines.whereType<Map>().where((line) =>
          line['tier'] is num &&
          line['count'] is num &&
          line['unitExclTax'] is num &&
          line['amountExclTax'] is num &&
          (line['tier'] as num).toInt() >= 1 &&
          (line['tier'] as num).toInt() <= 4).toList()
      : <Map>[];
  final totalCount = lines.fold<int>(
    0, (sum, line) => sum + (line['count'] as num).toInt(),
  );
  final totalAmount = lines.fold<num>(
    0, (sum, line) => sum + (line['amountExclTax'] as num),
  );
  final validPublishedAmount = quote != null &&
      quote.market == 'ADMIN' &&
      quote.currency == 'EUR' &&
      stations.isNotEmpty &&
      lines.length == 4 &&
      totalCount == stations.length &&
      totalAmount == quote.amountExclTax;

  final blue = PdfColor.fromHex('1E3A8A');
  final red = PdfColor.fromHex('DC2626');
  final dark = PdfColor.fromHex('263238');
  final grey = PdfColor.fromHex('607D8B');
  final pale = PdfColor.fromHex('F3F6FB');
  final border = PdfColor.fromHex('D9E2EC');
  final warm = PdfColor.fromHex('FFF8E1');
  final orange = PdfColor.fromHex('F59E0B');
  const leftWidth = 124.0;

  // Les polices PDF standard prennent en charge le français Latin-1.
  // Éviter les puces et apostrophes typographiques non couvertes.
  String pdfText(String input) => input
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('•', '-')
      .replaceAll('œ', 'oe')
      .replaceAll('Œ', 'OE')
      .replaceAll(' ', ' ')
      .replaceAll('…', '...');

  final brand = await AdminFinancialPdfBrand.load();

  final document = pw.Document(
    title: 'DEVIS SPHOT ADMIN - SPECIMEN',
    author: 'SPHOT',
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    ),
  );

  pw.Widget section(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 5, bottom: 3),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(pdfText(text.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 8.4, fontWeight: pw.FontWeight.bold, color: red,
          )),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.65, color: blue),
      ],
    ),
  );

  pw.Widget row(String label, String text, {bool emphasis = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 10, top: 1.4, bottom: 1.4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: leftWidth,
              child: pw.Text(pdfText(label), style: pw.TextStyle(
                color: blue, fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              )),
            ),
            pw.Expanded(child: pw.Text(pdfText(text), style: pw.TextStyle(
              color: emphasis ? red : dark,
              fontSize: emphasis ? 9 : 8,
              fontWeight: emphasis ?
                  pw.FontWeight.bold : pw.FontWeight.normal,
            ))),
          ],
        ),
      );

  final buyerId = value(subscription['billingSiret']).isNotEmpty
      ? value(subscription['billingSiret'])
      : filled(subscription, 'billingLegalId');
  final issuerVat = value(issuer['vatNumber']);
  final labelLines = <String>[
    'Premier poste', 'Du 2e au 4e poste',
    'Du 5e au 9e poste', 'À partir du 10e poste',
  ];
  final dossier = filled(subscription, 'administrativeReference');

  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 24, 40, 71),
    header: (ctx) => brand.header(),
    footer: (ctx) => brand.footer(ctx, specimen: true),
    build: (ctx) => [
      pw.SizedBox(height: 7),
      pw.Center(child: pw.Text('DEVIS SPHOT ADMIN', style: pw.TextStyle(
        fontSize: 12.6, color: blue, fontWeight: pw.FontWeight.bold,
      ))),
      pw.SizedBox(height: 6),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(14, 7, 14, 7),
        decoration: pw.BoxDecoration(
          color: pale, border: pw.Border.all(color: blue, width: 0.75),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('RÉFÉRENCE DU DOCUMENT',
                  style: pw.TextStyle(fontSize: 7.1, color: grey,
                    fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text('NON ATTRIBUÉE - SPÉCIMEN',
                  style: pw.TextStyle(fontSize: 10.3, color: red,
                    fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text('Dossier : ' + pdfText(dossier),
                  style: pw.TextStyle(fontSize: 7, color: dark)),
              ],
            )),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('RUBRIQUE', style: pw.TextStyle(
                  fontSize: 7, color: blue, fontWeight: pw.FontWeight.bold)),
                pw.Text('DEVIS ADMIN', style: pw.TextStyle(
                  fontSize: 8, color: dark, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 7),
                pw.Text('STATUT', style: pw.TextStyle(
                  fontSize: 7, color: blue, fontWeight: pw.FontWeight.bold)),
                pw.Text('NON ÉMIS', style: pw.TextStyle(
                  fontSize: 8, color: dark, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8),
        child: pw.Text(
          'Document consultable pour préparer un devis facultatif '
          'd\'abonnement SPHOT ADMIN. Les informations encore '
          'inconnues seront complétées automatiquement.',
          style: pw.TextStyle(color: dark, fontSize: 8),
        ),
      ),
      section('Émetteur'),
      row('Organisation', value(issuer['legalName']).isEmpty
          ? 'SPHOT - raison sociale à compléter'
          : value(issuer['legalName'])),
      row('SIRET', filled(issuer, 'siret')),
      row('Adresse', address(issuer, 'address',
          'postalCode', 'city', 'country')),
      row('Email', filled(issuer, 'email')),
      row('TVA intracommunautaire', issuerVat.isEmpty ?
          'À compléter' : issuerVat),
      section('Organisme payeur'),
      row('Organisation', filled(subscription, 'billingOrganisation')),
      row('SIRET / identifiant', buyerId),
      row('Adresse', address(subscription, 'billingAddress',
          'billingPostalCode', 'billingCity', 'billingCountry')),
      row('Contact', filled(subscription, 'billingContactName')),
      row('Email', filled(subscription, 'billingContactEmail')),
      section('Postes de secours concernés'),
      if (stations.isEmpty) row('Postes', 'À renseigner'),
      for (var i = 0; i < stations.length; i++)
        row('Poste ' + (i + 1).toString(), stations[i]),
      section('Offre et tarification annuelle'),
      if (validPublishedAmount) ...[
        row('Grille publiée', quote!.pricingReference),
        for (final line in lines)
          if ((line['count'] as num) > 0)
            row(labelLines[(line['tier'] as num).toInt() - 1],
              (line['count'] as num).toInt().toString() + ' x ' +
              money(line['unitExclTax'] as num) + ' = ' +
              money(line['amountExclTax'] as num)),
        pw.SizedBox(height: 4),
        row('TOTAL ANNUEL HT', money(quote!.amountExclTax),
            emphasis: true),
      ] else
        row('Montant HT', 'À compléter - grille ou postes indisponibles'),
      row('TVA', 'À déterminer selon le régime applicable'),
      row('TOTAL TTC', 'Non déterminé'),
      row('Traitement fiscal', 'À compléter'),
      row('Fondement fiscal', 'À compléter'),
      section('Période et conditions'),
      row('Abonnement', 'Annuel par poste de secours'),
      row('Période', 'Activation réelle au 31 décembre ; '
          'renouvellement au 1er janvier, sans prorata'),
      row('Émission', 'Non émis'),
      row('Validité', '30 jours après émission, au plus tard '
          'le 31 décembre'),
      pw.SizedBox(height: 5),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(12, 7, 12, 8),
        decoration: pw.BoxDecoration(
          color: warm, border: pw.Border.all(color: orange, width: 0.8),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('INFORMATION IMPORTANTE', style: pw.TextStyle(
              color: red, fontSize: 7.8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(
              'SPÉCIMEN NON CONTRACTUEL. Ce document ne constitue ni '
              'une commande, ni une facture, ni un règlement ni '
              'une activation. Les informations fiscales et '
              'contractuelles applicables sont précisées à '
              'l\'engagement.',
              style: pw.TextStyle(color: dark, fontSize: 7.3),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Align(alignment: pw.Alignment.centerRight,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('À bientôt sur SPHOT,',
              style: pw.TextStyle(fontSize: 8.1, color: dark)),
            pw.SizedBox(height: 3),
            pw.Text("L'équipe SPHOT", style: pw.TextStyle(
              color: blue, fontSize: 8.4, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    ],
  ));
  return document.save();
}
