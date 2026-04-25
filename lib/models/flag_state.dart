class SpotFlagState {
  final String id;
  final String name;
  final String nomSphot;
  final double lat;
  final double lng;
  final String typeSphot;
  final String statutBaignade;
  final String periode;
  final String heureDebut;
  final String heureFin;
  final String phone;
  final String activite;
  final Map<String, dynamic>? liveFlag;

  SpotFlagState({
    required this.id,
    required this.name,
    required this.nomSphot,
    required this.lat,
    required this.lng,
    required this.typeSphot,
    required this.statutBaignade,
    required this.periode,
    required this.heureDebut,
    required this.heureFin,
    required this.phone,
    required this.activite,
    this.liveFlag,
  });

  factory SpotFlagState.fromFirestore(String id, Map<String, dynamic> data) {
    return SpotFlagState(
      id: id,
      name: _readString(data['name']),
      nomSphot: _readString(data['nom_sphot']),
      lat: _readDouble(data['lat']),
      lng: _readDouble(data['lng']),
      typeSphot: _readString(data['type_sphot']),
      statutBaignade: _readString(data['statut_baignade']),
      periode: _readString(data['periode']),
      heureDebut: _readString(data['heure_debut']),
      heureFin: _readString(data['heure_fin']),
      phone: _readString(data['phone']),
      activite: _readString(data['activite']),
      liveFlag: data['liveFlag'] is Map<String, dynamic>
          ? data['liveFlag'] as Map<String, dynamic>
          : null,
    );
  }

  bool get isPosteSecours {
    return typeSphot.toLowerCase().contains('poste de secours');
  }

  bool get isNaturisme {
    return activite.toLowerCase().contains('naturisme');
  }

  String get normalizedType {
    return typeSphot
        .toUpperCase()
        .replaceAll('È', 'E')
        .replaceAll('É', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ô', 'O')
        .replaceAll('Û', 'U')
        .replaceAll('Ù', 'U')
        .trim();
  }

  FlagColor get flagColor {
    switch (_readString(liveFlag?['flagColor']).toLowerCase()) {
      case 'green':
      case 'vert':
        return FlagColor.green;
      case 'yellow':
      case 'jaune':
        return FlagColor.yellow;
      case 'red':
      case 'rouge':
        return FlagColor.red;
      case 'violet':
        return FlagColor.violet;
      default:
        return FlagColor.none;
    }
  }

  FlagPosition get flagPosition {
    switch (_readString(liveFlag?['flagPosition']).toLowerCase()) {
      case 'hisse':
      case 'hissé':
        return FlagPosition.hisse;
      case 'affale':
      case 'affalé':
        return FlagPosition.affale;
      default:
        return FlagPosition.none;
    }
  }

  bool get isMissingFlagColorDuringSurveillance {
    return isPosteSecours &&
        _isCurrentlyInSurveillanceWindow() &&
        flagPosition != FlagPosition.affale &&
        flagColor == FlagColor.none;
  }

  bool get hasValidFlag {
    return isPosteSecours &&
        _isCurrentlyInSurveillanceWindow() &&
        flagColor != FlagColor.none &&
        flagPosition == FlagPosition.hisse;
  }

  String get displayLine2 {
    if (!isPosteSecours) return typeSphot;

    final parts = <String>['🚨 POSTE DE SECOURS 🚨'];

    if (phone.trim().isNotEmpty) {
      parts.add('📞 $phone');
    }

    if (heureDebut.trim().isNotEmpty && heureFin.trim().isNotEmpty) {
      parts.add('🕘 $heureDebut - $heureFin');
    }

    return parts.join(' - ');
  }

  String get displayStatut {
    if (!isPosteSecours || !_isCurrentlyInSurveillanceWindow()) {
      return '⚠️ BAIGNADE NON SURVEILLÉE ⚠️ BAIGNADE À VOS RISQUES ET PÉRILS';
    }

    if (flagPosition == FlagPosition.affale) {
      return '⚠️ BAIGNADE NON SURVEILLÉE TEMPORAIREMENT ⚠️ BAIGNADE À VOS RISQUES ET PÉRILS';
    }

    if (flagColor == FlagColor.none) {
      return 'COULEUR DE LA FLAMME NON RENSEIGNÉE';
    }

    switch (flagColor) {
      case FlagColor.green:
        return 'BAIGNADE SURVEILLÉE ET AUTORISÉE';
      case FlagColor.yellow:
        return 'BAIGNADE SURVEILLÉE MAIS DANGEREUSE';
      case FlagColor.red:
        return 'BAIGNADE INTERDITE';
      case FlagColor.violet:
        return 'BAIGNADE INTERDITE - POLLUTION OU PRÉSENCE D’ESPÈCES DANGEREUSES';
      case FlagColor.none:
        return 'COULEUR DE LA FLAMME NON RENSEIGNÉE';
    }
  }

  int get statutColor {
    if (!isPosteSecours) return 0xFFFF0000;
    if (!_isCurrentlyInSurveillanceWindow()) return 0xFFFF0000;
    if (flagPosition == FlagPosition.affale) return 0xFFFF0000;
    if (flagColor == FlagColor.none) return 0xFFFF0000;

    switch (flagColor) {
      case FlagColor.green:
        return 0xFF22C55E;
      case FlagColor.yellow:
        return 0xFFF59E0B;
      case FlagColor.red:
        return 0xFFFF0000;
      case FlagColor.violet:
        return 0xFFD946EF;
      case FlagColor.none:
        return 0xFFFF0000;
    }
  }

  bool _isCurrentlyInSurveillanceWindow() {
    final now = DateTime.now();

    if (periode.trim().isNotEmpty) {
      final parts = periode.split('-');

      if (parts.length >= 2) {
        final start = _parseFrenchDate(parts[0].trim());
        final end = _parseFrenchDate(parts[1].trim());

        if (start != null && end != null) {
          final startDay = DateTime(start.year, start.month, start.day);
          final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);

          if (now.isBefore(startDay) || now.isAfter(endDay)) {
            return false;
          }
        }
      }
    }

    if (heureDebut.trim().isNotEmpty && heureFin.trim().isNotEmpty) {
      final startTime = _parseHour(heureDebut);
      final endTime = _parseHour(heureFin);

      if (startTime != null && endTime != null) {
        final start = DateTime(
          now.year,
          now.month,
          now.day,
          startTime.$1,
          startTime.$2,
        );

        final end = DateTime(
          now.year,
          now.month,
          now.day,
          endTime.$1,
          endTime.$2,
        );

        if (now.isBefore(start) || now.isAfter(end)) {
          return false;
        }
      }
    }

    return true;
  }

  static DateTime? _parseFrenchDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);

    if (day == null || month == null || year == null) return null;

    return DateTime(year, month, day);
  }

  static (int, int)? _parseHour(String value) {
    final clean = value.trim().toLowerCase().replaceAll('h', ':');
    final parts = clean.split(':');

    final hour = int.tryParse(parts[0]);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (hour == null) return null;

    return (hour, minute);
  }

  static String _readString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static double _readDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0.0;
  }
}

enum FlagColor {
  green,
  yellow,
  red,
  violet,
  none,
}

enum FlagPosition {
  hisse,
  affale,
  none,
}