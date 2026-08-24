# État consolidé du projet SPHOT — 24 août 2026

Ce document conserve les décisions techniques et fonctionnelles nécessaires à
la poursuite du projet indépendamment de l'historique des conversations.

## Références Git

- Dépôt : `Sylvainra/SPHOT`.
- Base consolidée validée : branche `integration/sphot-base-consolidee` au
  commit `d8c1e7bbfcdceea2f4bd2b07dba6c1666f3f500f`.
- Développement du portail annonceur : branche
  `feature/web-advertiser-dashboard`.
- Commits fondateurs du portail annonceur :
  - `37926f6` — ossature du dashboard Web annonceur ;
  - `ce6ecc3` — essai ProConnect en fenêtre locale ;
  - `8f18b1a` — passage au flux ProConnect par redirection.

Chaque évolution validée doit prolonger la dernière base validée. Les anciens
commits servent de points de restauration et ne doivent pas remplacer une
évolution plus récente sans décision explicite.

## Architecture fonctionnelle retenue

- L'application publique reste prioritairement conçue pour le téléphone.
- Les portails Admin, Super Admin et Annonceur sont conçus pour le Web afin de
  faciliter les saisies, la gestion et la consultation.
- Le dashboard annonceur s'inspire de l'organisation visuelle du dashboard
  Admin sans réintroduire ses fonctions métier.
- Le portail annonceur comprend huit rubriques : identité professionnelle,
  établissement, SPHOT publicitaire, diffusion, planification, devis et
  commande, documents et factures, statistiques.
- La diffusion publicitaire locale repose sur un établissement positionné sur
  la carte, un rayon et une période.
- Un emplacement publicitaire donné est réservé à un seul annonceur pendant
  une même période. La rotation simultanée de plusieurs annonceurs n'est pas la
  règle commerciale retenue.
- La facturation devra anticiper la facturation électronique française et
  distinguer les références administratives, devis, commandes et factures.

## ProConnect

- Le fournisseur Firebase reste `oidc.proconnect`.
- ProConnect demeure obligatoire pour une version de production du portail
  annonceur.
- L'authentification sur l'instance de test ProConnect fonctionne jusqu'au
  retour vers Firebase.
- Le flux popup revient vers le gestionnaire Firebase, ferme la fenêtre puis
  perd le résultat dans la fenêtre principale.
- Le flux par redirection authentifie l'utilisateur, mais `localhost` ne
  récupère pas le résultat à cause du stockage inter-domaines bloqué par les
  navigateurs récents.
- URL de retour actuellement enregistrée auprès de ProConnect :
  `https://sphot-ab80b.firebaseapp.com/__/auth/handler`.
- L'utilisateur ne dispose pas d'un compte lui permettant de modifier lui-même
  les `redirect_uri` dans l'Espace Partenaires ProConnect et les sollicitations
  adressées au support sont restées sans réponse.

### Contournement de développement

Le portail annonceur peut être lancé en développement avec :

```powershell
flutter run -d chrome -t lib/main_web_advertiser.dart --web-port 7357 --dart-define=SPHOT_ADVERTISER_DEV_BYPASS=true
```

Ce paramètre contourne ProConnect uniquement pour la session de développement.
Le dashboard affiche alors clairement que les données ne sont pas certifiées.

Sans ce paramètre, le contournement est désactivé et ProConnect reste requis :

```powershell
flutter run -d chrome -t lib/main_web_advertiser.dart --web-port 7357
```

Une construction de production ne doit jamais inclure
`SPHOT_ADVERTISER_DEV_BYPASS=true`.

## Firebase Hosting

- Site historique : `sphot-ab80b`.
- Site créé pendant les essais : `sphot-advertiser-test`.
- Le site `sphot-advertiser-test` est vide, non déployé et actuellement
  inutilisé.
- Une cible locale `advertiser` a été ajoutée à `.firebaserc` sur le poste de
  développement. Cette configuration n'est pas nécessaire au contournement de
  développement et doit rester identifiée tant qu'aucune stratégie
  d'hébergement n'est validée.
- La piste consistant à héberger le portail sous
  `https://sphot-ab80b.firebaseapp.com/annonceur/` a été évoquée pour réutiliser
  l'URL ProConnect existante, mais elle n'est ni développée, ni validée, ni
  déployée.
- Aucun déploiement du portail annonceur ne doit écraser le site historique.

## Fichiers du portail annonceur

### Actifs

- `lib/main_web_advertiser.dart`
- `lib/services/advertiser_auth_service.dart`
- `lib/web/advertiser/web_advertiser_app.dart`
- `lib/web/advertiser/pages/advertiser_dashboard_page.dart`

### À conserver pour traçabilité

- Les essais popup et redirection ProConnect restent récupérables dans
  l'historique Git.
- Les anciennes variantes ne doivent pas être dupliquées dans `lib/` uniquement
  pour servir de sauvegarde : Git constitue la sauvegarde de référence.

## Politique de nettoyage future

1. Inventorier les fichiers et ressources sans rien supprimer.
2. Rechercher leurs imports, appels, points d'entrée et dépendances.
3. Classer chaque élément : actif, expérimental, généré, ancien ou incertain.
4. Ne supprimer que de petits lots homogènes.
5. Compiler et tester après chaque lot.
6. Créer un commit distinct pour chaque lot nettoyé.
7. Nettoyer Firebase seulement après stabilisation du code, inventaire des
   collections, fonctions, sites Hosting, comptes Auth et fichiers Storage.
8. En cas de doute, conserver l'élément et documenter le doute.

## Éléments locaux à ne pas intégrer automatiquement

Les modifications de fichiers générés ou de dépendances telles que
`macos/Flutter/GeneratedPluginRegistrant.swift` et `pubspec.lock` doivent être
examinées séparément. Elles ne doivent pas être ajoutées à un commit fonctionnel
sans lien démontré avec la modification en cours.

## Prochaine étape

Poursuivre la conception fonctionnelle du dashboard annonceur grâce au
contournement de développement, en commençant par la rubrique identité
professionnelle. La résolution définitive de ProConnect reste un chantier
indépendant et ne doit plus bloquer la conception du portail.
