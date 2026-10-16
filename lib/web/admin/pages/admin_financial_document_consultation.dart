import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/published_commercial_quote_service.dart';
import 'admin_financial_document_pdf.dart';

/// Pure consultation : aucune écriture, aucun numéro commercial ou fiscal.
Future<Uint8List> createAdminFinancialDocumentSpecimen({
  required AdminFinancialDocumentKind kind,
  required Map<String, dynamic> subscription,
}) async {
  Map<String, dynamic> issuer = <String, dynamic>{};
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('sphotLegalIdentity')
        .get()
        .timeout(const Duration(seconds: 8));
    issuer = snapshot.data() ?? <String, dynamic>{};
  } catch (_) {
    // L'émetteur apparaît "À compléter" si sa fiche est inaccessible.
  }

  final raw = subscription['selectedRescueStationIds'];
  final ids = raw is Iterable
      ? raw.whereType<String>().where((v) => v.trim().isNotEmpty).toSet()
      : <String>{};

  PublishedCommercialQuote? price;
  if (ids.isNotEmpty &&
      (kind == AdminFinancialDocumentKind.order ||
       kind == AdminFinancialDocumentKind.invoice)) {
    try {
      price = await const PublishedCommercialQuoteService()
          .admin(numberOfRescueStations: ids.length)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Prix manquant ou incohérent : PDF consultable sans montant inventé.
    }
  }

  return buildAdminFinancialSpecimenPdf(
    kind: kind,
    subscription: subscription,
    issuer: issuer,
    pricing: price,
  );
}
