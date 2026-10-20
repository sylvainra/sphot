/// Règles contractuelles propres au SPHOT PUBLICITAIRE.
/// Les CGU, la confidentialité et le RGPD restent des documents séparés.
class AdvertiserCgvPolicy {
  const AdvertiserCgvPolicy._();

  static const documentId = 'advertiserCgv';
  static const defaultVersion = '1.0';
  static const title = 'CGV — SPHOT PUBLICITAIRE';
  static const radiusArticleTitle = 'Modification du rayon de diffusion';

  // Article approuvé pour les changements de zone / rayon.
  static const radiusArticle =
      'Le rayon d’action ou la zone géographique de diffusion sélectionné '
      'lors de la souscription d’une campagne publicitaire est applicable '
      'pour toute la durée contractuelle de cette campagne.\n\n'
      'L’annonceur peut demander une modification de ce rayon, à la hausse '
      'comme à la baisse, pendant la période de diffusion en cours.\n\n'
      'Toutefois, cette modification ne peut être approuvée ni prendre effet '
      'avant l’expiration de la période contractuelle en cours. Jusqu’à cette '
      'échéance, le rayon initialement souscrit et ses conditions tarifaires '
      'demeurent inchangés.\n\n'
      'À l’expiration de cette période, la modification pourra être examinée '
      'par SPHOT et fera l’objet d’une tarification correspondant au nouveau '
      'rayon sélectionné et aux conditions commerciales applicables à la '
      'nouvelle période de diffusion.\n\n'
      'La prise d’effet du nouveau rayon est subordonnée à son approbation, '
      'à l’acceptation des nouvelles conditions commerciales et à la '
      'régularisation du paiement applicable.\n\n'
      'Aucune augmentation ou diminution de rayon ne donne lieu à une '
      'modification rétroactive du prix de la période contractuelle '
      'déjà engagée.';

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
