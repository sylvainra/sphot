# SPHOT — Validation du refus définitif d'une candidature publicitaire (23/10/2026)

## Référence conservée

- Dépôt : `Sylvainra/SPHOT`, branche `main`.
- Référence du code exécuté avant ce compte rendu : `080c26b472dd6fa2e2dc01158f5cf6442161ebe8`.
- Site de référence : `https://sphot.app` ; projet Firebase : `sphot-ab80b`.
- Implémentation existante : `functions/advertiser_review_decision.js`,
  `functions/advertiser_refusal_cleanup.js` et leurs déclarations dans
  `functions/index.js`.

## Comportement attendu et validation utilisateur

Lorsqu'un Super Admin refuse définitivement une nouvelle candidature SPHOT
Publicitaire en phase 1, la fonction de décision demande l'envoi du mail de
refus. Le nettoyage ne doit commencer qu'après l'enregistrement de la
confirmation d'envoi (`rejectionEmail.status == sent`). Il supprime les
fichiers du dossier, le compte Firebase Auth anonyme correspondant et le
document Firestore avec ses éventuelles sous-collections.

**Le 23 octobre 2026, l'utilisateur confirme un essai concluant : le dossier
de candidature a bien été créé dans Firebase, puis supprimé après le refus.**
C'est la preuve fonctionnelle rapportée pour ce parcours. La disparition
individuelle des fichiers Storage et du compte Auth n'a pas été détaillée
dans ce retour ; elle est couverte par les tests automatisés, sans être
présentée comme une vérification manuelle indépendante.

Garde-fous conservés dans le code :

- Purge réservée aux nouvelles candidatures de phase 1 explicitement
  marquées `purgeAfterRejectionEmail == true` et refusées.
- Pas de purge rétroactive des anciens refus ; pas de purge d'un annonceur
  approuvé ou d'une décision de phase 2 sur les visuels.
- Vérification de la concordance entre l'UID du dossier et son identifiant ;
  refus de supprimer automatiquement un compte non anonyme.
- En cas d'échec de suppression Storage, conservation du document et du
  compte pour permettre un nouvel essai ; suppression Firestore en dernier.

## Déploiements Firebase confirmés par les sorties PowerShell

1. `reviewAdvertiserDecision` (`us-central1`) : **Successful update operation**.
2. `cleanupRejectedAdvertiserRequest` (`europe-west1`) : suppression réussie
   d'un ancien enregistrement de fonction incompatible, puis
   **Successful create operation** avec le déclencheur Firestore attendu.

La résolution de l'erreur de déploiement n'a nécessité aucun nouveau service,
aucun changement d'architecture et aucun changement du code applicatif.
Le PC utilise Node.js `22.23.4`. L'avertissement Firebase concernant une
version du SDK `firebase-functions` n'était pas bloquant ; aucune mise à
niveau de dépendance n'a été faite à cette occasion.

## Vérifications de non-régression avant cet enregistrement

- `node functions/test/advertiser_refusal_cleanup.test.js` : **7/7 réussis**.
- `node functions/test/advertiser_review_decision.test.js` : **8/8 réussis**.
- `npm --prefix functions run lint` : **réussi**.
- Les deux fonctions ont démarré localement avec le serveur Functions
  Framework sur le port 8080 et Node.js `22.23.4` lors du diagnostic.

**Statut : parcours de création puis refus avec suppression Firestore validé
par l'utilisateur le 23/10/2026.** Ce commit est uniquement documentaire :
il n'altère ni les fonctionnalités validées précédemment, ni les règles
Firestore, ni l'application Web/mobile. Un test futur peut, si nécessaire,
attester séparément les suppressions Auth et Storage en production.
