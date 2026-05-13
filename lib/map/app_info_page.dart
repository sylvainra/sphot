import 'package:flutter/material.dart';

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: Image.asset(
          'data/icons/title.png',
          height: 44,
          fit: BoxFit.contain,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: const [
          _InfoSection(
            icon: Icons.info_outline,
            title: 'À propos de SPHOT',
            content:
                "SPHOT est une application destinée à localiser les spots de baignade, les accès plage, les postes de secours et les zones naturelles référencées.\n\n"
                "L’objectif est d’aider les utilisateurs à mieux identifier les lieux de baignade et les informations disponibles autour de ces zones.",
          ),
          _InfoSection(
            icon: Icons.warning_amber_rounded,
            title: 'Avertissement important',
            content:
                "Les informations affichées dans SPHOT sont fournies à titre indicatif.\n\n"
                "Elles ne remplacent jamais les consignes officielles affichées sur place, les arrêtés municipaux, les instructions des sauveteurs, ni l’appréciation personnelle des conditions de sécurité.\n\n"
                "Avant toute baignade, l’utilisateur doit vérifier la signalisation locale, les drapeaux, la météo, l’état de la mer et respecter les consignes des autorités compétentes.",
          ),
          _InfoSection(
            icon: Icons.gavel_outlined,
            title: 'Conditions générales d’utilisation',
            content:
                "L’utilisation de SPHOT implique l’acceptation des présentes conditions.\n\n"
                "L’utilisateur s’engage à utiliser l’application de manière responsable et à ne pas détourner son usage.\n\n"
                "SPHOT ne garantit pas l’exactitude permanente, l’exhaustivité ou l’actualisation en temps réel de toutes les informations affichées.\n\n"
                "La responsabilité de l’éditeur ne saurait être engagée en cas d’accident, de mauvaise interprétation des informations, d’absence de données, de données erronées ou de non-respect des consignes locales.",
          ),
          _InfoSection(
            icon: Icons.privacy_tip_outlined,
            title: 'Politique de confidentialité',
            content:
                "SPHOT peut utiliser certaines données nécessaires au bon fonctionnement de l’application, notamment la position approximative ou précise de l’utilisateur lorsque celui-ci active la géolocalisation.\n\n"
                "La localisation est utilisée uniquement pour afficher la position de l’utilisateur sur la carte ou l’aider à trouver des spots à proximité.\n\n"
                "L’utilisateur peut à tout moment désactiver l’accès à la localisation depuis les paramètres de son appareil.\n\n"
                "Aucune donnée personnelle sensible n’est volontairement demandée pour la simple consultation de la carte.",
          ),
          _InfoSection(
            icon: Icons.description_outlined,
            title: 'Mentions légales',
            content:
                "Nom de l’application : SPHOT\n"
                "Éditeur : à compléter\n"
                "Contact : à compléter\n"
                "Hébergement des données : à compléter\n\n"
                "Les contenus, logos, icônes, textes, cartes et éléments graphiques présents dans l’application sont protégés et ne peuvent être copiés ou réutilisés sans autorisation.",
          ),
          _InfoSection(
            icon: Icons.campaign_outlined,
            title: 'Publicités et partenaires',
            content:
                "SPHOT peut afficher des emplacements publicitaires locaux, nationaux ou internationaux.\n\n"
                "Ces publicités peuvent concerner des commerces, services, activités touristiques ou partenaires situés à proximité des zones consultées.\n\n"
                "La présence d’une publicité ne constitue pas une recommandation officielle de sécurité.",
          ),
          _InfoSection(
            icon: Icons.contact_support_outlined,
            title: 'Contact',
            content:
                "Pour toute demande, suggestion, correction d’information ou signalement, vous pouvez contacter l’équipe SPHOT.\n\n"
                "Email : à compléter",
          ),
          _InfoSection(
            icon: Icons.update,
            title: 'Dernière mise à jour',
            content: "Version provisoire des informations légales.\n\n"
                "Ces contenus devront être relus et adaptés avant publication officielle.",
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1E3A8A), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Colors.black.withOpacity(0.78),
            ),
          ),
        ],
      ),
    );
  }
}