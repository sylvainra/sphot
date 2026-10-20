import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Comparaison en lecture seule avant la décision du Super Admin.
class AdvertiserAssetComparison extends StatelessWidget {
  const AdvertiserAssetComparison({
    super.key,
    required this.previousVisualUrl,
    required this.proposedVisualUrl,
    required this.previousLocation,
    required this.proposedLocation,
    required this.onEnlarge,
  });

  final String previousVisualUrl;
  final String proposedVisualUrl;
  final LatLng? previousLocation;
  final LatLng? proposedLocation;
  final ValueChanged<String> onEnlarge;

  bool get _sameVisual =>
      previousVisualUrl.isNotEmpty && previousVisualUrl == proposedVisualUrl;
  bool get _samePosition {
    if (previousLocation == null || proposedLocation == null) {
      return false;
    }
    return const Distance().as(
          LengthUnit.Meter,
          previousLocation!,
          proposedLocation!,
        ) < 1;
  }

  Widget _visual(String title, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 128,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD9E2EC)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: url.isEmpty
              ? const Center(
                  child: Text(
                    'Indisponible',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : Image.network(
                  url,
                  fit: BoxFit.contain,
                  // Même mode Web que le dialogue d'agrandissement :
                  // évite les échecs de chargement de certains visuels.
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Visuel inaccessible'),
                  ),
                ),
        ),
        const SizedBox(height: 7),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: url.isEmpty ? null : () => onEnlarge(url),
            icon: const Icon(Icons.open_in_full_rounded, size: 15),
            label: const Text(
              'AGRANDIR LE VISUEL',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _position(String title, LatLng? point) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.place_outlined, color: Color(0xFF1E3A8A),
              size: 19),
          const SizedBox(width: 7),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 12)),
              Text(point == null ? 'Position non renseignée' :
                  '${point.latitude.toStringAsFixed(6)}, '
                  '${point.longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12)),
            ],
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = previousLocation;
    final b = proposedLocation;
    final center = a != null && b != null ?
        LatLng((a.latitude + b.latitude) / 2,
            (a.longitude + b.longitude) / 2) : (a ?? b);
    final distance = a != null && b != null ?
        const Distance().as(LengthUnit.Meter, a, b) : null;
    final zoom = distance == null || distance < 800 ? 13.0 :
        distance < 5000 ? 11.0 : distance < 25000 ? 9.0 : 6.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        border: Border.all(color: const Color(0xFF1E3A8A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('COMPARAISON AVANT / APRÈS',
              style: TextStyle(color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const Text('VISUELS', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          _visual('AVANT — ACTUEL', previousVisualUrl),
          const SizedBox(height: 16),
          _visual('APRÈS — PROPOSÉ', proposedVisualUrl),
          if (_sameVisual)
            const Text('Visuel inchangé',
                style: TextStyle(color: Color(0xFF15803D))),
          const Divider(height: 24),
          const Text('POSITIONS', style: TextStyle(fontWeight: FontWeight.w800)),
          _position('Position actuelle', a),
          _position('Position proposée', b),
          if (_samePosition)
            const Text('Position inchangée',
                style: TextStyle(color: Color(0xFF15803D))),
          if (distance != null && !_samePosition)
            Text('Déplacement : ${distance < 1000 ?
                '${distance.toStringAsFixed(0)} m' :
                '${(distance / 1000).toStringAsFixed(2)} km'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          if (center != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(height: 200, child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
                  initialCameraFit: a != null && b != null && !_samePosition
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints([a, b]),
                          padding: const EdgeInsets.all(52),
                        )
                      : null,
                  minZoom: 2,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.sylvainra.sphot',
                  ),
                  MarkerLayer(markers: [
                    if (a != null) Marker(point: a, width: 42, height: 42,
                        child: const Icon(Icons.location_pin,
                            color: Color(0xFF1E3A8A), size: 36)),
                    if (b != null && !_samePosition)
                      Marker(point: b, width: 42, height: 42,
                        child: const Icon(Icons.location_pin,
                            color: Color(0xFF15803D), size: 36)),
                  ]),
                ],
              )),
            ),
            const SizedBox(height: 5),
            Text(_samePosition
                ? 'Bleu : position inchangée'
                : 'Bleu : avant   ·   Vert : après',
                style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
