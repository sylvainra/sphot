# SPHOT ADMIN — autorisation de l'essai 8 jours côté serveur

**TEST / revue de code uniquement. Aucun déploiement prévu.**

Ce correctif succède à la première validation administrative déjà testée.
Il ne constitue ni une seconde validation du SIREN/SIRET ni un paiement.

## Contenu

- `functions/admin_trial_authorization.js` : transaction Firestore atomique
  sécurisée par le JWT du Super Admin, durée fixée côté serveur.
- `functions/test/admin_trial_authorization.test.js` : 11 tests Node.js.
- `lib/web/super_admin/services/super_admin_trial_authorization_service.dart` :
  appel HTTPS authentifié, URL fournie par `--dart-define`.
- `sphot_admin_trial_authorization_TEST_changes.patch` : remplacement **du
  démarrage initial** dans le widget et enregistrement facultatif dans
  `functions/index.js`.

## Préconditions de la transaction

1. `adminRequests` déjà approuvé, compte `admins` cohérent.
2. `adminOdooReviewEvidence` issu du serveur de première validation,
   avec SIREN/SIRET et territoire conformes.
3. Demande d'essai explicitement en attente, huit jours, acceptations
   CGU / confidentialité / RGPD **avec version et date** conservées.
4. `subscriptions` au stade de configuration, aucun essai précédent,
   aucun cycle Odoo ni abonnement annuel déjà actif.
5. Le serveur crée une preuve `adminTrialAuthorizations/{uid}` une seule fois.

Les événements Firestore existants peuvent ensuite produire les documents
et notifications de validation d'essai.

## Étapes volontairement NON couvertes

- Le renouvellement exceptionnel de l'essai (`_renewTrial`) utilise encore
  un ancien chemin Flutter. **La règle stricte TEST le refuse**. Il faut
  lui créer un endpoint serveur distinct avant d'envisager une publication.
- Le bouton historique « PASSER ACTIF » côté Super Admin écrit encore les
  champs de paiement ; il doit être remplacé par la lecture de preuve Odoo.
- La sélection des postes et le devis client doivent être vérifiés côté
  serveur avant la commande Odoo.
- Aucun correctif de règles n'a été publié ; les règles de production
  communiquées précédemment demeurent ouvertes.

## Sécurité du déploiement

Le nouvel endpoint n'est exporté qu'avec
`SPHOT_ENABLE_ADMIN_TRIAL_AUTHORIZATION=true`. Flutter exige une URL
explicitement injectée sous le nom `SPHOT_ADMIN_TRIAL_AUTHORIZATION_URL` :
il n'y a **aucune URL de production par défaut**.

Ne pas activer ce flag ni modifier les `--dart-define` avant les tests
de compatibilité, les nouvelles règles Firestore et la validation explicite.
