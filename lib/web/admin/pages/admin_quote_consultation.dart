import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/published_commercial_quote_service.dart';
import 'admin_quote_specimen_pdf.dart';

/// Prépare un PDF consultable même si le dossier n'est pas encore complet.
/// Aucune attribution de numéro DV, aucune écriture Firestore, aucun email.
Future<Uint8List> createConsultableAdminQuotePdf(
  Map<String, dynamic> data,
) async {
  final chosen = data['selectedRescueStationIds'];
  final ids = chosen is Iterable
      ? chosen.whereType<String>().where((id) => id.trim().isNotEmpty).toSet()
      : <String>{};

  // Les informations juridiques seront prises en compte lors des prochaines
  // consultations. Un document manquant ne bloque pas le PDF consultable.
  Map<String, dynamic> issuer = <String, dynamic>{};
  try {
    final snap = await FirebaseFirestore.instance
        .collection('settings')
        .doc('sphotLegalIdentity')
        .get()
        .timeout(const Duration(seconds: 8));
    issuer = snap.data() ?? <String, dynamic>{};
  } catch (_) {
    // En l'absence de fiche accessible : mentions "À compléter".
  }

  // Lorsque l'offre n'est pas renseignée ou que la grille publiée est
  // indisponible, le document reste consultable SANS prix fictif.
  PublishedCommercialQuote? published;
  if (ids.isNotEmpty) {
    try {
      published = await const PublishedCommercialQuoteService()
          .admin(numberOfRescueStations: ids.length)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // La case tarifaire du PDF indique alors "À compléter".
    }
  }

  return buildAdminQuoteSpecimenPdf(
    subscription: data,
    issuer: issuer,
    quote: published,
  );
}
