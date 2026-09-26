import 'package:shared_preferences/shared_preferences.dart';

class PublicFavoritesService {
  static const String storageKey = 'sphot_public_favorite_ids';

  static Future<Set<String>> loadFavoriteIds() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(storageKey) ?? const <String>[])
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  static Future<bool> contains(String spotId) async {
    final favorites = await loadFavoriteIds();
    return favorites.contains(spotId);
  }

  static Future<bool> toggle(String spotId) async {
    final preferences = await SharedPreferences.getInstance();
    final favorites = (preferences.getStringList(storageKey) ?? const <String>[])
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    final nextSaved = !favorites.contains(spotId);

    if (nextSaved) {
      favorites.add(spotId);
    } else {
      favorites.remove(spotId);
    }

    await preferences.setStringList(
      storageKey,
      favorites.toList(growable: false),
    );

    return nextSaved;
  }
}
