import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../shared/web_colors.dart';

class AdvertisingSpotSection extends StatefulWidget {
  const AdvertisingSpotSection({
    super.key,
    required this.user,
    required this.position,
    required this.onPositionChanged,
  });

  final User? user;
  final LatLng? position;
  final void Function(LatLng point, {required bool centerMap})
      onPositionChanged;

  @override
  State<AdvertisingSpotSection> createState() =>
      _AdvertisingSpotSectionState();
}

class _AdvertisingSpotSectionState extends State<AdvertisingSpotSection> {
  final _referenceController = TextEditingController();

  bool _loading = true;
  bool _searching = false;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  bool _loadingSavedPosition = false;
  String? _resolvedAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialiseSpot();
  }

  @override
  void didUpdateWidget(covariant AdvertisingSpotSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position == widget.position) return;
    if (_loadingSavedPosition) {
      _loadingSavedPosition = false;
      return;
    }
    _completed = false;
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _initialiseSpot() async {
    final user = widget.user;
    if (user != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          final establishment = _map(data['establishment']);
          final advertisingSpot = _map(data['advertisingSpot']);

          final savedReference = _read(advertisingSpot['referenceLabel']);
          final establishmentAddress = _composeAddress(establishment);
          _referenceController.text = savedReference.isNotEmpty
              ? savedReference
              : establishmentAddress;
          _resolvedAddress = _nullableRead(
            advertisingSpot['resolvedAddress'],
          );

          final latitude = _toDouble(advertisingSpot['latitude']);
          final longitude = _toDouble(advertisingSpot['longitude']);
          if (latitude != null && longitude != null) {
            final savedPoint = LatLng(latitude, longitude);
            _loadingSavedPosition = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onPositionChanged(savedPoint, centerMap: true);
            });
          }
          _completed = data['advertisingSpotCompleted'] == true &&
              latitude != null &&
              longitude != null;
        }
      } catch (error) {
        _error = 'Impossible de charger le SPHOT publicitaire enregistré.';
        debugPrint('Chargement SPHOT publicitaire impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String _read(Object? value) => value?.toString().trim() ?? '';

  String? _nullableRead(Object? value) {
    final text = _read(value);
    return text.isEmpty ? null : text;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _composeAddress(Map<String, dynamic> establishment) {
    return [
      _read(establishment['businessName']),
      _read(establishment['address']),
      _read(establishment['addressComplement']),
      [
        _read(establishment['postalCode']),
        _read(establishment['city']),
      ].where((part) => part.isNotEmpty).join(' '),
      _read(establishment['country']),
    ].where((part) => part.isNotEmpty).join(', ');
  }

  void _markAsModified(String _) {
    if (_completed) setState(() => _completed = false);
  }

  Future<void> _searchReference() async {
    final query = _referenceController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Saisissez une adresse, une commune ou un lieu.');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'limit': '1',
          'countrycodes': 'fr',
        },
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'SPHOT advertiser portal'},
      );
      if (response.statusCode != 200) {
        throw Exception('Erreur géocodage ${response.statusCode}');
      }

      final results = jsonDecode(response.body) as List<dynamic>;
      if (results.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'Lieu introuvable. Précisez votre recherche.');
        return;
      }

      final result = Map<String, dynamic>.from(results.first as Map);
      final latitude = double.tryParse(result['lat'].toString());
      final longitude = double.tryParse(result['lon'].toString());
      if (latitude == null || longitude == null) {
        throw Exception('Coordonnées invalides');
      }

      final point = LatLng(latitude, longitude);
      if (!mounted) return;
      setState(() {
        _resolvedAddress = _read(result['display_name']);
        _completed = false;
      });
      widget.onPositionChanged(point, centerMap: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de localiser ce lieu pour le moment.';
      });
      debugPrint('Localisation SPHOT publicitaire impossible : $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final position = widget.position;
    if (position == null) {
      setState(() {
        _error = 'Recherchez un lieu ou cliquez sur la carte pour le positionner.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = widget.user;
      if (user != null) {
        final creationData = _requestExists
            ? <String, Object?>{}
            : <String, Object?>{
                'status': 'pending',
                'createdAt': FieldValue.serverTimestamp(),
              };
        await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .set({
          ...creationData,
          'uid': user.uid,
          'advertisingSpotCompleted': true,
          'advertisingSpot': <String, Object?>{
            'referenceLabel': _referenceController.text.trim(),
            'resolvedAddress': _resolvedAddress,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'confirmedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() => _completed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SPHOT publicitaire enregistré.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement SPHOT publicitaire impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: WebColors.red),
        ),
      );
    }

    final position = widget.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpotCard(
          icon: Icons.search_rounded,
          title: 'RECHERCHER L’ÉTABLISSEMENT',
          status: _completed ? 'POSITION CONFIRMÉE' : 'À POSITIONNER',
          statusColor: _completed
              ? const Color(0xFF15803D)
              : const Color(0xFF6B7280),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referenceController,
                      onChanged: _markAsModified,
                      onSubmitted: (_) => _searchReference(),
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _fieldDecoration(
                        'Adresse, commune ou lieu de référence',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _searching ? null : _searchReference,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(
                          color: WebColors.blue,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: WebColors.blue,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.search_rounded,
                              color: WebColors.red,
                              size: 27,
                            ),
                    ),
                  ),
                ],
              ),
              if (_resolvedAddress != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _resolvedAddress!,
                    style: const TextStyle(
                      color: WebColors.blue,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _SpotCard(
          iconWidget: SvgPicture.asset(
            'data/icons/fire_blue_icon.svg',
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
          title: 'POSITION SUR LA CARTE',
          status: position == null ? 'AUCUNE POSITION' : 'POSITION DÉFINIE',
          statusColor: position == null
              ? const Color(0xFF6B7280)
              : const Color(0xFF15803D),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Déplacez et zoomez la grande carte, puis cliquez à l’emplacement exact de l’établissement.',
                style: TextStyle(
                  color: Color(0xFF4B5F97),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _CoordinateLine(
                label: 'Latitude',
                value: position?.latitude.toStringAsFixed(6),
              ),
              _CoordinateLine(
                label: 'Longitude',
                value: position?.longitude.toStringAsFixed(6),
                isLast: true,
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _completed ? WebColors.red : WebColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _completed
                        ? Icons.check_circle_outline_rounded
                        : Icons.save_outlined,
                  ),
            label: Text(
              _saving
                  ? 'ENREGISTREMENT…'
                  : _completed
                      ? 'SPHOT PUBLICITAIRE ENREGISTRÉ'
                      : 'ENREGISTRER LE SPHOT PUBLICITAIRE',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF4B5F97)),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 1.6),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 1.6),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 2),
    ),
  );
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    this.icon,
    this.iconWidget,
    required this.title,
    required this.status,
    required this.child,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String status;
  final Widget child;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: iconWidget ??
                    Icon(icon, color: WebColors.blue, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CoordinateLine extends StatelessWidget {
  const _CoordinateLine({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String? value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5F97),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Non définie',
              style: const TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
