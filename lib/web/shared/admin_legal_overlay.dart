import 'package:flutter/material.dart';

/// Habillage exclusivement visuel du contrôle CGU SPHOT ADMIN.
///
/// Le dashboard et sa carte restent visibles, sans aucune interaction
/// possible (souris, clavier, accessibilité ou retour arrière). Le contrôle
/// de version et l'enregistrement juridique restent assurés par
/// ProfessionalLegalGate et la Cloud Function existante.
class AdminLegalOverlay extends StatelessWidget {
  const AdminLegalOverlay({
    super.key,
    required this.dashboard,
    required this.panel,
    this.fullHeight = true,
  });

  final Widget dashboard;
  final Widget panel;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            child: ExcludeSemantics(
              child: AbsorbPointer(
                absorbing: true,
                child: dashboard,
              ),
            ),
          ),
          const ModalBarrier(
            dismissible: false,
            color: Color(0x4D10233F),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final heightLimit = constraints.maxHeight;
                  final panelHeight = fullHeight
                      ? (heightLimit > 630 ? 630.0 : heightLimit)
                      : (heightLimit > 270 ? 270.0 : heightLimit);
                  return Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: SizedBox(
                        height: panelHeight,
                        child: Material(
                          color: Colors.white,
                          elevation: 24,
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: panel,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// État de chargement/erreur dans le même décor Admin verrouillé.
class AdminLegalStatusPanel extends StatelessWidget {
  const AdminLegalStatusPanel({
    super.key,
    required this.title,
    required this.detail,
    this.loading = false,
    this.onRetry,
    this.onSignOut,
  });

  final String title;
  final String detail;
  final bool loading;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator()
              else
                const Icon(
                  Icons.gpp_maybe_outlined,
                  color: Color(0xFF213F8E),
                  size: 28,
                ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF213F8E),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (onRetry != null || onSignOut != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (onSignOut != null)
                      TextButton(
                        onPressed: onSignOut,
                        child: const Text('SE DÉCONNECTER'),
                      ),
                    if (onRetry != null)
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('RÉESSAYER'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
