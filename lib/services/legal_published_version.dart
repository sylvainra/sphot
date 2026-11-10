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

  static Map<String, String> acceptedSnapshot({
    required Map<String, dynamic>? cgu,
    required Map<String, dynamic>? privacyPolicy,
    required Map<String, dynamic>? rgpdNotice,
    required String fallback,
  }) => <String, String>{
    'cgu': identifier(cgu, fallback: fallback),
    'privacyPolicy': identifier(privacyPolicy, fallback: fallback),
    'rgpdNotice': identifier(rgpdNotice, fallback: fallback),
  };

  /// Les preuves anciennes ne comportaient que la version du corpus ; leur
  /// compatibilité est préservée. Pour les nouvelles, on vérifie chaque ID.
  static bool matchesRecordedSnapshot(
    Object? recorded,
    Map<String, String> current,
  ) {
    if (recorded is! Map) return true;
    for (final item in current.entries) {
      if (recorded[item.key] != item.value) return false;
    }
    return true;
  }
}
