/// Version publiée propre à un document juridique.
///
/// Le numéro de version du corpus SPHOT reste nécessaire aux contrôles
/// d'accès historiques, mais il ne doit pas être présenté comme la version
/// individuelle d'une notice RGPD ou d'une politique de confidentialité.
class LegalPublishedVersion {
  const LegalPublishedVersion._();

  static String number(
    Map<String, dynamic>? document, {
    required String fallback,
  }) {
    final individual = (document?['version'] ?? '').toString().trim();
    return individual.isNotEmpty ? individual : fallback.trim();
  }

  /// La révision absente sur les notices historiques reste explicite ; on ne
  /// lui invente pas une révision zéro qui n'existe pas dans Firestore.
  static String identifier(
    Map<String, dynamic>? document, {
    required String fallback,
  }) {
    final version = number(document, fallback: fallback);
    final rawRevision = document?['revision'];
    if (rawRevision is int && rawRevision >= 0) {
      return '$version:r$rawRevision';
    }
    return '$version:historique';
  }

  /// Retourne les versions des documents réellement présentés à ce profil.
  /// Les anciens appels demeurent ceux des CGU Grand Public.
  static Map<String, String> acceptedSnapshot({
    required Map<String, dynamic>? cgu,
    required Map<String, dynamic>? privacyPolicy,
    required Map<String, dynamic>? rgpdNotice,
    required String fallback,
    String cguId = 'cgu',
    Map<String, dynamic>? charter,
    String? charterId,
  }) {
    final result = <String, String>{
      cguId: identifier(cgu, fallback: fallback),
      'privacyPolicy': identifier(privacyPolicy, fallback: fallback),
      'rgpdNotice': identifier(rgpdNotice, fallback: fallback),
    };
    if (charterId != null) {
      if (charter == null) {
        throw ArgumentError('Charte manquante pour $charterId');
      }
      result[charterId] = identifier(charter, fallback: fallback);
    }
    return result;
  }

  /// Un texte non publié ou incomplet ne peut pas être accepté.
  static bool isPublishedDocument(
    Map<String, dynamic>? document, {
    required int chapterCount,
  }) {
    final chapters = document?['chapters'];
    return document?['published'] == true &&
        document?['testOnly'] != true &&
        chapters is List &&
        chapters.length == chapterCount;
  }

  /// Les preuves anciennes ne comportaient que la version du corpus ; leur
  /// compatibilité est préservée. Pour les nouvelles, on vérifie chaque ID.
  static bool matchesRecordedSnapshot(
    Object? recorded,
    Map<String, String> current, {
    bool requireProof = false,
  }) {
    if (recorded is! Map) return !requireProof;
    for (final item in current.entries) {
      if (recorded[item.key] != item.value) return false;
    }
    return true;
  }
}
