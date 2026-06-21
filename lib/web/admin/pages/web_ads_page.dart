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

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'pending_review':
      case 'pending_payment':
        return Colors.orange;
      case 'rejected':
      case 'cancelled':
        return redColor;
      case 'paused':
        return adminColor;
      case 'ended':
        return Colors.grey;
      default:
        return adminColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'BROUILLON';
      case 'pending_payment':
        return 'PAIEMENT EN ATTENTE';
      case 'pending_review':
        return 'À VÉRIFIER';
      case 'active':
        return 'ACTIVE';
      case 'paused':
        return 'SUSPENDUE';
      case 'rejected':
        return 'REJETÉE';
      case 'ended':
        return 'TERMINÉE';
      case 'cancelled':
        return 'ANNULÉE';
      default:
        return status.isEmpty ? 'INCONNU' : status.toUpperCase();
    }
  }

  Widget _collectionList({
    required String collection,
    required String emptyText,
    required bool Function(Map<String, dynamic> data) filter,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
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
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    color: _statusColor(status),
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _text(data['title']).isEmpty
                              ? 'Campagne sans titre'
                              : _text(data['title']).toUpperCase(),
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Annonceur : ${_text(data['advertiserName'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Catégorie : ${_text(data['category'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Emplacement : ${_text(data['placementType'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Zone : ${_text(data['targetCountry'])} / '
                          '${_text(data['targetRegion'])} / '
                          '${_text(data['targetDepartment'])} / '
                          '${_text(data['targetCity'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Diffusion : ${_formatDate(data['startDate'])} → '
                          '${_formatDate(data['endDate'])}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
          collection: 'adRequests',
          emptyText: 'Aucune demande Ads pour le moment.',
          filter: (_) => true,
        );
      case 1:
        return _collectionList(
          collection: 'campaigns',
          emptyText: 'Aucune campagne active.',
          filter: (data) => _text(data['status']) == 'active',
        );
      case 2:
        return _collectionList(
          collection: 'campaigns',
          emptyText: 'Aucune campagne à vérifier.',
          filter: (data) => _text(data['status']) == 'pending_review',
        );
      case 3:
        return _collectionList(
          collection: 'campaigns',
          emptyText: 'Aucune campagne rejetée.',
          filter: (data) => _text(data['status']) == 'rejected',
        );
      default:
        return _collectionList(
          collection: 'adRequests',
          emptyText: 'Aucune demande Ads pour le moment.',
          filter: (_) => true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
         
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tabButton('DEMANDES ADS', 0),
              _tabButton('CAMPAGNES ACTIVES', 1),
              _tabButton('À VÉRIFIER', 2),
              _tabButton('REJETÉES', 3),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _selectedContent()),
        ],
      ),
    );
  }
}