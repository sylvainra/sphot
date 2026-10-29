# SPHOT — correctif Odoo 20, lecture Stripe restreinte (préparation locale)

Ce dossier contient uniquement le **nouveau** modèle
`sphot_advertiser_checkout/models/stripe_evidence.py`. Il est destiné à être
intégré à l'addon Odoo existant `sphot_advertiser_checkout`, dans la base
neutralisée `sphot_publicitaire_checkout_test`, **après validation séparée**.

L'addon déjà installé sur Windows reste la source à préserver : ne pas
remplacer son fichier `models/checkout.py`, ni son manifeste ni ses groupes.

Intégration future à contrôler avant toute action :

1. Comparer l'addon installé avec la copie de référence, sauvegarder ses
   fichiers, puis copier le nouveau `models/stripe_evidence.py` dans `models`.
2. Ajouter `from . import stripe_evidence` au fichier `models/__init__.py`
   **existant**, en conservant tous ses imports.
3. Mettre à niveau **uniquement** `sphot_advertiser_checkout` dans la base
   neutralisée, après accord explicite pour cette opération.
4. Vérifier avec le compte technique que la nouvelle méthode renvoie seulement
   des informations de paiement liées à la facture SPHOT demandée. Confirmer
   que les accès directs `payment.provider/search_read` et
   `payment.transaction/search_read` restent refusés.

Ne pas modifier les ACL générales du compte technique. Aucun paiement Stripe,
aucune activation de campagne, aucun déploiement ni écriture Firebase.
