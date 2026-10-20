/// Règles contractuelles propres au SPHOT PUBLICITAIRE.
/// Les CGU, la confidentialité et le RGPD restent des documents séparés.
class AdvertiserCgvPolicy {
  const AdvertiserCgvPolicy._();

  static const documentId = 'advertiserCgv';
  static const defaultVersion = '1.0';
  static const title = 'CGV — SPHOT PUBLICITAIRE';
  static const radiusArticleTitle = 'Modification du rayon de diffusion';

  // Clause contractuelle propre aux campagnes publicitaires.
  static const radiusArticle =
      'Le rayon d’action ou la zone géographique de diffusion est choisi '
      'au moment de la souscription de la campagne publicitaire et demeure '
      'fixe pendant toute sa période contractuelle payée.\n\n'
      'Aucune augmentation, diminution ou autre modification du rayon '
      'ne peut être demandée ou appliquée pendant cette période. '
      'Les conditions tarifaires souscrites restent inchangées.\n\n'
      'À l’issue de la période contractuelle, l’annonceur peut sélectionner '
      'librement un nouveau rayon pour une nouvelle souscription. '
      'Le tarif correspondant à la nouvelle zone et à la durée '
      'choisie lui est présenté avant sa commande.\n\n'
      'Le nouveau rayon ne prend effet qu’après confirmation de '
      'la nouvelle souscription et du paiement associé. '
      'Ce changement ne requiert aucune approbation du Super Admin.\n\n'
      'Aucune modification de rayon ne donne lieu à un recalcul '
      'ou à un remboursement rétroactif de la période déjà engagée.';

  static Map<String, dynamic> get initialDocument => {
    'title': title,
    'version': defaultVersion,
    'revision': 0,
    'published': true,
    'chapters': [
      {'title': radiusArticleTitle, 'content': radiusArticle},
    ],
  };
}
