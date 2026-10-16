/// Affichage du cycle de vie des grilles tarifaires.
/// Toutes les dates proviennent du serveur (ISO 8601 en UTC),
/// puis sont affichées dans le fuseau local du navigateur.
class CommercialPricingHistoryFormat {
  const CommercialPricingHistoryFormat._();

  static String time(Object? raw) {
    if (raw is! String || raw.isEmpty) return 'Horodatage non disponible';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Horodatage non disponible';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        'à ${two(date.hour)}:${two(date.minute)}:${two(date.second)} '
        '(heure locale)';
  }

  static String status(Object? value) {
    switch (value) {
      case 'published':
        return 'PUBLIÉE';
      case 'archived':
        return 'ARCHIVÉE';
      case 'scheduled':
        return 'PROGRAMMÉE';
      case 'cancelled':
        return 'PROGRAMMATION ANNULÉE';
      default:
        return value?.toString().toUpperCase() ?? 'ÉTAT INCONNU';
    }
  }

  static List<String> events(Map<String, dynamic> version) {
    final lines = <String>[];
    final isInitialReference = version['createdBy'] == 'seed';
    final restoredFrom = version['restoredFromVersion'];
    if (restoredFrom is num) {
      lines.add('Reprise exacte des tarifs de la version V${restoredFrom.toInt()}');
    }
    final createdAt = version['createdAt'];
    final effectiveAt = version['effectiveAt'];
    final publishedAt = version['publishedAt'];
    final scheduledAt = version['scheduledAt'];
    final archivedAt = version['archivedAt'];
    final cancelledAt = version['cancelledAt'];
    final state = version['status']?.toString();

    if (isInitialReference) {
      // Initial seed was snapshotted when Firestore pricing was first used.
      // Its real original publication date was never recorded.
      final referenceTime = createdAt ?? effectiveAt;
      if (referenceTime != null) {
        lines.add('Référence initiale enregistrée le ${time(referenceTime)}');
      }
      lines.add('Date de publication d’origine non disponible');
    } else {
      if (createdAt != null) {
        lines.add('Version historisée le ${time(createdAt)}');
      }
      if (scheduledAt != null) {
        lines.add('Programmation enregistrée le ${time(scheduledAt)}');
      }
      if (scheduledAt != null && effectiveAt != null) {
        lines.add('Date d’effet programmée : ${time(effectiveAt)}');
      }
      if (publishedAt != null) {
        lines.add('Publication effectuée le ${time(publishedAt)}');
      } else if ((state == 'published' || state == 'archived') &&
          effectiveAt != null) {
        lines.add('Date d’effet enregistrée : ${time(effectiveAt)} '
            '(historique antérieur à l’horodatage détaillé)');
      }
    }

    if (archivedAt != null) {
      lines.add('Archivage effectué le ${time(archivedAt)}');
    } else if (state == 'archived') {
      lines.add('Archivage effectué — date non enregistrée dans l’ancienne version');
    }
    if (cancelledAt != null) {
      lines.add('Programmation annulée le ${time(cancelledAt)}');
    }
    return lines;
  }

  static List<String> draftEvents(Map<String, dynamic> draft) {
    final events = <String>[];
    final restoredFrom = draft['restoredFromVersion'];
    if (restoredFrom is num) {
      events.add('Brouillon repris intégralement de V${restoredFrom.toInt()}');
    }
    if (draft['createdAt'] != null) {
      events.add('Brouillon créé le ${time(draft['createdAt'])}');
    }
    if (draft['updatedAt'] != null) {
      events.add('Dernier enregistrement le ${time(draft['updatedAt'])}');
    }
    return events;
  }
}
