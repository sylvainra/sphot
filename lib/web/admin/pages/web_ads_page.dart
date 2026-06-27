import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class WebAdsPage extends StatefulWidget {
  const WebAdsPage({super.key});

  @override
  State<WebAdsPage> createState() => _WebAdsPageState();
}

class _WebAdsPageState extends State<WebAdsPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  int _selectedTab = 0;

  String _text(dynamic value) => (value ?? '').toString();

  String _formatDate(dynamic value) {
    if (value == null) return '—';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String && value.trim().isNotEmpty) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return '—';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'disabled':
        return Colors.orange;
      case 'reported':
        return redColor;
      case 'deleted':
        return Colors.grey;
      default:
        return adminColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'ACTIVE';
      case 'disabled':
        return 'DÉSACTIVÉE';
      case 'reported':
        return 'SIGNALÉE';
      case 'deleted':
        return 'SUPPRIMÉE';
      default:
        return status.isEmpty ? 'INCONNU' : status.toUpperCase();
    }
  }

  Future<void> _updateStatus(
    String docId,
    String status, {
    String? reason,
  }) async {
    await FirebaseFirestore.instance.collection('adRequests').doc(docId).update({
      'status': status,
      'disabledReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteAd(String docId) async {
    await FirebaseFirestore.instance.collection('adRequests').doc(docId).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;

    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedTab = index;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? adminColor : Colors.transparent,
        foregroundColor: selected ? Colors.white : adminColor,
        side: const BorderSide(color: adminColor, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _collectionList({
    required String emptyText,
    required bool Function(Map<String, dynamic> data) filter,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adRequests').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Erreur de chargement.',
              style: TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          return filter(doc.data());
        }).toList();

        docs.sort((a, b) {
          final left = a.data()['createdAt'];
          final right = b.data()['createdAt'];

          if (left is Timestamp && right is Timestamp) {
            return right.compareTo(left);
          }

          return 0;
        });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              emptyText,
              style: const TextStyle(
                color: adminColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(top: 4),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();

            final status = _text(data['status']);
            final bannerUrl = _text(data['bannerUrl']);
            final broadcastType = _text(data['broadcastType']);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _statusColor(status),
                  width: 2,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 170,
                    height: 85,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: adminColor,
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: bannerUrl.isEmpty
                          ? const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: adminColor,
                                size: 36,
                              ),
                            )
                          : Image.network(
                              bannerUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: redColor,
                                    size: 36,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _text(data['advertiserName']).isEmpty
                              ? 'Annonceur inconnu'
                              : _text(data['advertiserName']).toUpperCase(),
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Contact : ${_text(data['contactName'])} • ${_text(data['email'])} • ${_text(data['phone'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Site : ${_text(data['websiteUrl']).isEmpty ? '—' : _text(data['websiteUrl'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'SIREN : ${_text(data['siren'])} • SIRET : ${_text(data['siret'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Catégorie : ${_text(data['categoryLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Visibilité : ${_text(data['visibilityLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          broadcastType == 'national'
                              ? 'Zone : Diffusion nationale'
                              : 'Zone : ${_text(data['centerCity']).isEmpty ? 'Localisation carte' : _text(data['centerCity'])} • Rayon ${_text(data['radiusKm'])} km',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Diffusion : ${_formatDate(data['campaignStartDate'])} → ${_formatDate(data['campaignEndDate'])} • ${_text(data['durationLabel'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Montant : ${_text(data['totalPriceExclTax'])} € HT',
                          style: const TextStyle(
                            color: redColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_text(data['message']).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Message : ${_text(data['message'])}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (status != 'active')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(doc.id, 'active'),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('RÉACTIVER'),
                        ),
                      if (status == 'active')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(
                            doc.id,
                            'disabled',
                            reason: 'Désactivée par Super Admin',
                          ),
                          icon: const Icon(Icons.pause_rounded),
                          label: const Text('DÉSACTIVER'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _updateStatus(doc.id, 'reported'),
                        icon: const Icon(Icons.report_outlined),
                        label: const Text('SIGNALER'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _deleteAd(doc.id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('SUPPRIMER'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _selectedContent() {
    switch (_selectedTab) {
      case 0:
        return _collectionList(
          emptyText: 'Aucune publicité pour le moment.',
          filter: (data) => _text(data['status']) != 'deleted',
        );
      case 1:
        return _collectionList(
          emptyText: 'Aucune publicité active.',
          filter: (data) => _text(data['status']) == 'active',
        );
      case 2:
        return _collectionList(
          emptyText: 'Aucune publicité désactivée.',
          filter: (data) => _text(data['status']) == 'disabled',
        );
      case 3:
        return _collectionList(
          emptyText: 'Aucune publicité signalée.',
          filter: (data) => _text(data['status']) == 'reported',
        );
      default:
        return _collectionList(
          emptyText: 'Aucune publicité pour le moment.',
          filter: (data) => _text(data['status']) != 'deleted',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Text(
            'PUBLICITÉS SPHOT',
            style: TextStyle(
              color: adminColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tabButton('TOUTES', 0),
              _tabButton('ACTIVES', 1),
              _tabButton('DÉSACTIVÉES', 2),
              _tabButton('SIGNALÉES', 3),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _selectedContent()),
        ],
      ),
    );
  }
}