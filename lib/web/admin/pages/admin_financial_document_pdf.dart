import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/published_commercial_quote_service.dart';
import 'admin_financial_pdf_brand.dart';

enum AdminFinancialDocumentKind { order, invoice, creditNote, paymentStatus }

extension AdminFinancialDocumentKindLabel on AdminFinancialDocumentKind {
  String get title => switch (this) {
    AdminFinancialDocumentKind.order => 'COMMANDE SPHOT ADMIN',
    AdminFinancialDocumentKind.invoice => 'FACTURE SPHOT ADMIN',
    AdminFinancialDocumentKind.creditNote => 'AVOIR SPHOT ADMIN',
    AdminFinancialDocumentKind.paymentStatus => 'SUIVI DES PAIEMENTS SPHOT ADMIN',
  };
  String get filename => switch (this) {
    AdminFinancialDocumentKind.order => 'SPHOT-COMMANDE-SPECIMEN.pdf',
    AdminFinancialDocumentKind.invoice => 'SPHOT-FACTURE-SPECIMEN.pdf',
    AdminFinancialDocumentKind.creditNote => 'SPHOT-AVOIR-SPECIMEN.pdf',
    AdminFinancialDocumentKind.paymentStatus => 'SPHOT-SUIVI-PAIEMENTS-SPECIMEN.pdf',
  };
}

Future<Uint8List> buildAdminFinancialSpecimenPdf({
  required AdminFinancialDocumentKind kind,
  required Map<String, dynamic> subscription,
  required Map<String, dynamic> issuer,
  PublishedCommercialQuote? pricing,
}) async {
  String str(dynamic v) => v?.toString().trim() ?? '';
  String filled(Map<String, dynamic> d, String k) =>
      str(d[k]).isEmpty ? 'À compléter' : str(d[k]);
  String money(num n) => n.toStringAsFixed(2).replaceAll('.', ',') + ' EUR';
  String normalize(String v) => v.replaceAll('’', "'")
      .replaceAll('—', '-').replaceAll('–', '-').replaceAll('œ', 'oe');
  String address(Map<String, dynamic> d, String a, String p,
      String c, String country) {
    final elements = <String>[
      str(d[a]),
      <String>[str(d[p]), str(d[c])].where((v) => v.isNotEmpty).join(' '),
      str(d[country]),
    ].where((v) => v.isNotEmpty).toList();
    return elements.isEmpty ? 'À compléter' : elements.join(', ');
  }

  final savedIds = subscription['selectedRescueStationIds'];
  final ids = savedIds is Iterable
      ? savedIds.whereType<String>().where((v) => v.isNotEmpty).toSet()
      : <String>{};
  final names = <String, String>{};
  final selected = subscription['selectedRescueStations'];
  if (selected is Iterable) {
    for (final item in selected) {
      if (item is! Map) continue;
      final id = str(item['spotDocumentId']);
      if (!ids.contains(id)) continue;
      names[id] = <String>[str(item['idSphot']), str(item['name'])]
          .where((v) => v.isNotEmpty).join(' - ');
    }
  }
  final stations = ids.map((id) =>
      names[id]?.isNotEmpty == true ? names[id]! :
      'Poste à identifier : ' + id).toList()..sort();

  final raw = pricing?.details['lines'];
  final lines = raw is List
      ? raw.whereType<Map>().where((entry) =>
          entry['tier'] is num && entry['count'] is num &&
          entry['unitExclTax'] is num && entry['amountExclTax'] is num &&
          (entry['tier'] as num).toInt() >= 1 &&
          (entry['tier'] as num).toInt() <= 4).toList()
      : <Map>[];
  final count = lines.fold<int>(0,
      (sum, v) => sum + (v['count'] as num).toInt());
  final total = lines.fold<num>(0,
      (sum, v) => sum + (v['amountExclTax'] as num));
  final usable = pricing != null && pricing.market == 'ADMIN' &&
      pricing.currency == 'EUR' && stations.isNotEmpty &&
      lines.length == 4 && count == stations.length &&
      total == pricing.amountExclTax;

  final blue = PdfColor.fromHex('1E3A8A');
  final red = PdfColor.fromHex('DC2626');
  final dark = PdfColor.fromHex('263238');
  final grey = PdfColor.fromHex('607D8B');
  final pale = PdfColor.fromHex('F3F6FB');
  final brand = await AdminFinancialPdfBrand.load();
  final doc = pw.Document(
    title: kind.title + ' - SPECIMEN',
    author: 'SPHOT',
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    ),
  );

  pw.Widget heading(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 4),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(normalize(title.toUpperCase()), style: pw.TextStyle(
          color: red, fontSize: 8.4, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.7, color: blue),
      ]),
  );
  pw.Widget line(String label, String content, {bool amount = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(left: 10, top: 1.8, bottom: 1.8),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 124, child: pw.Text(normalize(label),
            style: pw.TextStyle(color: blue, fontSize: 8,
              fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(normalize(content),
            style: pw.TextStyle(color: amount ? red : dark,
              fontSize: amount ? 9 : 8,
              fontWeight: amount ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ]),
    );

  final payerId = str(subscription['billingSiret']).isNotEmpty
      ? str(subscription['billingSiret'])
      : filled(subscription, 'billingLegalId');
  final widgets = <pw.Widget>[
    pw.Center(child: pw.Text(kind.title,
      style: pw.TextStyle(color: blue,
        fontSize: 12.6, fontWeight: pw.FontWeight.bold))),
    pw.SizedBox(height: 7),
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: pw.BoxDecoration(color: pale,
        border: pw.Border.all(color: blue, width: 0.75),
        borderRadius: pw.BorderRadius.circular(12)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('RÉFÉRENCE DU DOCUMENT', style: pw.TextStyle(
            color: grey, fontSize: 7.1, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('NON ATTRIBUÉE - SPÉCIMEN', style: pw.TextStyle(
            color: red, fontSize: 10.3, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(normalize('Dossier : ' +
              filled(subscription, 'administrativeReference')),
            style: pw.TextStyle(color: dark, fontSize: 7)),
        ]),
    ),
    heading('Émetteur'),
    line('Organisation', str(issuer['legalName']).isNotEmpty
        ? str(issuer['legalName'])
        : 'SPHOT - raison sociale à compléter'),
    line('SIRET', filled(issuer, 'siret')),
    line('Adresse', address(issuer, 'address',
        'postalCode', 'city', 'country')),
    line('Email', filled(issuer, 'email')),
    line('TVA intracommunautaire', filled(issuer, 'vatNumber')),
    heading('Organisme payeur'),
    line('Organisation', filled(subscription, 'billingOrganisation')),
    line('SIRET / identifiant', payerId),
    line('Adresse', address(subscription, 'billingAddress',
        'billingPostalCode', 'billingCity', 'billingCountry')),
    line('Contact', filled(subscription, 'billingContactName')),
    line('Email', filled(subscription, 'billingContactEmail')),
  ];

  if (kind == AdminFinancialDocumentKind.order ||
      kind == AdminFinancialDocumentKind.invoice) {
    widgets.add(heading('Postes de secours concernés'));
    if (stations.isEmpty) widgets.add(line('Postes', 'À renseigner'));
    for (var i = 0; i < stations.length; i++) {
      widgets.add(line('Poste ' + (i + 1).toString(), stations[i]));
    }
    widgets.add(heading('Offre et tarification annuelle'));
    if (usable) {
      widgets.add(line('Grille publiée', pricing!.pricingReference));
      const tiers = ['Premier poste', 'Du 2e au 4e poste',
        'Du 5e au 9e poste', 'À partir du 10e poste'];
      for (final entry in lines) {
        final quantity = (entry['count'] as num).toInt();
        if (quantity == 0) continue;
        widgets.add(line(tiers[(entry['tier'] as num).toInt() - 1],
            quantity.toString() + ' x ' +
            money(entry['unitExclTax'] as num) + ' = ' +
            money(entry['amountExclTax'] as num)));
      }
      widgets.add(line('TOTAL ANNUEL HT INDICATIF',
          money(pricing.amountExclTax), amount: true));
    } else {
      widgets.add(line('Montant HT', 'À compléter - prix ou postes indisponibles'));
    }
    widgets.add(line('TVA', 'À déterminer selon le régime applicable'));
    widgets.add(line('TOTAL TTC', 'Non déterminé'));
  }

  if (kind == AdminFinancialDocumentKind.order) {
    widgets.add(heading('Références de commande'));
    widgets.add(line('Commande interne CMD', 'Non attribuée'));
    widgets.add(line('Bon de commande externe',
        filled(subscription, 'purchaseOrderNumber')));
    widgets.add(line('Engagement juridique',
        filled(subscription, 'engagementNumber')));
    widgets.add(line('Code service Chorus Pro',
        filled(subscription, 'chorusServiceCode')));
    widgets.add(line('Date de commande', 'Non confirmée'));
    widgets.add(line('CGV / engagement', 'À vérifier avant confirmation'));
  } else if (kind == AdminFinancialDocumentKind.invoice) {
    widgets.add(heading('Facturation'));
    widgets.add(line('Numéro fiscal FA', 'Non attribué'));
    widgets.add(line('Date de facture', 'Non émise'));
    widgets.add(line('Commande associée', 'À compléter'));
    widgets.add(line('Échéance de règlement', 'À définir'));
    widgets.add(line('Traitement fiscal', 'À déterminer'));
    widgets.add(line('Référence engagement',
        filled(subscription, 'engagementNumber')));
    widgets.add(line('Paiement encaissé', 'Non vérifié'));
  } else if (kind == AdminFinancialDocumentKind.creditNote) {
    widgets.add(heading('Facture corrigée et montant'));
    widgets.add(line('Numéro avoir AV', 'Non attribué'));
    widgets.add(line('Facture d’origine FA', 'À compléter'));
    widgets.add(line('Date d’émission', 'Non émis'));
    widgets.add(line('Motif', 'À renseigner'));
    widgets.add(line('Montant HT', 'À calculer sur facture émise'));
    widgets.add(line('TVA et TTC', 'À calculer sur facture émise'));
    widgets.add(line('Remboursement / solde', 'Non déterminé'));
  } else {
    widgets.add(heading('Suivi des factures et paiements'));
    widgets.add(line('Facture liée', 'À compléter'));
    widgets.add(line('Code Chorus Pro',
        filled(subscription, 'chorusServiceCode')));
    widgets.add(line('Dépôt Chorus Pro', 'Non vérifié'));
    widgets.add(line('Échéance', 'À compléter'));
    widgets.add(line('Montant exigible', 'À établir depuis une facture émise'));
    widgets.add(line('Encaissement', 'Non vérifié'));
    widgets.add(line('Date de règlement', 'Non vérifiée'));
    widgets.add(line('Solde restant', 'Non déterminé'));
    widgets.add(line('Justificatif de paiement', 'À rattacher'));
  }
  widgets.addAll([
    pw.SizedBox(height: 7),
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('FFF8E1'),
        border: pw.Border.all(color: PdfColor.fromHex('F59E0B'), width: 0.8),
        borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('INFORMATION IMPORTANTE', style: pw.TextStyle(
            fontSize: 7.8, color: red, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(normalize('SPÉCIMEN NON CONTRACTUEL. Aucun document '
            'comptable, paiement ou commande n’est créé par cette consultation. '
            'Les champs manquants sont à compléter. '
            'Les montants indicatifs ne constituent pas une créance.'),
            style: pw.TextStyle(color: dark, fontSize: 7.4)),
        ]),
    ),
    pw.SizedBox(height: 6),
    pw.Align(alignment: pw.Alignment.centerRight,
      child: pw.Text("L'équipe SPHOT", style: pw.TextStyle(
        color: blue, fontSize: 8.4, fontWeight: pw.FontWeight.bold))),
  ]);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 24, 40, 71),
    header: (_) => brand.header(),
    footer: (ctx) => brand.footer(ctx, specimen: true),
    build: (_) => widgets,
  ));
  return doc.save();
}
