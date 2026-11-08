import 'package:shared_preferences/shared_preferences.dart';

/// Versions effectivement publiées, distinctes des brouillons éditoriaux.
class PublicLegalVersions {
  const PublicLegalVersions({
    required this.cgu,
    required this.privacyPolicy,
    required this.rgpdNotice,
  });

  final String cgu;
  final String privacyPolicy;
  final String rgpdNotice;
}

enum PublicLegalAccessDecision {
  acceptCgu,
  acknowledgeInformationUpdate,
  allowAccess,
}

/// Mémorisation par navigateur / installation, sans compte ni identifiant public.
/// Elle ne constitue pas une preuve d'acceptation nominative centralisée.
class PublicLegalAcceptanceService {
  const PublicLegalAcceptanceService();

  static const _cguKey = 'sphot_public_cgu_accepted_version_v1';
  static const _privacyKey = 'sphot_public_privacy_seen_version_v1';
  static const _rgpdKey = 'sphot_public_rgpd_seen_version_v1';
  static const _acceptedAtKey = 'sphot_public_cgu_accepted_at_v1';
  static const _informationSeenAtKey =
      'sphot_public_legal_information_seen_at_v1';

  Future<PublicLegalAccessDecision> accessDecision(
    PublicLegalVersions current,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    if (preferences.getString(_cguKey) != current.cgu) {
      return PublicLegalAccessDecision.acceptCgu;
    }

    if (preferences.getString(_privacyKey) != current.privacyPolicy ||
        preferences.getString(_rgpdKey) != current.rgpdNotice) {
      return PublicLegalAccessDecision.acknowledgeInformationUpdate;
    }

    return PublicLegalAccessDecision.allowAccess;
  }

  Future<void> accept(PublicLegalVersions current) async {
    final preferences = await SharedPreferences.getInstance();
    await _save(preferences, _privacyKey, current.privacyPolicy);
    await _save(preferences, _rgpdKey, current.rgpdNotice);
    await _save(
      preferences,
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    // La CGU est marquée acceptée en dernier : si une écriture échoue,
    // l'accès reste soumis à une nouvelle validation au prochain lancement.
    await _save(preferences, _cguKey, current.cgu);
  }

  Future<void> acknowledgeInformationUpdate(PublicLegalVersions current) async {
    final preferences = await SharedPreferences.getInstance();
    await _save(preferences, _privacyKey, current.privacyPolicy);
    await _save(preferences, _rgpdKey, current.rgpdNotice);
    await _save(
      preferences,
      _informationSeenAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _save(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Enregistrement local indisponible : $key');
    }
  }
}
