import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SuperAdminDashboardFinancesPage extends StatelessWidget {
  const SuperAdminDashboardFinancesPage({super.key});

  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  int _price(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  String _money(int value) {
    return '${value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]} ',
        )} €';
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    Color color = adminColor,
  }) {
    return Expanded(
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Text(
        title,
        style: TextStyle(
          color: adminColor.withOpacity(0.95),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adStream =
        FirebaseFirestore.instance.collection('adRequests').snapshots();
    final subscriptionsStream =
        FirebaseFirestore.instance.collection('subscriptions').snapshots();
    final adminsStream =
        FirebaseFirestore.instance.collection('admins').snapshots();
    final adminRequestsStream =
        FirebaseFirestore.instance.collection('adminRequests').snapshots();
    final territoiresStream =
        FirebaseFirestore.instance.collection('territoires').snapshots();
    final spotsStream =
        FirebaseFirestore.instance.collection('spots').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: adStream,
      builder: (context, adsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: subscriptionsStream,
          builder: (context, subscriptionsSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: adminsStream,
              builder: (context, adminsSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: adminRequestsStream,
                  builder: (context, adminRequestsSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: territoiresStream,
                      builder: (context, territoiresSnapshot) {
                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: spotsStream,
                          builder: (context, spotsSnapshot) {
                            final isLoading = !adsSnapshot.hasData ||
                                !subscriptionsSnapshot.hasData ||
                                !adminsSnapshot.hasData ||
                                !adminRequestsSnapshot.hasData ||
                                !territoiresSnapshot.hasData ||
                                !spotsSnapshot.hasData;

                            int activeAds = 0;
                            int disabledAds = 0;
                            int reportedAds = 0;
                            int deletedAds = 0;
                            int estimatedAdRevenue = 0;

                            int activeSubscriptions = 0;
                            int trialSubscriptions = 0;
                            int overdueSubscriptions = 0;
                            int cancelledSubscriptions = 0;
                            int estimatedSubscriptionRevenue = 0;
                            int rescueStations = 0;

                            int adminsCount = 0;
                            int pendingRequests = 0;
                            int territoiresCount = 0;
                            int spotsCount = 0;

                            if (adsSnapshot.hasData) {
                              for (final doc in adsSnapshot.data!.docs) {
                                final data = doc.data();
                                final status = (data['status'] ?? '').toString();

                                if (status == 'active') {
                                  activeAds++;
                                  estimatedAdRevenue +=
                                      _price(data['totalPriceExclTax']);
                                } else if (status == 'disabled') {
                                  disabledAds++;
                                } else if (status == 'reported') {
                                  reportedAds++;
                                } else if (status == 'deleted') {
                                  deletedAds++;
                                }
                              }
                            }

                            if (subscriptionsSnapshot.hasData) {
                              for (final doc
                                  in subscriptionsSnapshot.data!.docs) {
                                final data = doc.data();
                                final status = (data['status'] ?? '').toString();

                                final numberOfStations =
                                    _price(data['numberOfRescueStations']);
                                final pricePerStation =
                                    _price(data['pricePerStationExclTax']);

                                if (status == 'active') {
                                  activeSubscriptions++;
                                  rescueStations += numberOfStations;
                                  estimatedSubscriptionRevenue +=
                                      numberOfStations * pricePerStation;
                                } else if (status == 'trial') {
                                  trialSubscriptions++;
                                } else if (status == 'overdue') {
                                  overdueSubscriptions++;
                                } else if (status == 'cancelled') {
                                  cancelledSubscriptions++;
                                }
                              }
                            }

                            if (adminsSnapshot.hasData) {
                              adminsCount = adminsSnapshot.data!.docs.length;
                            }

                            if (adminRequestsSnapshot.hasData) {
                              pendingRequests =
                                  adminRequestsSnapshot.data!.docs.where((doc) {
                                final data = doc.data();
                                return data['status'] == 'pending';
                              }).length;
                            }

                            if (territoiresSnapshot.hasData) {
                              territoiresCount =
                                  territoiresSnapshot.data!.docs.length;
                            }

                            if (spotsSnapshot.hasData) {
                              spotsCount = spotsSnapshot.data!.docs.length;
                            }

                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TABLEAU DE BORD SUPER ADMIN',
                                    style: TextStyle(
                                      color: adminColor,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  if (isLoading)
                                    const Center(
                                        child: CircularProgressIndicator())
                                  else ...[
                                    _sectionTitle('PUBLICITÉ'),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'PUBLICITÉS ACTIVES',
                                          value: '$activeAds',
                                          icon: Icons.campaign_outlined,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'CA PUB ESTIMÉ',
                                          value: _money(estimatedAdRevenue),
                                          icon: Icons.euro_rounded,
                                          color: redColor,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'DÉSACTIVÉES',
                                          value: '$disabledAds',
                                          icon: Icons.pause_circle_outline,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'SIGNALÉES',
                                          value: '$reportedAds',
                                          icon: Icons.report_outlined,
                                          color: redColor,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'SUPPRIMÉES',
                                          value: '$deletedAds',
                                          icon: Icons.delete_outline,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 26),
                                    _sectionTitle('ABONNEMENTS'),
                                    const _SubscriptionPricingEditor(),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'ABONNEMENTS ACTIFS',
                                          value: '$activeSubscriptions',
                                          icon:
                                              Icons.workspace_premium_outlined,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'CA ABONNEMENTS ESTIMÉ',
                                          value: _money(
                                              estimatedSubscriptionRevenue),
                                          icon: Icons.euro_rounded,
                                          color: adminColor,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'ESSAIS EN COURS',
                                          value: '$trialSubscriptions',
                                          icon: Icons.hourglass_top_rounded,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'EN RETARD',
                                          value: '$overdueSubscriptions',
                                          icon: Icons.warning_amber_rounded,
                                          color: redColor,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'RÉSILIÉS',
                                          value: '$cancelledSubscriptions',
                                          icon: Icons.cancel_outlined,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 26),
                                    _sectionTitle('PLATEFORME'),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'SPHOTS',
                                          value: '$spotsCount',
                                          icon: Icons.place_outlined,
                                          color: adminColor,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'POSTES SURVEILLÉS',
                                          value: '$rescueStations',
                                          icon: Icons.beach_access_outlined,
                                          color: Colors.green,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 26),
                                    _sectionTitle('ADMINISTRATION'),
                                    Row(
                                      children: [
                                        _kpiCard(
                                          title: 'DEMANDES EN ATTENTE',
                                          value: '$pendingRequests',
                                          icon:
                                              Icons.pending_actions_outlined,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'ADMINS APPROUVÉS',
                                          value: '$adminsCount',
                                          icon: Icons.verified_user_outlined,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 14),
                                        _kpiCard(
                                          title: 'TERRITOIRES',
                                          value: '$territoiresCount',
                                          icon: Icons.public_outlined,
                                          color: adminColor,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SubscriptionPricingEditor extends StatefulWidget {
  const _SubscriptionPricingEditor();

  @override
  State<_SubscriptionPricingEditor> createState() =>
      _SubscriptionPricingEditorState();
}

class _SubscriptionPricingEditorState
    extends State<_SubscriptionPricingEditor> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);

  final TextEditingController _priceController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('subscriptionPricing')
        .get();

    final data = snapshot.data();
    final value =
        (data?['annualPricePerRescueStationExclTax'] as num?)
            ?.toDouble();

    _priceController.text =
        (value ?? 500.0).toStringAsFixed(2);

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _savePrice() async {
    final price = double.tryParse(
      _priceController.text.trim().replaceAll(',', '.'),
    );

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarif annuel invalide.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('subscriptionPricing')
          .set(
        {
          'annualPricePerRescueStationExclTax': price,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarif annuel enregistré.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _blue,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'TARIF ANNUEL PAR POSTE DE SECOURS',
              style: TextStyle(
                color: _blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '€ HT / an',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _saving ? null : _savePrice,
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.save_rounded),
            label: Text(
              _saving ? 'ENREGISTREMENT...' : 'ENREGISTRER',
            ),
          ),
        ],
      ),
    );
  }
}
