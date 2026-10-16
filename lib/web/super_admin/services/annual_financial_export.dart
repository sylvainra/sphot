import 'dart:convert';
import 'dart:typed_data';

/// Export DOCUMENTAIRE pour transmission au cabinet comptable.
/// Ce n'est ni un FEC, ni un journal comptable certifié.
/// Seules les factures FA et les avoirs AV réellement émis et archivés
/// sont inclus ; aucun devis, commande ou abonnement estimé.
class SuperAdminAnnualFinancialReport {
  const SuperAdminAnnualFinancialReport({
    required this.year,
    required this.csv,
    required this.documentCount,
    required this.excludedCount,
    required this.netExclTax,
    required this.netTax,
    required this.netInclTax,
  });

  final int year;
  final String csv;
  final int documentCount;
  final int excludedCount;
  final num netExclTax;
  final num netTax;
  final num netInclTax;

  Uint8List get bytes => Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode(csv),
      ]);
}

class SuperAdminAnnualFinancialExport {
  const SuperAdminAnnualFinancialExport._();

  static String _str(dynamic v) => v?.toString().trim() ?? '';
  static Map<String, dynamic> _map(dynamic v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  static String _csv(String input) {
    // Ne pas laisser Excel/LibreOffice interpréter une référence comme une
    // formule. Toutes les colonnes sont citées et séparées par point-virgule.
    final safe = RegExp(r'^[=+@\-]').hasMatch(input)
        ? "'" + input
        : input;
    return '"' + safe.replaceAll('"', '""') + '"';
  }

  static String _format(num v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  static SuperAdminAnnualFinancialReport build(
    int year,
    List<Map<String, dynamic>> documents,
  ) {
    if (year < 2000 || year > 2200) {
      throw ArgumentError.value(year, 'year');
    }
    const cols = [
      'Type', 'Numéro', 'Date émission', 'Référence dossier Admin',
      'Admin UID', 'Acheteur', 'Identifiant fiscal acheteur',
      'Montant HT signé', 'TVA signée', 'Montant TTC signé',
      'Devise', 'Référence commande', 'Référence devis',
      'Facture origine (avoir)', 'Traitement TVA', 'Fondement fiscal',
      'Référence pièce', 'SHA256 PDF', 'Référence archive',
      'Encaissement',
    ];
    final lines = <List<String>>[];
    var excluded = 0;
    num sumHt = 0;
    num sumVat = 0;
    num sumTtc = 0;

    // Export stable, trié sans modifier les pièces sources.
    final sorted = [...documents]..sort((a, b) {
      final dateCompare = _str(a['issuedOn']).compareTo(_str(b['issuedOn']));
      if (dateCompare != 0) return dateCompare;
      return _str(a['documentNumber']).compareTo(_str(b['documentNumber']));
    });

    for (final record in sorted) {
      final type = _str(record['documentType']);
      final isInvoice = type == 'invoice';
      final isCredit = type == 'creditNote' || type == 'credit_note';
      if (!isInvoice && !isCredit) continue;
      if (_str(record['status']) != 'issued') continue;
      final number = _str(record['documentNumber']);
      final date = _str(record['issuedOn']);
      final validNumber = RegExp(isInvoice
          ? r'^FA-[0-9]{4}-[0-9]{6,}$'
          : r'^AV-[0-9]{4}-[0-9]{6,}$').hasMatch(number);
      final parsedDate = DateTime.tryParse(date);
      if (!validNumber || parsedDate == null ||
          parsedDate.year != year || !number.contains('-' + year.toString() + '-') ||
          record['year'] != year ||
          _str(record['adminUid']).isEmpty ||
          _str(record['storagePath']).isEmpty ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(_str(record['sha256'])) ||
          (isCredit && !RegExp(r'^FA-[0-9]{4}-[0-9]{6,}$')
              .hasMatch(_str(record['originalInvoiceNumber'])))) {
        excluded++;
        continue;
      }
      final ht = record['amountExclTax'];
      final vat = record['taxAmount'];
      final ttc = record['amountInclTax'];
      if (ht is! num || vat is! num || ttc is! num ||
          !ht.isFinite || !vat.isFinite || !ttc.isFinite ||
          ht < 0 || vat < 0 || ttc < 0 ||
          ((ht + vat - ttc) * 100).abs() > 1) {
        excluded++;
        continue;
      }

      final snapshot = _map(record['commercialSnapshot']);
      final buyer = _map(snapshot['buyer']);
      final fiscal = _map(snapshot['fiscality']);
      final pricing = _map(snapshot['pricing']);
      final currency = _str(record['currency']).isNotEmpty
          ? _str(record['currency']) : _str(pricing['currency']);
      if (currency != 'EUR') {
        excluded++;
        continue;
      }
      final sign = isCredit ? -1 : 1;
      sumHt += ht * sign;
      sumVat += vat * sign;
      sumTtc += ttc * sign;
      lines.add([
        isInvoice ? 'FACTURE' : 'AVOIR',
        number,
        date,
        _str(record['administrativeReference']),
        _str(record['adminUid']),
        _str(buyer['legalName']),
        _str(buyer['legalId']),
        _format(ht * sign),
        _format(vat * sign),
        _format(ttc * sign),
        'EUR',
        _str(record['orderNumber']),
        _str(record['quoteNumber']),
        isCredit ? _str(record['originalInvoiceNumber']) : '',
        _str(record['taxTreatment']).isNotEmpty
            ? _str(record['taxTreatment']) : _str(fiscal['taxTreatment']),
        _str(fiscal['legalBasis']),
        _str(record['documentId']),
        _str(record['sha256']),
        _str(record['storagePath']),
        'NON RAPPROCHÉ',
      ]);
    }

    final rows = [cols, ...lines];
    final csv = rows.map((row) {
      return row.asMap().entries.map((entry) {
        // Les montants signés sont exclusivement générés à partir de
        // nombres validés, jamais fournis tels quels par le client.
        if (entry.key >= 7 && entry.key <= 9 && row != cols) {
          return '"' + entry.value + '"';
        }
        return _csv(entry.value);
      }).join(';');
    }).join('\r\n') + '\r\n';
    return SuperAdminAnnualFinancialReport(
      year: year, csv: csv, documentCount: lines.length,
      excludedCount: excluded,
      netExclTax: sumHt, netTax: sumVat, netInclTax: sumTtc,
    );
  }
}
