import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Contours Natural Earth 1:110m : carte indicative, pas frontière légale.
/// Source de données publique et mondiale (domaine public).
/// Les frontières sont chargées une fois et réutilisées en mémoire.
class AdvertiserCountryBoundary {
  const AdvertiserCountryBoundary({
    required this.iso3,
    required this.name,
    required this.polygons,
  });

  final String iso3;
  final String name;
  final List<List<LatLng>> polygons;

  List<LatLng> get allPoints => [
        for (final polygon in polygons) ...polygon,
      ];

  /// Test de présence dans au moins une composante du pays.
  bool contains(LatLng point) =>
      polygons.any((polygon) => _insidePolygon(point, polygon));

  static bool _insidePolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1;
        i < polygon.length;
        j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses = (a.latitude > point.latitude) !=
          (b.latitude > point.latitude);
      if (!crosses) continue;
      final x = (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (point.longitude < x) inside = !inside;
    }
    return inside;
  }

  /// Tolérance cartographique pour les plages proches des côtes, car la
  /// généralisation 1:110m ne correspond pas exactement à la côte réelle.
  double closestBoundaryKm(LatLng point) {
    var best = double.infinity;
    final latFactor = 111.195;
    final lonFactor =
        latFactor * math.cos(point.latitude * math.pi / 180).abs();
    for (final ring in polygons) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final x1 = (a.longitude - point.longitude) * lonFactor;
        final y1 = (a.latitude - point.latitude) * latFactor;
        final x2 = (b.longitude - point.longitude) * lonFactor;
        final y2 = (b.latitude - point.latitude) * latFactor;
        final dx = x2 - x1;
        final dy = y2 - y1;
        final norm = dx * dx + dy * dy;
        final t = norm == 0
            ? 0.0
            : (-x1 * dx - y1 * dy).clamp(0.0, norm) / norm;
        final distance =
            math.sqrt(math.pow(x1 + dx * t, 2) + math.pow(y1 + dy * t, 2));
        if (distance < best) best = distance;
      }
    }
    return best;
  }
}

class AdvertiserCountryBoundaryService {
  AdvertiserCountryBoundaryService({http.Client? client}) : _client = client;

  final http.Client? _client;
  static Future<List<AdvertiserCountryBoundary>>? _cachedWorld;
  static const sourceUrl =
      'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/'
      'master/geojson/ne_110m_admin_0_countries.geojson';

  Future<List<AdvertiserCountryBoundary>> _download() async {
    final ownClient = _client ?? http.Client();
    try {
      final response = await ownClient
          .get(Uri.parse(sourceUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Frontières indisponibles (HTTP ${response.statusCode}).');
      }
      return parseFeatureCollection(jsonDecode(utf8.decode(response.bodyBytes)));
    } finally {
      if (_client == null) ownClient.close();
    }
  }

  Future<List<AdvertiserCountryBoundary>> countries() async {
    // Les clients de tests ne partagent jamais le cache de production.
    if (_client != null) return _download();
    final pending = _cachedWorld ??= _download();
    try {
      return await pending;
    } catch (_) {
      if (identical(_cachedWorld, pending)) _cachedWorld = null;
      rethrow;
    }
  }

  Future<AdvertiserCountryBoundary?> findAt(LatLng position) async {
    final boundaries = await countries();
    for (final boundary in boundaries) {
      if (boundary.contains(position)) return boundary;
    }
    // Une plage peut être quelques kilomètres hors du contour simplifié.
    // Ne jamais inventer de pays si l'écart dépasse 12 km.
    AdvertiserCountryBoundary? nearest;
    var distance = 12.0;
    for (final boundary in boundaries) {
      final candidate = boundary.closestBoundaryKm(position);
      if (candidate < distance) {
        distance = candidate;
        nearest = boundary;
      }
    }
    return nearest;
  }

  Future<AdvertiserCountryBoundary?> findByIso3(String code) async {
    final countries = await this.countries();
    for (final boundary in countries) {
      if (boundary.iso3 == code.toUpperCase()) return boundary;
    }
    return null;
  }

  static List<AdvertiserCountryBoundary> parseFeatureCollection(Object? data) {
    if (data is! Map || data['features'] is! List) {
      throw const FormatException('Catalogue GeoJSON mondial invalide.');
    }
    final byCountry = <String, AdvertiserCountryBoundary>{};
    for (final rawFeature in data['features'] as List) {
      if (rawFeature is! Map) continue;
      final properties = rawFeature['properties'];
      final geometry = rawFeature['geometry'];
      if (properties is! Map || geometry is! Map) continue;
      final iso3 = (properties['ADM0_A3'] ??
              properties['ISO_A3'] ??
              '')
          .toString()
          .toUpperCase();
      final name = (properties['ADMIN'] ?? properties['NAME'] ?? '')
          .toString()
          .trim();
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(iso3) || name.isEmpty) {
        continue;
      }
      final polygons = <List<LatLng>>[];
      final coordinates = geometry['coordinates'];
      if (coordinates is! List) continue;
      final figures = geometry['type'] == 'Polygon'
          ? <dynamic>[coordinates]
          : geometry['type'] == 'MultiPolygon'
              ? coordinates
              : <dynamic>[];
      for (final figure in figures) {
        if (figure is! List || figure.isEmpty) continue;
        final exterior = figure.first;
        if (exterior is! List) continue;
        final points = <LatLng>[];
        for (final rawPoint in exterior) {
          if (rawPoint is! List || rawPoint.length < 2) continue;
          final lng = rawPoint[0];
          final lat = rawPoint[1];
          if (lat is num && lng is num &&
              lat >= -90 && lat <= 90 &&
              lng >= -180 && lng <= 180) {
            points.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        }
        if (points.length >= 3) polygons.add(points);
      }
      if (polygons.isNotEmpty) {
        final existing = byCountry[iso3];
        byCountry[iso3] = AdvertiserCountryBoundary(
          iso3: iso3,
          name: existing?.name ?? name,
          // Toutes les composantes portant ce code pays restent couvertes.
          polygons: [...?existing?.polygons, ...polygons],
        );
      }
    }
    if (byCountry.isEmpty) {
      throw const FormatException('Aucun pays exploitable dans le GeoJSON.');
    }
    return byCountry.values.toList();
  }
}
