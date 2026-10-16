# SPHOT ADMIN — reprise du chantier PAIEMENT (13/10/2026)

> Référence de continuité entre discussions. Pour reprendre, **lire cette note et les fichiers de cette branche avant toute modification**. Ne pas revenir à l'ancien panneau d'abonnement de `main` et ne pas réintroduire le tarif fixe 500 €.

## Dépôt et branche de travail à utiliser

- GitHub : `Sylvainra/SPHOT`
- Branche : `codex/advertiser-pricing-table-v1`
- Écran PAIEMENT : `lib/web/admin/pages/admin_payment_panel.dart`
- Message commercial et affichage dans le tableau de bord : `lib/web/admin/pages/admin_dashboard_page.dart`
- Service de devis/grille publiée : `lib/services/published_commercial_quote_service.dart`
- Source dynamique de la sélection des postes : `lib/web/admin/services/admin_station_pricing_preview.dart`

## Décisions du 13 octobre 2026

1. Grille progressive annuelle **par tranche**, pas de tarif fixe par poste :
   - 1er poste de secours : 499,00 € HT ;
   - 2e à 4e postes : 399,00 € HT par poste ;
   - 5e à 9e postes : 299,00 € HT par poste ;
   - à partir du 10e : 199,00 € HT par poste.
2. Grille gérée/publiée par le Super Admin, modifiable sans changer le code ; afficher son nom/référence et les tarifs réellement publiés. Ne pas coder ces valeurs en dur comme source d'autorité dans l'étape PAIEMENT.
3. Écran PAIEMENT : titre **PAIEMENT** uniquement, accompagné du marqueur Fire rouge SVG (`data/icons/fire_red_icon.svg`) commun aux étapes. Supprimer tout soulignement jaune.
4. Sous le titre : **Postes de Secours sollicités**, puis chaque poste sur sa propre ligne ; **Grille tarifaire utilisée**, puis la référence de la grille, sans les trois lignes supplémentaires de commentaire ; **TARIFICATION**, puis le détail des tranches actives (ex. « 1er Poste de Secours : 499,00 € », « De 2 à 4 Postes de Secours : 3 × 399,00 € », etc.) ; **TOTAL ANNUEL HT** dans le même alignement, puis **« Avant TVA et fiscalité... »**.
5. Paiements réels non activés : conserver les modes carte bancaire et facturation/commande publique existants, sans déclencher de prélèvement. Aucun frais d'installation ni de formation.
6. Message commercial de bienvenue centré sur la carte : ne l'afficher **qu'à la première connexion de l'Admin**, pas à chaque connexion. Le fait que le message ait été ajouté récemment explique possiblement son apparition sur un ancien profil, mais l'état réel des anciens comptes doit être contrôlé. Ne pas l'afficher systématiquement.

## Modifications effectivement faites (branches et commits)

- **Branche de référence ci-dessus** : `5939e3674bb0ec0d5092c45c4e3cf4fd235b060a` — simplification de `admin_payment_panel.dart`, sans remplacer le calcul de la grille publiée (suppression « VOTRE OFFRE ANNUELLE », liste verticale sans puces, intitulés, lignes tarifaires compactes, total aligné et phrase finale).
- **Même branche** : `e316903a3328d83625076c96b6bd967c098f0c36` — mémorisation du message commercial dès son premier affichage, localement et dans `adminRequests/{uid}.welcomePromotionSeenAt`, en le gardant visible pendant la session d'origine.
- **Branche erronée à IGNORER** : `fix/admin-paiement-compact-20261013`, commits `4a5333e` puis `55f7378`. Ils modifient un ancien `admin_subscription_panel.dart` non conforme au chantier actuel et **ne doivent pas être fusionnés**.
- Les corrections sont sur une branche et **non fusionnées dans `main`** à la date de cette note. Une compilation et des tests visuels/fonctionnels Flutter restent à faire.

## Corrections complémentaires du 13 octobre (captures utilisateur)

- `2da5869ea2fd06cf77e35f793109dea82bc920f5` : `admin_payment_panel.dart` harmonisé avec le panneau ABONNEMENT (430 px, même header et Fire rouge SVG à échelle 1,5), lignes comptables avec montants alignés à droite, TOTAL ANNUEL HT **rouge** et mention exacte « Avant TVA et fiscalité applicable. Aucun devis contractuel ni montant à payer confirmé. ».
- `0b7d756aed3343944be96fe5fb0839430636f7d2` : `admin_dashboard_page.dart` transmet `idSphot` (ou numéro explicite alternatif) + nom du poste de secours au volet PAIEMENT lorsque le numéro est renseigné.
- Audit statique des deux fichiers effectué : conservation du service de grille publiée et de ses montants ; gabarit de 430 px et SVG contrôlés. **Compilation et test visuel Flutter non effectués** (SDK non disponible dans l'environnement d'exécution distant).
- Pour tester sur la branche : `git switch codex/advertiser-pricing-table-v1` puis `git pull --ff-only origin codex/advertiser-pricing-table-v1` (après `git status` et sauvegarde des changements locaux), `flutter pub get`, `flutter run -d chrome -t lib/main_web_admin.dart`.
- Vérifier notamment le cas des deux postes à 499 € + 399 € = 898 € HT, le libellé `numéro - nom`, l'alignement et le total rouge, la mention sans soulignement jaune.

## Règles pour la reprise

- Ne pas repartir d'une version ancienne récupérée sur `main` ni réécrire le composant PAIEMENT au complet.
- Relire l'état HEAD de la branche `codex/advertiser-pricing-table-v1` et faire des corrections **localisées**.
- Vérifier que le montant simulé, le nombre de postes et la référence de la grille proviennent de la même version publiée.
- Vérifier la première connexion sur nouvel Admin et ancien profil, puis une reconnexion, y compris sur un second navigateur (Firestore doit empêcher la réapparition).
- Tester rendu, suppression effective du soulignement jaune, noms des postes, tranches et total. Ne pas annoncer de compilation validée avant de l'avoir exécutée.
- Préserver les autres étapes et workflows validés.

## Retours du test visuel du 13 octobre (21 h 37)

- **Validé par l'utilisateur** : largeur du volet PAIEMENT et taille du marker Fire SVG, numéros et noms des SPHOTS, présentation comptable et total rouge visibles sur capture. Ne plus toucher à ces éléments sans nouvelle demande.
- **Corrigé** : suppression de « Grille tarifaire utilisée » et de sa référence isolée ; intitulé dynamique **« TARIFICATION SUIVANT GRILLE TARIFAIRE ${quote.pricingReference} »** dans `lib/web/admin/pages/admin_payment_panel.dart`, commit `04e0236fc4198f0b6fbe5f76b3ddee654ec8713f`.
- **À décider ensuite (CGV)** : intégrer la consultation et l'acceptation explicite des CGV dans `ABONNEMENT`, idéalement juste avant « VALIDER LA COMMANDE D’ABONNEMENT », en réutilisant les versions publiées de `legalDocuments`, en historisant l'acceptation par version, UID et horodatage Firestore. La grille de tarification n'est pas une acceptation des CGV. **Ne pas coder ni activer la validation juridique sur une CGV non publiée sans accord sur le point du parcours.**
