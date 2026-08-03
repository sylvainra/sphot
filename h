warning: in the working copy of 'lib/web/admin/pages/admin_dashboard_page.dart', LF will be replaced by CRLF the next time Git touches it
[1mdiff --git a/lib/web/admin/pages/admin_dashboard_page.dart b/lib/web/admin/pages/admin_dashboard_page.dart[m
[1mindex 1b9a5fb..f539bbb 100644[m
[1m--- a/lib/web/admin/pages/admin_dashboard_page.dart[m
[1m+++ b/lib/web/admin/pages/admin_dashboard_page.dart[m
[36m@@ -75,9 +75,12 @@[m [mclass AdminDashboardPage extends StatefulWidget {[m
 class _AdminDashboardPageState extends State<AdminDashboardPage> {[m
   static const Color adminColor = Color(0xFF1E3A8A);[m
   static const Color redColor = Color(0xFFDC2626);[m
[32m+[m[32m  static const Color pendingColor = Color(0xFF6B7280);[m
 [m
   final MapController _mapController = MapController();[m
 Timer? _mapMovementTimer;[m
[32m+[m[32mTimer? _trialEndRefreshTimer;[m
[32m+[m[32mDateTime? _scheduledTrialEndDate;[m
 OverlayEntry? _sphotHoverOverlayEntry;[m
 Timer? _sphotHoverExitTimer;[m
 [m
[36m@@ -91,6 +94,8 @@[m [mColor _sphotHoverColor = adminColor;[m
   bool _showSauveteursManagementPanel = false;[m
   bool _showSurveillancePeriodsPanel = false;[m
   bool _showTrialSummaryPanel = false;[m
[32m+[m[32m  bool _showSubscriptionPanel = false;[m
[32m+[m[32m  bool _showBillingDocumentsPanel = false;[m
   bool _trialSummaryDialogOpen = false;[m
   Future<Map<String, dynamic>>? _trialSummaryPanelFuture;[m
   bool _placingSphotOnMap = false;[m
[36m@@ -1617,6 +1622,27 @@[m [mString _formatDate(dynamic value) {[m
   return value.toString();[m
 }[m
 [m
[32m+[m[32mvoid _scheduleTrialEndRefresh(DateTime? trialEndDate) {[m
[32m+[m[32m  if (_scheduledTrialEndDate == trialEndDate) return;[m
[32m+[m
[32m+[m[32m  _scheduledTrialEndDate = trialEndDate;[m
[32m+[m[32m  _trialEndRefreshTimer?.cancel();[m
[32m+[m
[32m+[m[32m  if (trialEndDate == null) return;[m
[32m+[m
[32m+[m[32m  final delay = trialEndDate.difference(DateTime.now());[m
[32m+[m[32m  if (delay <= Duration.zero) return;[m
[32m+[m
[32m+[m[32m  _trialEndRefreshTimer = Timer([m
[32m+[m[32m    delay + const Duration(seconds: 1),[m
[32m+[m[32m    () {[m
[32m+[m[32m      if (!mounted) return;[m
[32m+[m[32m      _scheduledTrialEndDate = null;[m
[32m+[m[32m      setState(() {});[m
[32m+[m[32m    },[m
[32m+[m[32m  );[m
[32m+[m[32m}[m
[32m+[m
 Widget _selectedAdminCard() {[m
   final admin = _selectedAdmin;[m
   if (admin == null) return const SizedBox.shrink();[m
[36m@@ -3500,6 +3526,8 @@[m [mWidget _buildTrialSauveteurManagementRow({[m
 [m
                       setState(() {[m
                         _showTrialSummaryPanel = true;[m
[32m+[m[32m                        _showSubscriptionPanel = false;[m
[32m+[m[32m                        _showBillingDocumentsPanel = false;[m
                         _trialSummaryPanelFuture =[m
                             _loadTrialSummaryData();[m
                       });[m
[36m@@ -4383,6 +4411,8 @@[m [mvoid _openTrialSummaryPanel() {[m
   setState(() {[m
     _trialSummaryPanelFuture = _loadTrialSummaryData();[m
     _showTrialSummaryPanel = true;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _showSauveteursManagementPanel = false;[m
     _showSurveillancePeriodsPanel = false;[m
[36m@@ -4450,11 +4480,315 @@[m [mWidget _buildTrialSummaryPanel() {[m
   );[m
 }[m
 [m
[32m+[m[32mvoid _openSubscriptionPanel() {[m
[32m+[m[32m  setState(() {[m
[32m+[m[32m    _showSubscriptionPanel = true;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
[32m+[m[32m    _showTrialSummaryPanel = false;[m
[32m+[m[32m    _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSauveteursManagementPanel = false;[m
[32m+[m[32m    _showSurveillancePeriodsPanel = false;[m
[32m+[m[32m    _showSauveteurEditorPanel = false;[m
[32m+[m[32m    _showSphotEditorPanel = false;[m
[32m+[m[32m    _placingSphotOnMap = false;[m
[32m+[m[32m    _selectedSpot = null;[m
[32m+[m[32m    _selectedAdmin = null;[m
[32m+[m[32m    _selectedAdvertiser = null;[m
[32m+[m[32m    _showLegalDocumentsPanel = false;[m
[32m+[m[32m  });[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mvoid _openBillingDocumentsPanel() {[m
[32m+[m[32m  setState(() {[m
[32m+[m[32m    _showBillingDocumentsPanel = true;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showTrialSummaryPanel = false;[m
[32m+[m[32m    _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSauveteursManagementPanel = false;[m
[32m+[m[32m    _showSurveillancePeriodsPanel = false;[m
[32m+[m[32m    _showSauveteurEditorPanel = false;[m
[32m+[m[32m    _showSphotEditorPanel = false;[m
[32m+[m[32m    _placingSphotOnMap = false;[m
[32m+[m[32m    _selectedSpot = null;[m
[32m+[m[32m    _selectedAdmin = null;[m
[32m+[m[32m    _selectedAdvertiser = null;[m
[32m+[m[32m    _showLegalDocumentsPanel = false;[m
[32m+[m[32m  });[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mvoid _closeSubscriptionPanel() {[m
[32m+[m[32m  setState(() {[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m  });[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mvoid _closeBillingDocumentsPanel() {[m
[32m+[m[32m  setState(() {[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
[32m+[m[32m  });[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mWidget _buildCommercialPanelHeader({[m
[32m+[m[32m  required String title,[m
[32m+[m[32m  required VoidCallback onClose,[m
[32m+[m[32m}) {[m
[32m+[m[32m  return Padding([m
[32m+[m[32m    padding: const EdgeInsets.all(20),[m
[32m+[m[32m    child: Row([m
[32m+[m[32m      crossAxisAlignment: CrossAxisAlignment.center,[m
[32m+[m[32m      children: [[m
[32m+[m[32m        Transform.translate([m
[32m+[m[32m  offset: const Offset(-12, 0),[m
[32m+[m[32m  child: Transform.scale([m
[32m+[m[32m    scale: 1.5,[m
[32m+[m[32m    alignment: Alignment.center,[m
[32m+[m[32m    child: Image.asset([m
[32m+[m[32m      'data/icons/fire_red_icon.png',[m
[32m+[m[32m      width: 30,[m
[32m+[m[32m      height: 30,[m
[32m+[m[32m      fit: BoxFit.contain,[m
[32m+[m[32m      filterQuality: FilterQuality.high,[m
[32m+[m[32m    ),[m
[32m+[m[32m  ),[m
[32m+[m[32m),[m
[32m+[m[41m        [m
[32m+[m[32m        Expanded([m
[32m+[m[32m          child: Column([m
[32m+[m[32m            crossAxisAlignment: CrossAxisAlignment.start,[m
[32m+[m[32m            children: [[m
[32m+[m[32m              Text([m
[32m+[m[32m                title,[m
[32m+[m[32m                style: const TextStyle([m
[32m+[m[32m                  color: adminColor,[m
[32m+[m[32m                  fontSize: 19,[m
[32m+[m[32m                  fontWeight: FontWeight.w900,[m
[32m+[m[32m                  letterSpacing: 0.7,[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m            ],[m
[32m+[m[32m          ),[m
[32m+[m[32m        ),[m
[32m+[m[32m        IconButton([m
[32m+[m[32m          tooltip: 'Fermer',[m
[32m+[m[32m          onPressed: onClose,[m
[32m+[m[32m          icon: const Icon(Icons.close_rounded),[m
[32m+[m[32m        ),[m
[32m+[m[32m      ],[m
[32m+[m[32m    ),[m
[32m+[m[32m  );[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mWidget _buildCommercialSection({[m
[32m+[m[32m  required IconData icon,[m
[32m+[m[32m  required String title,[m
[32m+[m[32m  required String description,[m
[32m+[m[32m  String status = 'À COMPLÉTER',[m
[32m+[m[32m  Color statusColor = pendingColor,[m
[32m+[m[32m}) {[m
[32m+[m[32m  return Container([m
[32m+[m[32m    padding: const EdgeInsets.all(16),[m
[32m+[m[32m    decoration: BoxDecoration([m
[32m+[m[32m      color: Colors.white,[m
[32m+[m[32m      borderRadius: BorderRadius.circular(14),[m
[32m+[m[32m      border: Border.all([m
[32m+[m[32m        color: adminColor.withOpacity(0.22),[m
[32m+[m[32m      ),[m
[32m+[m[32m    ),[m
[32m+[m[32m    child: Row([m
[32m+[m[32m      crossAxisAlignment: CrossAxisAlignment.start,[m
[32m+[m[32m      children: [[m
[32m+[m[32m        Icon(icon, color: adminColor, size: 27),[m
[32m+[m[32m        const SizedBox(width: 13),[m
[32m+[m[32m        Expanded([m
[32m+[m[32m          child: Column([m
[32m+[m[32m            crossAxisAlignment: CrossAxisAlignment.start,[m
[32m+[m[32m            children: [[m
[32m+[m[32m              Text([m
[32m+[m[32m                title,[m
[32m+[m[32m                style: const TextStyle([m
[32m+[m[32m                  color: adminColor,[m
[32m+[m[32m                  fontSize: 14,[m
[32m+[m[32m                  fontWeight: FontWeight.w900,[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m              const SizedBox(height: 5),[m
[32m+[m[32m              Text([m
[32m+[m[32m                description,[m
[32m+[m[32m                style: TextStyle([m
[32m+[m[32m                  color: adminColor.withOpacity(0.72),[m
[32m+[m[32m                  fontSize: 12,[m
[32m+[m[32m                  fontWeight: FontWeight.w600,[m
[32m+[m[32m                  height: 1.35,[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m              const SizedBox(height: 10),[m
[32m+[m[32m              Text([m
[32m+[m[32m                status,[m
[32m+[m[32m                style: TextStyle([m
[32m+[m[32m                  color: statusColor,[m
[32m+[m[32m                  fontSize: 11,[m
[32m+[m[32m                  fontWeight: FontWeight.w900,[m
[32m+[m[32m                  letterSpacing: 0.6,[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m            ],[m
[32m+[m[32m          ),[m
[32m+[m[32m        ),[m
[32m+[m[32m      ],[m
[32m+[m[32m    ),[m
[32m+[m[32m  );[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mWidget _buildSubscriptionPanel() {[m
[32m+[m[32m  return Container([m
[32m+[m[32m    width: 430,[m
[32m+[m[32m    decoration: BoxDecoration([m
[32m+[m[32m      color: Colors.white.withOpacity(0.98),[m
[32m+[m[32m      border: Border([m
[32m+[m[32m        left: BorderSide([m
[32m+[m[32m          color: adminColor.withOpacity(0.45),[m
[32m+[m[32m          width: 1.5,[m
[32m+[m[32m        ),[m
[32m+[m[32m      ),[m
[32m+[m[32m    ),[m
[32m+[m[32m    child: Material([m
[32m+[m[32m      color: Colors.transparent,[m
[32m+[m[32m      child: SafeArea([m
[32m+[m[32m        child: Column([m
[32m+[m[32m          children: [[m
[32m+[m[32m            _buildCommercialPanelHeader([m
[32m+[m[32m              title: 'ABONNEMENT',[m
[32m+[m[32m              onClose: _closeSubscriptionPanel,[m
[32m+[m[32m            ),[m
[32m+[m[32m            Divider([m
[32m+[m[32m              height: 1,[m
[32m+[m[32m              color: adminColor.withOpacity(0.20),[m
[32m+[m[32m            ),[m
[32m+[m[32m            Expanded([m
[32m+[m[32m              child: Container([m
[32m+[m[32m                color: const Color(0xFFF8FAFC),[m
[32m+[m[32m                child: ListView([m
[32m+[m[32m                  padding: const EdgeInsets.all(20),[m
[32m+[m[32m                  children: [[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.apartment_rounded,[m
[32m+[m[32m                      title: 'ORGANISME PAYEUR',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Coordonnées administratives et informations de facturation de votre organisme.',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.description_outlined,[m
[32m+[m[32m                      title: 'OFFRE ET DEVIS',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Nombre de postes de secours, durée et montant annuel de l’abonnement.',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.assignment_turned_in_outlined,[m
[32m+[m[32m                      title: 'COMMANDE',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Bon de commande, numéro d’engagement et code service si nécessaire.',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.verified_outlined,[m
[32m+[m[32m                      title: 'ACTIVATION',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'L’abonnement sera activé après validation complète de la commande.',[m
[32m+[m[32m                      status: 'EN ATTENTE',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                  ],[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m            ),[m
[32m+[m[32m          ],[m
[32m+[m[32m        ),[m
[32m+[m[32m      ),[m
[32m+[m[32m    ),[m
[32m+[m[32m  );[m
[32m+[m[32m}[m
[32m+[m
[32m+[m[32mWidget _buildBillingDocumentsPanel() {[m
[32m+[m[32m  return Container([m
[32m+[m[32m    width: 430,[m
[32m+[m[32m    decoration: BoxDecoration([m
[32m+[m[32m      color: Colors.white.withOpacity(0.98),[m
[32m+[m[32m      border: Border([m
[32m+[m[32m        left: BorderSide([m
[32m+[m[32m          color: adminColor.withOpacity(0.45),[m
[32m+[m[32m          width: 1.5,[m
[32m+[m[32m        ),[m
[32m+[m[32m      ),[m
[32m+[m[32m    ),[m
[32m+[m[32m    child: Material([m
[32m+[m[32m      color: Colors.transparent,[m
[32m+[m[32m      child: SafeArea([m
[32m+[m[32m        child: Column([m
[32m+[m[32m          children: [[m
[32m+[m[32m            _buildCommercialPanelHeader([m
[32m+[m[32m              title: 'DOCUMENTS & FACTURES',[m
[32m+[m[32m              onClose: _closeBillingDocumentsPanel,[m
[32m+[m[32m            ),[m
[32m+[m[32m            Divider([m
[32m+[m[32m              height: 1,[m
[32m+[m[32m              color: adminColor.withOpacity(0.20),[m
[32m+[m[32m            ),[m
[32m+[m[32m            Expanded([m
[32m+[m[32m              child: Container([m
[32m+[m[32m                color: const Color(0xFFF8FAFC),[m
[32m+[m[32m                child: ListView([m
[32m+[m[32m                  padding: const EdgeInsets.all(20),[m
[32m+[m[32m                  children: [[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.request_quote_outlined,[m
[32m+[m[32m                      title: 'DEVIS',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Les devis générés pour votre organisme apparaîtront ici.',[m
[32m+[m[32m                      status: 'AUCUN DOCUMENT',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.shopping_cart_checkout_rounded,[m
[32m+[m[32m                      title: 'COMMANDES',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Bons de commande et références d’engagement associés.',[m
[32m+[m[32m                      status: 'AUCUN DOCUMENT',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.receipt_long_outlined,[m
[32m+[m[32m                      title: 'FACTURES ET AVOIRS',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'Factures, avoirs et état de leur transmission électronique.',[m
[32m+[m[32m                      status: 'AUCUN DOCUMENT',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                    const SizedBox(height: 12),[m
[32m+[m[32m                    _buildCommercialSection([m
[32m+[m[32m                      icon: Icons.account_balance_outlined,[m
[32m+[m[32m                      title: 'SUIVI DU PAIEMENT',[m
[32m+[m[32m                      description:[m
[32m+[m[32m                          'État du dépôt, du traitement et du règlement des factures.',[m
[32m+[m[32m                      status: 'AUCUNE FACTURE',[m
[32m+[m[32m                    ),[m
[32m+[m[32m                  ],[m
[32m+[m[32m                ),[m
[32m+[m[32m              ),[m
[32m+[m[32m            ),[m
[32m+[m[32m          ],[m
[32m+[m[32m        ),[m
[32m+[m[32m      ),[m
[32m+[m[32m    ),[m
[32m+[m[32m  );[m
[32m+[m[32m}[m
[32m+[m
 Widget _buildRightPanel({[m
   required int visibleSpots,[m
[32m+[m[32m  required bool showTrialButton,[m
 }) {[m
   return Container([m
     width: 360,[m
[32m+[m[32m    padding: const EdgeInsets.all(22),[m
     decoration: BoxDecoration([m
       color: Colors.white.withOpacity(0.96),[m
       border: Border([m
[36m@@ -4465,11 +4799,8 @@[m [mWidget _buildRightPanel({[m
       ),[m
     ),[m
     child: SafeArea([m
[31m-      child: Padding([m
[31m-        padding: const EdgeInsets.all(22),[m
[31m-        child: Column([m
[31m-          crossAxisAlignment: CrossAxisAlignment.start,[m
[31m-          children: [[m
[32m+[m[32m      child: Column([m
[32m+[m[32m        children: [[m
   const SizedBox([m
     width: double.infinity,[m
     child: Text([m
[36m@@ -4504,7 +4835,7 @@[m [mWidget _buildRightPanel({[m
     ),[m
   ),[m
 [m
[31m-  const SizedBox(height: 20),[m
[32m+[m[32m  const SizedBox(height: 16),[m
 [m
   _summaryCard([m
     title: 'CRÉER UN SPHOT',[m
[36m@@ -4512,14 +4843,14 @@[m [mWidget _buildRightPanel({[m
     color: adminColor,[m
     iconPath: 'data/icons/fire_red_icon.png',[m
     stepNumber: 1,[m
[31m-    iconScale: 1.6,[m
[31m-    titleFontSize: 20,[m
[31m-    titleLetterSpacing: 1.2,[m
[32m+[m[32m    iconScale: 1.35,[m
[32m+[m[32m    titleFontSize: 17,[m
[32m+[m[32m    titleLetterSpacing: 0.8,[m
     showValue: false,[m
     onTap: _openNewSphotEditor,[m
   ),[m
 [m
[31m-  const SizedBox(height: 12),[m
[32m+[m[32m  const SizedBox(height: 8),[m
 [m
   _summaryCard([m
     title: 'CRÉER UNE PÉRIODE',[m
[36m@@ -4527,14 +4858,14 @@[m [mWidget _buildRightPanel({[m
     color: adminColor,[m
     iconPath: 'data/icons/fire_red_icon.png',[m
     stepNumber: 2,[m
[31m-    iconScale: 1.6,[m
[31m-    titleFontSize: 20,[m
[31m-    titleLetterSpacing: 1.2,[m
[32m+[m[32m    iconScale: 1.35,[m
[32m+[m[32m    titleFontSize: 17,[m
[32m+[m[32m    titleLetterSpacing: 0.8,[m
     showValue: false,[m
     onTap: _openSurveillancePeriodsPanel,[m
   ),[m
 [m
[31m-  const SizedBox(height: 12),[m
[32m+[m[32m  const SizedBox(height: 8),[m
 [m
   _summaryCard([m
     title: 'CRÉER UN SAUVETEUR',[m
[36m@@ -4542,86 +4873,78 @@[m [mWidget _buildRightPanel({[m
     color: adminColor,[m
     iconPath: 'data/icons/fire_red_icon.png',[m
     stepNumber: 3,[m
[31m-    iconScale: 1.6,[m
[31m-    titleFontSize: 20,[m
[31m-    titleLetterSpacing: 1.2,[m
[32m+[m[32m    iconScale: 1.35,[m
[32m+[m[32m    titleFontSize: 17,[m
[32m+[m[32m    titleLetterSpacing: 0.8,[m
     showValue: false,[m
     onTap: _openNewSauveteurEditor,[m
   ),[m
 [m
[31m-  const SizedBox(height: 12),[m
[32m+[m[32m  const SizedBox(height: 8),[m
 [m
 _summaryCard([m
   title: 'ESPACE ADMIN SPHOT',[m
   value: '',[m
   color: adminColor,[m
   iconPath: 'data/icons/fire_red_icon.png',[m
[31m-  iconScale: 1.6,[m
[31m-  titleFontSize: 20,[m
[31m-  titleLetterSpacing: 1.2,[m
[32m+[m[32m  iconScale: 1.35,[m
[32m+[m[32m  titleFontSize: 17,[m
[32m+[m[32m  titleLetterSpacing: 0.8,[m
   showValue: false,[m
   onTap: _openTrialSummaryPanel,[m
 ),[m
 [m
[31m-const SizedBox(height: 12),[m
[32m+[m[32mconst SizedBox(height: 8),[m
 [m
[31m-  SizedBox([m
[31m-  width: double.infinity,[m
[31m-  height: 80,[m
[31m-  child: OutlinedButton.icon([m
[31m-    onPressed: _openTrialSummaryDialog,[m
[32m+[m[32mif (showTrialButton) ...[[m
[32m+[m[32m  _summaryCard([m
[32m+[m[32m    title: 'ESSAI GRATUIT 8 JOURS',[m
[32m+[m[32m    value: '',[m
[32m+[m[32m    color: redColor,[m
[32m+[m[32m    iconPath: 'data/icons/fire_red_icon.png',[m
[32m+[m[32m    iconScale: 1.35,[m
[32m+[m[32m    titleFontSize: 17,[m
[32m+[m[32m    titleLetterSpacing: 0.8,[m
[32m+[m[32m    showValue: false,[m
[32m+[m[32m    onTap: _openTrialSummaryDialog,[m
[32m+[m[32m  ),[m
[32m+[m[32m  const SizedBox(height: 8),[m
[32m+[m[32m],[m
 [m
[31m-    style: OutlinedButton.styleFrom([m
[31m-      foregroundColor: redColor,[m
[31m-      backgroundColor: Colors.transparent,[m
[31m-      side: const BorderSide([m
[31m-        color: redColor,[m
[31m-        width: 1.8,[m
[31m-      ),[m
[31m-      shape: RoundedRectangleBorder([m
[31m-        borderRadius: BorderRadius.circular(16),[m
[31m-      ),[m
[31m-    ),[m
[32m+[m[32m_summaryCard([m
[32m+[m[32m  title: 'ABONNEMENT',[m
[32m+[m[32m  value: '',[m
[32m+[m[32m  color: showTrialButton ? pendingColor : redColor,[m
[32m+[m[32m  iconPath: 'data/icons/fire_red_icon.png',[m
[32m+[m[32m  iconScale: 1.35,[m
[32m+[m[32m  titleFontSize: 16,[m
[32m+[m[32m  titleLetterSpacing: 0.5,[m
[32m+[m[32m  showValue: false,[m
[32m+[m[32m  grayscaleIcon: showTrialButton,[m
[32m+[m[32m  onTap: _openSubscriptionPanel,[m
[32m+[m[32m),[m
 [m
[31m-    icon: SizedBox([m
[31m-      width: 34,[m
[31m-      height: 34,[m
[31m-      child: Transform.scale([m
[31m-        scale: 1.6,[m
[31m-        alignment: Alignment.center,[m
[31m-        child: Image.asset([m
[31m-          'data/icons/fire_red_icon.png',[m
[31m-          width: 34,[m
[31m-          height: 34,[m
[31m-          fit: BoxFit.contain,[m
[31m-          filterQuality: FilterQuality.high,[m
[31m-        ),[m
[31m-      ),[m
[31m-    ),[m
[32m+[m[32mconst SizedBox(height: 8),[m
 [m
[31m-    label: const FittedBox([m
[31m-      fit: BoxFit.scaleDown,[m
[31m-      child: Text([m
[31m-        'ESSAI GRATUIT 8 JOURS',[m
[31m-        maxLines: 1,[m
[31m-        softWrap: false,[m
[31m-        textAlign: TextAlign.center,[m
[31m-        style: TextStyle([m
[31m-          color: redColor,[m
[31m-          fontSize: 20,[m
[31m-          fontWeight: FontWeight.w900,[m
[31m-          letterSpacing: 1.2,[m
[31m-        ),[m
[31m-      ),[m
[31m-    ),[m
[31m-  ),[m
[32m+[m[32m_summaryCard([m
[32m+[m[32m  title: 'DOCUMENTS & FACTURES',[m
[32m+[m[32m  value: '',[m
[32m+[m[32m  color: showTrialButton ? pendingColor : adminColor,[m
[32m+[m[32m  iconPath: showTrialButton[m
[32m+[m[32m      ? 'data/icons/fire_red_icon.png'[m
[32m+[m[32m      : 'data/icons/fire_blue_icon.png',[m
[32m+[m[32m  iconScale: 1.35,[m
[32m+[m[32m  titleFontSize: 16,[m
[32m+[m[32m  titleLetterSpacing: 0.5,[m
[32m+[m[32m  showValue: false,[m
[32m+[m[32m  grayscaleIcon: showTrialButton,[m
[32m+[m[32m  onTap: _openBillingDocumentsPanel,[m
 ),[m
 [m
[31m-  const Spacer(),[m
[32m+[m[32mconst SizedBox(height: 4),[m
 [m
   [m
 ],[m
[31m-        ),[m
       ),[m
     ),[m
   );[m
[36m@@ -4637,17 +4960,18 @@[m [mconst SizedBox(height: 12),[m
   double titleFontSize = 13,[m
   double titleLetterSpacing = 0,[m
   bool showValue = true,[m
[32m+[m[32m  bool grayscaleIcon = false,[m
   VoidCallback? onTap,[m
 }) {[m
     final card = Container([m
[31m-  height: 80,[m
[32m+[m[32m  height: 64,[m
   padding: const EdgeInsets.symmetric([m
[31m-    horizontal: 14,[m
[31m-    vertical: 8,[m
[32m+[m[32m    horizontal: 12,[m
[32m+[m[32m    vertical: 5,[m
   ),[m
       decoration: BoxDecoration([m
         color: Colors.transparent,[m
[31m-        borderRadius: BorderRadius.circular(16),[m
[32m+[m[32m        borderRadius: BorderRadius.circular(14),[m
         border: Border.all(color: color, width: 1.5),[m
       ),[m
       child: Row([m
[36m@@ -4662,13 +4986,29 @@[m [mconst SizedBox(height: 12),[m
       Transform.scale([m
         scale: iconScale,[m
         alignment: Alignment.center,[m
[31m-        child: Image.asset([m
[31m-          iconPath,[m
[31m-          width: 34,[m
[31m-          height: 34,[m
[31m-          fit: BoxFit.contain,[m
[31m-          filterQuality: FilterQuality.high,[m
[31m-        ),[m
[32m+[m[32m        child: grayscaleIcon[m
[32m+[m[32m            ? ColorFiltered([m
[32m+[m[32m                colorFilter: const ColorFilter.matrix([[m
[32m+[m[32m                  0.2126, 0.7152, 0.0722, 0, 0,[m
[32m+[m[32m                  0.2126, 0.7152, 0.0722, 0, 0,[m
[32m+[m[32m                  0.2126, 0.7152, 0.0722, 0, 0,[m
[32m+[m[32m                  0, 0, 0, 1, 0,[m
[32m+[m[32m                ]),[m
[32m+[m[32m                child: Image.asset([m
[32m+[m[32m                  iconPath,[m
[32m+[m[32m                  width: 34,[m
[32m+[m[32m                  height: 34,[m
[32m+[m[32m                  fit: BoxFit.contain,[m
[32m+[m[32m                  filterQuality: FilterQuality.high,[m
[32m+[m[32m                ),[m
[32m+[m[32m              )[m
[32m+[m[32m            : Image.asset([m
[32m+[m[32m                iconPath,[m
[32m+[m[32m                width: 34,[m
[32m+[m[32m                height: 34,[m
[32m+[m[32m                fit: BoxFit.contain,[m
[32m+[m[32m                filterQuality: FilterQuality.high,[m
[32m+[m[32m              ),[m
       ),[m
       if (stepNumber != null)[m
         Transform.translate([m
[36m@@ -4701,15 +5041,21 @@[m [mconst SizedBox(height: 12),[m
   mainAxisAlignment: MainAxisAlignment.center,[m
   crossAxisAlignment: CrossAxisAlignment.start,[m
               children: [[m
[31m-                Text([m
[31m-                  title,[m
[31m-                  style: TextStyle([m
[31m-                    color: color,[m
[31m-                    decoration: TextDecoration.none,[m
[31m-                    decorationColor: Colors.transparent,[m
[31m-                    fontSize: titleFontSize,[m
[31m-                    fontWeight: FontWeight.w900,[m
[31m-                    letterSpacing: titleLetterSpacing,[m
[32m+[m[32m                FittedBox([m
[32m+[m[32m                  fit: BoxFit.scaleDown,[m
[32m+[m[32m                  alignment: Alignment.centerLeft,[m
[32m+[m[32m                  child: Text([m
[32m+[m[32m                    title,[m
[32m+[m[32m                    maxLines: 1,[m
[32m+[m[32m                    softWrap: false,[m
[32m+[m[32m                    style: TextStyle([m
[32m+[m[32m                      color: color,[m
[32m+[m[32m                      decoration: TextDecoration.none,[m
[32m+[m[32m                      decorationColor: Colors.transparent,[m
[32m+[m[32m                      fontSize: titleFontSize,[m
[32m+[m[32m                      fontWeight: FontWeight.w900,[m
[32m+[m[32m                      letterSpacing: titleLetterSpacing,[m
[32m+[m[32m                    ),[m
                   ),[m
                 ),[m
                 if (showValue) ...[[m
[36m@@ -5136,6 +5482,8 @@[m [mvoid _openSurveillancePeriodsPanel() {[m
   setState(() {[m
     _showTrialSummaryPanel = false;[m
     _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _showSurveillancePeriodsPanel = true;[m
     _showSauveteurEditorPanel = false;[m
[36m@@ -5774,6 +6122,8 @@[m [mFuture<void> _saveSauveteur() async {[m
   _showSauveteursManagementPanel = false;[m
 [m
   _showTrialSummaryPanel = isEditing;[m
[32m+[m[32m  _showSubscriptionPanel = false;[m
[32m+[m[32m  _showBillingDocumentsPanel = false;[m
   _trialSummaryPanelFuture = isEditing[m
       ? _loadTrialSummaryData()[m
       : null;[m
[36m@@ -5815,6 +6165,8 @@[m [mvoid _openNewSphotEditor() {[m
   setState(() {[m
     _showTrialSummaryPanel = false;[m
     _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _clearSphotEditor();[m
     _showSauveteurEditorPanel = false;[m
[36m@@ -5849,6 +6201,8 @@[m [mvoid _openNewSauveteurEditor() {[m
   setState(() {[m
     _showTrialSummaryPanel = false;[m
     _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _clearSauveteurEditor();[m
     _showSauveteurEditorPanel = true;[m
[36m@@ -5879,6 +6233,8 @@[m [mvoid _openSauveteursManagementPanel() {[m
   setState(() {[m
     _showTrialSummaryPanel = false;[m
     _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _clearSauveteurEditor();[m
     _showSauveteursManagementPanel = true;[m
[36m@@ -5918,6 +6274,8 @@[m [mvoid _openSauveteurForEditing([m
   setState(() {[m
   _showTrialSummaryPanel = false;[m
   _trialSummaryPanelFuture = null;[m
[32m+[m[32m  _showSubscriptionPanel = false;[m
[32m+[m[32m  _showBillingDocumentsPanel = false;[m
     [m
     _clearSauveteurEditor();[m
 [m
[36m@@ -6089,6 +6447,8 @@[m [mvoid _loadSphotInEditor(Map<String, dynamic> data) {[m
   setState(() {[m
     _showTrialSummaryPanel = false;[m
     _trialSummaryPanelFuture = null;[m
[32m+[m[32m    _showSubscriptionPanel = false;[m
[32m+[m[32m    _showBillingDocumentsPanel = false;[m
 [m
     _editingSphotDocId = _cleanText(data['_docId']);[m
     _sphotIdController.text = _cleanText([m
[36m@@ -6376,6 +6736,8 @@[m [mFuture<void> _deleteSphotFromSummary([m
     setState(() {[m
       _selectedSpot = null;[m
       _showTrialSummaryPanel = true;[m
[32m+[m[32m      _showSubscriptionPanel = false;[m
[32m+[m[32m      _showBillingDocumentsPanel = false;[m
       _trialSummaryPanelFuture =[m
           _loadTrialSummaryData();[m
     });[m
[36m@@ -7545,7 +7907,7 @@[m [mWidget _buildSurveillancePeriodsPanel() {[m
                   Transform.translate([m
                     offset: const Offset(-12, 0),[m
                     child: Transform.scale([m
[31m-                      scale: 1.8,[m
[32m+[m[32m                      scale: 1.5,[m
                       alignment: Alignment.center,[m
                       child: Image.asset([m
                         'data/icons/fire_red_icon.png',[m
[36m@@ -8354,7 +8716,7 @@[m [mWidget _buildSauveteurEditorPanel() {[m
                   Transform.translate([m
                     offset: const Offset(-12, 0),[m
                     child: Transform.scale([m
[31m-                      scale: 1.8,[m
[32m+[m[32m                      scale: 1.5,[m
                       alignment: Alignment.center,[m
                       child: Image.asset([m
                         'data/icons/fire_red_icon.png',[m
[36m@@ -8731,7 +9093,7 @@[m [mWidget _buildSphotEditorPanel() {[m
                 Transform.translate([m
   offset: const Offset(-12, 0),[m
   child: Transform.scale([m
[31m-    scale: 1.8,[m
[32m+[m[32m    scale: 1.5,[m
     alignment: Alignment.center,[m
     child: Image.asset([m
       'data/icons/fire_red_icon.png',[m
[36m@@ -11423,6 +11785,7 @@[m [mvoid initState() {[m
 @override[m
 void dispose() {[m
   _mapMovementTimer?.cancel();[m
[32m+[m[32m  _trialEndRefreshTimer?.cancel();[m
 [m
   _sphotHoverExitTimer?.cancel();[m
   _removeSphotHoverLabel();[m
[36m@@ -12311,6 +12674,27 @@[m [mWidget build(BuildContext context) {[m
                     for (final doc in subscriptionsDocs) doc.id: doc.data(),[m
                   };[m
 [m
[32m+[m[32m                  final currentSubscription =[m
[32m+[m[32m                      _subscriptionsByUid[widget.adminUid.trim()];[m
[32m+[m[32m                  final subscriptionStatus = _cleanText([m
[32m+[m[32m                    currentSubscription?['status'],[m
[32m+[m[32m                  ).toLowerCase();[m
[32m+[m[32m                  final rawTrialEndDate =[m
[32m+[m[32m                      currentSubscription?['trialEndDate'];[m
[32m+[m[32m                  final DateTime? trialEndDate = rawTrialEndDate is Timestamp[m
[32m+[m[32m                      ? rawTrialEndDate.toDate()[m
[32m+[m[32m                      : rawTrialEndDate is DateTime[m
[32m+[m[32m                          ? rawTrialEndDate[m
[32m+[m[32m                          : null;[m
[32m+[m
[32m+[m[32m                  _scheduleTrialEndRefresh(trialEndDate);[m
[32m+[m
[32m+[m[32m                  final trialHasEnded = trialEndDate != null &&[m
[32m+[m[32m                      !DateTime.now().isBefore(trialEndDate);[m
[32m+[m[32m                  final showTrialButton = currentSubscription == null ||[m
[32m+[m[32m                      subscriptionStatus.isEmpty ||[m
[32m+[m[32m                      (subscriptionStatus == 'trial' && !trialHasEnded);[m
[32m+[m
                   final validSpots = docs.where((doc) {[m
   final data = doc.data();[m
   final lat = _toDouble(data['sphotLat']);[m
[36m@@ -12397,6 +12781,7 @@[m [mfinal clusteredMarkers = validSpots.map((doc) {[m
                     children: [[m
                       _buildRightPanel([m
                         visibleSpots: validSpots.length,[m
[32m+[m[32m                        showTrialButton: showTrialButton,[m
                       ),[m
                       Expanded([m
   child: Stack([m
[36m@@ -12620,7 +13005,11 @@[m [mfinal clusteredMarkers = validSpots.map((doc) {[m
                       if (_selectedAdmin != null)[m
   _buildAdminDetailPanel(),[m
 [m
[31m-if (_showTrialSummaryPanel)[m
[32m+[m[32mif (_showSubscriptionPanel)[m
[32m+[m[32m  _buildSubscriptionPanel()[m
[32m+[m[32melse if (_showBillingDocumentsPanel)[m
[32m+[m[32m  _buildBillingDocumentsPanel()[m
[32m+[m[32melse if (_showTrialSummaryPanel)[m
   _buildTrialSummaryPanel()[m
 else if (_showSauveteursManagementPanel)[m
   _buildSauveteursManagementPanel()[m
