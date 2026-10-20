import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Lecture seule : montre ce qui est actuellement approuvé et ce qui est
/// proposé. Aucun état commercial ni aucune position n'est modifié ici.
class AdvertiserAssetComparisonPanel extends StatelessWidget {
  const AdvertiserAssetComparisonPanel({
    super.key,
    required this.currentVisualUrl,
    required this.proposedVisualUrl,
    required this.currentLocation,
    required this.proposedLocation,
    required this.onEnlargeVisual,
  });

  final String currentVisualUrl;
  final String proposedVisualUrl;
  final Map<String, dynamic> currentLocation;
  final Map<String, dynamic> proposedLocation;
  final ValueChanged<String> onEnlargeVisual;

  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _green = Color(0xFF15803D);

  double? _coordinate(Map<String, dynamic> data, String key) {
    final value = data[key];
    final result = value is num
        ? value.toDouble()
        : double.tryParse((value ?? '').toString());
    if (result == null || !result.isFinite) return null;
    if (key == 'latitude' && (result < -90 || result > 90)) return null;
    if (key == 'longitude' && (result < -180 || result > 180)) return null;
    return result;
  }

  LatLng? _point(Map<String, dynamic> location) {
    final lat = _coordinate(location, 'latitude');
    final lng = _coordinate(location, 'longitude');
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  String _coordinates(LatLng? point) {
    if (point == null) return 'Position non disponible';
    return '${point.latitude.toStringAsFixed(6)}, '
        '${point.longitude.toStringAsFixed(6)}';
  }

  Widget _visualCard(String title, String url, Color color) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 76,
            child: url.isEmpty
                ? const Center(
                    child: Text(
                      'Visuel non disponible',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.contain,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'Impossible de charger le visuel',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 5),
          TextButton.icon(
            onPressed: url.isEmpty ? null : () => onEnlargeVisual(url),
            icon: const Icon(Icons.open_in_full_rounded, size: 14),
            label: const Text('AGRANDIR', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Marker _marker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 86,
      height: 65,
      child: Column(
        children: [
          Icon(Icons.location_on_rounded, size: 32, color: color),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oldPoint = _point(currentLocation);
    final newPoint = _point(proposedLocation);
    final imageUnchanged = currentVisualUrl.isNotEmpty &&
        currentVisualUrl == proposedVisualUrl;
    final distanceMeters = oldPoint != null && newPoint != null
        ? const Distance().as(LengthUnit.Meter, oldPoint, newPoint)
        : null;
    final positionUnchanged = distanceMeters != null &&
        distanceMeters < 0.1;

    final markers = <Marker>[
      if (oldPoint != null)
        _marker(
          oldPoint,
          positionUnchanged ? 'INCHANGÉE' : 'AVANT',
          _blue,
        ),
      if (newPoint != null && !positionUnchanged)
        _marker(newPoint, 'APRÈS', _green),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        border: Border.all(color: _blue.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'COMPARAISON AVANT / APRÈS',
            style: TextStyle(
              color: _blue,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'VISUELS PUBLICITAIRES',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _visualCard(
                  'AVANT - ACTUEL',
                  currentVisualUrl,
                  _blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _visualCard(
                  'APRÈS - PROPOSÉ',
                  proposedVisualUrl,
                  _green,
                ),
              ),
            ],
          ),
          if (imageUnchanged)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'Visuel inchangé',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'POSITIONS GÉOGRAPHIQUES',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'AVANT : ${_coordinates(oldPoint)}',
            style: const TextStyle(color: _blue, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'APRÈS : ${_coordinates(newPoint)}',
            style: const TextStyle(color: _green, fontSize: 11),
          ),
          const SizedBox(height: 6),
          if (positionUnchanged)
            const Text(
              'Position inchangée',
              style: TextStyle(
                color: _blue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (distanceMeters != null)
            Text(
              distanceMeters < 1000
                  ? 'Déplacement : ${distanceMeters.toStringAsFixed(0)} m'
                  : 'Déplacement : '
                      '${(distanceMeters / 1000).toStringAsFixed(2)} km',
              style: const TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 8),
          if (oldPoint != null || newPoint != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 210,
                child: FlutterMap(
                  key: ValueKey(
                    '${_coordinates(oldPoint)}:${_coordinates(newPoint)}',
                  ),
                  options: MapOptions(
                    initialCenter: oldPoint ?? newPoint!,
                    initialZoom: 13,
                    initialCameraFit: oldPoint != null &&
                            newPoint != null &&
                            !positionUnchanged
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(
                              [oldPoint, newPoint],
                            ),
                            padding: const EdgeInsets.all(50),
                          )
                        : null,
                    minZoom: 2,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.sylvainra.sphot',
                    ),
                    MarkerLayer(markers: markers),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            const Text(
              'Aucune position vérifiable pour cette proposition.',
              style: TextStyle(color: Colors.red, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
