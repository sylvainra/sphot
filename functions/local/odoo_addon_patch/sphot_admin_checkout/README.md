# SPHOT ADMIN — addon séparé Odoo Community 20 (préparation locale)

Source étudiée : archive Windows
`sphot_advertiser_checkout_20261031_154833.zip`, qui contient notamment
`models/checkout.py` et `models/stripe_evidence.py`. Les fichiers du module
PUBLICITAIRE original restent inchangés.

## Installation future, uniquement après validation

- Placer le dossier `sphot_admin_checkout` à côté de l'addon installé
  `sphot_advertiser_checkout`, sous le répertoire d'addons Odoo actif.
- Ne pas écraser ni modifier `sphot_advertiser_checkout`.
- L'addon ADMIN dépend de l'addon PUBLICITAIRE pour les champs de référence
  uniques et pour le groupe « SPHOT - Passerelle commandes et factures ».
- Installer **seulement sur la base neutralisée**
  `sphot_publicitaire_checkout_test`, après sauvegarde et validation explicite.
- Configurer quatre produits de type service, facturables à la commande,
  une société, des clients et les taxes/positions fiscales nécessaires.
- Tester l'unicité commande/facture, concurrence, montants et rapprochements.

Modèle RPC : `sphot.admin.checkout`. Méthodes :
`create_or_get_draft_order`, `confirm_and_post_one_invoice`,
`read_stripe_checkout_evidence`. Contrats exacts dans
`functions/local/odoo_admin_checkout_client.js`.

Le module refuse les références publicitaires (`SPHOT-PUB-*`) et exige
`SPHOT-ADM-TEST-*`. Une facture Odoo n'est pas un paiement. Une preuve
d'engagement public vérifié peut ouvrir les droits opérationnels sans
encaissement, mais cette décision est prise dans le serveur SPHOT et non
dans cet addon. La période d'essai de 8 jours reste séparée.

**État : code syntaxiquement vérifié et contrats testés en simulation.
Non installé, non testé contre l'instance Odoo réelle, non déployé.**
