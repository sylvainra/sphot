/// Compte des postes d'une collectivite sans confondre un ancien compteur
/// d'abonnement avec une selection de postes de secours enregistree.
class AdminStationPricingPreview {
  const AdminStationPricingPreview({
    required this.availableCount,
    required this.quotedCount,
    required this.hasSavedSelection,
    required this.unmatchedSavedCount,
    required this.legacyCount,
  });

  final int availableCount;
  final int quotedCount;
  final bool hasSavedSelection;
  final int unmatchedSavedCount;
  final int? legacyCount;

  bool get hasLegacyCountMismatch =>
      legacyCount != null && legacyCount != quotedCount;

  bool get isValid => quotedCount > 0 && unmatchedSavedCount == 0;

  /// Les identifiants disponibles proviennent UNIQUEMENT de la carte de
  /// l'Admin connecte. Le document d'abonnement ne sert qu'a retrouver
  /// l'eventuelle selection explicite de cette meme collectivite.
  factory AdminStationPricingPreview.resolve({
    required Iterable<String> availableSpotIds,
    required Map<String, dynamic> subscription,
  }) {
    final available = availableSpotIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final rawSelected = subscription['selectedRescueStationIds'];
    final selected = rawSelected is Iterable
        ? rawSelected
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
        : <String>{};
    final hasSavedSelection = selected.isNotEmpty;
    final quotedCount = hasSavedSelection
        ? selected.intersection(available).length
        : available.length;
    final storedCount = subscription['numberOfRescueStations'];
    final legacyCount = storedCount is int && storedCount > 0
        ? storedCount
        : storedCount is num && storedCount > 0 &&
                storedCount == storedCount.roundToDouble()
            ? storedCount.toInt()
            : null;

    return AdminStationPricingPreview(
      availableCount: available.length,
      quotedCount: quotedCount,
      hasSavedSelection: hasSavedSelection,
      unmatchedSavedCount: hasSavedSelection
          ? selected.difference(available).length
          : 0,
      legacyCount: legacyCount,
    );
  }
}
