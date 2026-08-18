import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/flag_state.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<SpotFlagState>> getSpotsStream() {
    return _firestore.collection('publicSpots').snapshots().map((snapshot) {
      const territoryFields = <String>[
        'pays',
        'region',
        'departement',
        'ville',
        'villeLat',
        'villeLng',
        'departementLat',
        'departementLng',
        'logoVille',
        'siteInternetVille',
        'arretesMunicipaux',
      ];
      final territoryDefaults = <String, Map<String, dynamic>>{};

      for (final document in snapshot.docs) {
        final data = document.data();
        final territoryId = _territoryId(document.id, data);
        if (territoryId.isEmpty) continue;

        final defaults = territoryDefaults.putIfAbsent(
          territoryId,
          () => <String, dynamic>{},
        );
        for (final field in territoryFields) {
          final value = data[field];
          if (_isEmptyPublicValue(field, defaults[field]) &&
              !_isEmptyPublicValue(field, value)) {
            defaults[field] = value;
          }
        }
      }

      return snapshot.docs.map((document) {
        final data = Map<String, dynamic>.from(document.data());
        final territoryId = _territoryId(document.id, data);
        final defaults = territoryDefaults[territoryId];

        if (territoryId.isNotEmpty &&
            _isEmptyPublicValue('territoireId', data['territoireId'])) {
          data['territoireId'] = territoryId;
        }
        if (defaults != null) {
          for (final field in territoryFields) {
            if (_isEmptyPublicValue(field, data[field]) &&
                !_isEmptyPublicValue(field, defaults[field])) {
              data[field] = defaults[field];
            }
          }
        }

        return SpotFlagState.fromFirestore(document.id, data);
      }).toList(growable: false);
    });
  }

  static String _territoryId(String documentId, Map<String, dynamic> data) {
    final storedId = (data['territoireId'] ?? '').toString().trim();
    if (storedId.isNotEmpty) return storedId;

    final separatorIndex = documentId.indexOf('__');
    if (separatorIndex <= 0) return '';
    return documentId.substring(0, separatorIndex).trim();
  }

  static bool _isEmptyPublicValue(String field, dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if ((field.endsWith('Lat') || field.endsWith('Lng')) && value is num) {
      return value == 0;
    }
    return false;
  }
}


