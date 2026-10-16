import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/super_admin/services/annual_financial_export.dart';

void main() {
  Map<String, dynamic> invoice() => {
        'documentType': 'invoice',
        'status': 'issued',
        'documentNumber': 'FA-2026-000001',
        'year': 2026,
        'issuedOn': '2026-10-16',
        'adminUid': 'admin-1',
        'administrativeReference': 'SPHOT-ADM-FRA-2026-000061',
        'amountExclTax': 898,
        'taxAmount': 0,
        'amountInclTax': 898,
        'currency': 'EUR',
        'sha256': List<String>.filled(64, 'a').join(),
        'storagePath': 'private/2026/invoice.pdf',
        'commercialSnapshot': {
          'buyer': {'legalName': 'Commune test', 'legalId': '12345678901234'},
          'fiscality': {'taxTreatment': 'TEST', 'legalBasis': 'TEST'},
        },
      };

  test('Aucun devis ni estimation ne rentre dans le CSV comptable', () {
    final result = SuperAdminAnnualFinancialExport.build(2026, [
      {...invoice(), 'documentType': 'quote'},
      {...invoice(), 'status': 'draft_preview'},
    ]);
    expect(result.documentCount, 0);
    expect(result.netExclTax, 0);
    expect(result.csv, contains('Facture origine'));
  });

  test('Facture et avoir valide se rapprochent sans encaissement inventé', () {
    final original = invoice();
    final credit = {
      ...invoice(),
      'documentType': 'creditNote',
      'documentNumber': 'AV-2026-000001',
      'originalInvoiceNumber': 'FA-2026-000001',
      'amountExclTax': 100,
      'taxAmount': 0,
      'amountInclTax': 100,
    };
    final result = SuperAdminAnnualFinancialExport.build(
        2026, [original, credit]);
    expect(result.documentCount, 2);
    expect(result.netExclTax, 798);
    expect(result.csv, contains('FA-2026-000001'));
    expect(result.csv, contains('AV-2026-000001'));
    expect(result.csv, contains('-100,00'));
    expect(result.csv, contains('NON RAPPROCHÉ'));
    expect(result.bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
  });

  test('Une pièce sans hash ou incohérente est exclue', () {
    final wrong = {...invoice(), 'sha256': ''};
    final badTax = {...invoice(), 'amountInclTax': 999};
    final result = SuperAdminAnnualFinancialExport.build(
        2026, [wrong, badTax]);
    expect(result.documentCount, 0);
    expect(result.excludedCount, 2);
  });
}
