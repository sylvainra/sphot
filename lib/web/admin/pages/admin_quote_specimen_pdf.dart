import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../services/published_commercial_quote_service.dart';

/// Produit seulement un SPÉCIMEN de devis : aucune émission ou écriture.
Future<Uint8List> buildAdminQuoteSpecimenPdf({
  required Map<String, dynamic> subscription,
  required Map<String, dynamic> issuer,
  required PublishedCommercialQuote quote,
}) async {
  String str(dynamic v) => v?.toString().trim() ?? '';
  String field(Map<String, dynamic> data, String key) =>
      str(data[key]).isEmpty ? 'À compléter' : str(data[key]);
  String money(num n) =>
      n.toStringAsFixed(2).replaceAll('.', ',') + ' EUR';
  String address(Map<String, dynamic> data, String a, String p,
      String c, String country) {
    final parts = <String>[
      str(data[a]),
      [str(data[p]), str(data[c])].where((v) => v.isNotEmpty).join(' '),
      str(data[country]),
    ].where((v) => v.isNotEmpty).toList();
    return parts.isEmpty ? 'Adresse à compléter' : parts.join(', ');
  }

  final selected = subscription['selectedRescueStationIds'];
  final ids = selected is Iterable
      ? selected.whereType<String>().where((v) => v.trim().isNotEmpty).toSet()
      : <String>{};
  if (ids.isEmpty || quote.market != 'ADMIN' || quote.currency != 'EUR') {
    throw StateError('Tarif ou postes non disponibles pour le spécimen.');
  }
  final raw = quote.details['lines'];
  if (raw is! List) {
    throw StateError('Détail du tarif publié manquant.');
  }
  final lines = raw.whereType<Map>().where((l) =>
      l['count'] is num && l['unitExclTax'] is num &&
      l['amountExclTax'] is num && l['tier'] is num &&
      (l['tier'] as num).toInt() >= 1 &&
      (l['tier'] as num).toInt() <= 4).toList();
  final count = lines.fold<int>(0,
      (total, l) => total + (l['count'] as num).toInt());
  final sum = lines.fold<num>(0,
      (total, l) => total + (l['amountExclTax'] as num));
  if (lines.length != 4 || count != ids.length ||
      sum != quote.amountExclTax) {
    throw StateError('Prix publié incohérent avec les postes.');
  }

  final nameById = <String, String>{};
  final stored = subscription['selectedRescueStations'];
  if (stored is Iterable) {
    for (final item in stored) {
      if (item is! Map) continue;
      final id = str(item['spotDocumentId']);
      if (ids.contains(id)) {
        nameById[id] = [str(item['idSphot']), str(item['name'])]
            .where((v) => v.isNotEmpty).join(' - ');
      }
    }
  }
  final stations = ids.map((id) =>
      nameById[id]?.isNotEmpty == true ? nameById[id]! :
      'Poste à identifier : ' + id).toList()..sort();

  final blue = PdfColor.fromHex('1E3A8A');
  final red = PdfColor.fromHex('DC2626');
  final grey = PdfColor.fromHex('64748B');
  final soft = PdfColor.fromHex('F3F6FB');
  final orange = PdfColor.fromHex('B45309');
  final title = pw.MemoryImage(
      (await rootBundle.load('data/icons/title.png')).buffer.asUint8List());
  final fire = pw.MemoryImage((await rootBundle.load(
      'data/icons/fire_red_icon.png')).buffer.asUint8List());

  pw.Widget line(String value, {bool bold = false, PdfColor? color,
      double size = 9}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(value, style: pw.TextStyle(
      fontSize: size, color: color ?? blue,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    )),
  );
  pw.Widget heading(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10, bottom: 8),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        line(value, bold: true, size: 10),
        pw.Container(height: 0.7, color: blue),
      ],
    ),
  );

  const tiers = <String>[
    'Premier poste', '2e au 4e poste', '5e au 9e poste',
    '10e poste et suivants',
  ];
  final rows = <List<String>>[
    for (final l in lines)
      if ((l['count'] as num) > 0)
        [
          tiers[(l['tier'] as num).toInt() - 1],
          (l['count'] as num).toInt().toString(),
          money(l['unitExclTax'] as num),
          money(l['amountExclTax'] as num),
        ],
  ];
  final document = pw.Document(
      title: 'SPHOT - SPECIMEN DE DEVIS', author: 'SPHOT');
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(42, 30, 42, 42),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(border: pw.Border(
        bottom: pw.BorderSide(color: blue, width: 0.8),
      )),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Image(title, width: 145, height: 45, fit: pw.BoxFit.contain),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              line('DEVIS SPHOT ADMIN', bold: true, size: 12),
              line('SPÉCIMEN - NON CONTRACTUEL', color: red,
                  bold: true, size: 8.5),
            ]),
        ]),
    ),
    footer: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 7),
      decoration: pw.BoxDecoration(border: pw.Border(
        top: pw.BorderSide(color: blue, width: 0.6),
      )),
      child: pw.Row(children: [
        pw.Image(fire, height: 22),
        pw.SizedBox(width: 8),
        pw.Expanded(child: line(
          'SPHOT - Document de démonstration sans valeur commerciale. '
          'L’équipe SPHOT.', size: 7, color: grey)),
        line('Page ' + ctx.pageNumber.toString() + ' / ' +
            ctx.pagesCount.toString(), color: grey, size: 7),
      ]),
    ),
    build: (ctx) => [
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: soft, border: pw.Border.all(color: blue, width: 0.6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            line('DOSSIER ADMIN : ' +
                field(subscription, 'administrativeReference'), bold: true),
            line('Numéro de devis : non attribué', color: grey),
            line('Date d’émission : non émis', color: grey),
            line('Validité : 30 jours à compter d’une émission officielle, '
                'sans dépasser le 31 décembre de l’année concernée.',
                color: grey, size: 8),
          ]),
      ),
      heading('ÉMETTEUR'),
      line(str(issuer['legalName']).isEmpty ?
          'SPHOT (raison sociale à compléter)' :
          str(issuer['legalName']), bold: true),
      line('SIRET : ' + field(issuer, 'siret')),
      line(address(issuer, 'address', 'postalCode', 'city', 'country')),
      line('Email : ' + field(issuer, 'email')),
      line('TVA intracommunautaire : ' +
          (str(issuer['vatNumber']).isEmpty ?
              'À déterminer si applicable' : str(issuer['vatNumber']))),
      heading('ORGANISME PAYEUR - DONNÉES DÉCLARÉES'),
      line(field(subscription, 'billingOrganisation'), bold: true),
      line('SIRET / identifiant : ' +
          (str(subscription['billingSiret']).isNotEmpty ?
              str(subscription['billingSiret']) :
              field(subscription, 'billingLegalId'))),
      line(address(subscription, 'billingAddress',
          'billingPostalCode', 'billingCity', 'billingCountry')),
      line('Contact : ' + field(subscription, 'billingContactName')),
      line('Email : ' + field(subscription, 'billingContactEmail')),
      heading('POSTES DE SECOURS CONCERNÉS (' +
          stations.length.toString() + ')'),
      ...stations.map((name) => line('• ' + name, size: 8.5)),
      heading('OFFRE ET TARIFICATION ANNUELLE'),
      line('Grille publiée : ' + quote.pricingReference,
          size: 8, color: grey),
      pw.Table.fromTextArray(
        headers: const ['Tranche', 'Qté', 'Prix unitaire HT', 'Montant HT'],
        data: rows,
        headerDecoration: pw.BoxDecoration(color: blue),
        headerStyle: pw.TextStyle(color: PdfColors.white,
            fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: pw.TextStyle(fontSize: 8.5, color: blue),
        cellPadding: const pw.EdgeInsets.all(7),
        cellAlignments: {
          1: pw.Alignment.center,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
      ),
      pw.SizedBox(height: 11),
      pw.Container(alignment: pw.Alignment.centerRight,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            line('TOTAL ANNUEL ESTIMATIF HT : ' +
                money(quote!.amountExclTax),
                bold: true, color: red, size: 13),
            line('TVA : à déterminer selon le régime applicable',
                color: grey),
            line('TOTAL TTC : non déterminé', color: grey),
          ]),
      ),
      heading('PÉRIODE ET CONDITIONS'),
      line('Abonnement annuel par poste. Début à l’activation réelle ; '
          'fin au 31 décembre de l’année d’activation ; '
          'renouvellement au 1er janvier, sans prorata.', size: 8.5),
      line('Le devis reste facultatif. Ce spécimen ne constitue '
          'ni commande, ni facture, ni paiement, ni activation.',
          size: 8.5),
      pw.SizedBox(height: 7),
      pw.Container(
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('FFF7ED'),
          border: pw.Border.all(color: orange, width: 0.8),
        ),
        child: line('SPÉCIMEN NON CONTRACTUEL. '
          'La fiche settings/sphotLegalIdentity alimente les coordonnées '
          'de SPHOT lorsqu’elles seront renseignées. '
          'L’émission officielle fixera les mentions fiscales, '
          'le numéro DV et la date après vérifications.',
          color: orange, size: 8),
      ),
    ],
  ));
  return document.save();
}
