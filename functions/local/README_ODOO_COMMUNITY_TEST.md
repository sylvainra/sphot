# SPHOT PUBLICITAIRE → Odoo Community local (TEST)

Cette passerelle est **strictement locale**. Elle ne doit jamais être déployée
dans Firebase ou exposée sur Internet. Elle écoute uniquement sur
`127.0.0.1:8767`, utilise l'API JSON-2 du serveur Odoo local
`127.0.0.1:8069`, et ne traite **aucun paiement bancaire réel**. Un
règlement comptable manuel peut être simulé uniquement dans la base de test.

## Prérequis

- Odoo Community 20 local ouvert sur `http://localhost:8069`.
- Base Odoo `sphot_publicitaire_test`, Ventes activé.
- Clé API Odoo sauvegardée par l'utilisateur, non copiée dans le dépôt.
- Compte annonceur SPHOT existant, approuvé, connecté dans Flutter Web.
- Node.js et dépendances du répertoire `functions` installées (`npm ci --prefix functions`).
- Configuration SPHOT enregistrée : SPHOT PUBLICITAIRE, DIFFUSION,
  PLANIFICATION, validations juridiques et tarif publié.

## Lancer sur l'ordinateur Windows (PowerShell n° 1)

Dans `C:\Users\surfS\sphot` :

```powershell
$odooSecure = Read-Host "Colle ta cle API Odoo (saisie invisible)" -AsSecureString
$odooPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($odooSecure)
try {
    $env:SPHOT_ODOO_LOCAL_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($odooPtr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($odooPtr)
    Remove-Variable odooPtr,odooSecure -ErrorAction SilentlyContinue
}
node functions/local/odoo_community_bridge_server.js
```

La clé API existe uniquement dans l'environnement de ce terminal et du
processus Node enfant. Elle n'est ni affichée ni enregistrée sur disque.
Fermer le terminal après les tests.

## Lancer SPHOT dans un autre PowerShell

```powershell
flutter run -d chrome -t lib/main.dart --web-port=8766 --dart-define=SPHOT_ODOO_LOCAL=true
```

Ouvrir `http://localhost:8766/#/professional-login`, se connecter avec le
compte annonceur SPHOT **BLUE SURF SCHOOL**, puis ouvrir **DEVIS & COMMANDE**.

Le bouton « CONFIRMER LA COMMANDE TEST » transmet au serveur local uniquement
la référence de dossier et le devis affiché. Le serveur vérifie la session
Firebase, lit le dossier en respectant ses droits d'accès, récupère le devis
publié du service SPHOT, compare les données, puis recherche la référence de
commande dans Odoo **avant toute création**. Si la commande existe, elle est
réutilisée ; sinon, le client, un produit technique générique puis la commande
sont créés dans Odoo. Le client et le produit ne sont pas préconfigurés.

Dans Odoo → Ventes → Commandes, contrôler la référence SPHOT, le nom et
le montant HT. Revenir au devis SPHOT : la même commande est retrouvée.

## Facturer la commande existante (deuxième étape du test)

Après avoir retrouvé **S00001** dans **DEVIS & COMMANDE** :

1. Ouvrir **PAIEMENT CB** dans SPHOT. La rubrique « FACTURATION ODOO —
   ENVIRONNEMENT LOCAL DE TEST » charge la commande depuis Odoo.
2. Cliquer une seule fois sur **CRÉER LA FACTURE TEST DANS ODOO**, puis
   confirmer dans la boîte de dialogue.
3. Ouvrir Odoo → Facturation → Clients → Factures pour constater la facture
   **validée**, reliée à la commande déjà créée. Son numéro est attribué
   par Odoo ; ne pas en inventer un côté SPHOT.
4. Passer à **DOCUMENTS & FACTURES**, puis revenir à **PAIEMENT CB** : la
   même facture doit réapparaître. Le bouton de création n'apparaît plus.

La passerelle passe par l'assistant officiel de facturation des ventes
`sale.advance.payment.inv` (`create_invoices`), puis vérifie les montants
avant `account.move/action_post`. Elle recherche toute facture existante liée
à la commande **avant** de créer quoi que ce soit. Un second appel ne crée
pas de deuxième facture ; s'il y a plusieurs factures ou un écart de montants,
le test s'arrête avec un message d'erreur. Une facture dans Odoo n'est pas
un paiement : elle reste à régler.

**Ne pas utiliser manuellement « Créer une facture » dans Odoo** pour ce
test : nous vérifions que SPHOT réalise ce travail via l'API.

## Simulation comptable du règlement (troisième étape du test)

Après apparition de la facture validée dans **PAIEMENT CB** :

1. Cliquer sur **SIMULER LE RÈGLEMENT DANS ODOO (SANS CB)**.
2. Confirmer l'enregistrement **manuel de test** dans la boîte de dialogue.
3. Odoo doit mettre à jour le statut de la facture (typiquement `in_payment`,
   parfois `paid` selon sa configuration comptable). Le numéro de facture,
   ses montants et la commande S00001 restent identiques.
4. Passer dans **DOCUMENTS & FACTURES**, puis revenir dans **PAIEMENT CB** :
   le statut de règlement doit être retrouvé et le bouton masqué.

Le serveur n'accepte **qu'un seul journal de type `cash` (caisse)** dans cette
base de test, avec une méthode **`manual` entrante** ; il refuse de choisir un
journal bancaire ou un fournisseur de paiement, ainsi que plusieurs caisses
ambiguës. Si ce prérequis manque, la simulation s'arrête avec un message de
configuration, sans inventer de paiement. Le serveur utilise l'assistant natif
`account.payment.register`, puis **relit Odoo** pour confirmer le résultat.
Un second clic, un changement de rubrique ou un redémarrage de la passerelle
ne doivent pas engendrer un deuxième règlement.

**Attention :** une inscription comptable manuelle n'est **pas** un paiement CB
et ne constitue pas une preuve d'encaissement réel. L'état `in_payment` n'est
pas équivalent à `paid` : Odoo peut attendre une opération de rapprochement
comptable. Aucun état n'est propagé dans Firestore et aucune campagne n'est
activée. Il ne faut pas traiter cette simulation comme une validation d'achat
pour la production.

## Aperçu visuel CB et activation (quatrième étape du test)

Sur le dossier BLUE SURF SCHOOL, revenir à **PAIEMENT CB** après avoir
consulté la facture existante. La rubrique locale propose maintenant :

1. **VOIR LA SIMULATION DE PAIEMENT CB** : une maquette avec une carte fictive,
   le montant et trois résultats (acceptée, refusée, en attente). Aucun
   numéro bancaire ne doit être saisi. Le résultat de cette seule maquette
   est conservé entre les rubriques pendant la session Flutter en cours.
2. **PRÉVISUALISER L'ACTIVATION (TEST)** : consulter les contrôles de commande,
   facture et règlement comptable, ainsi que les deux points volontairement
   bloquants : aucune preuve CB réelle et aucune autorisation de publication.

Ces boutons n'appellent **aucun endpoint de paiement** et ne modifient **ni**
la facture Odoo déjà soldée **ni** Firestore. Un résultat « CB acceptée » dans
la maquette ne signifie **jamais** que Odoo a créé une transaction CB.

**Étape distincte à venir :** pour éprouver une véritable transaction de test
en ligne dans Odoo, utiliser le **prestataire Démo** d'Odoo 20 en mode test
sur une facture **non réglée**. La facture FAC/2026/00001 est déjà soldée par
la caisse de test : ne pas tenter de la faire payer une seconde fois. Odoo
Démo permet de choisir le résultat sans identifiants bancaires ni carte réelle.
Référence : https://www.odoo.com/documentation/20.0/fr/applications/finance/payment_providers/demo.html

## Deuxième achat : prestataire natif Odoo Démo (cinquième étape)

La facture du premier cycle **doit déjà être soldée**. Le deuxième cycle
réutilise le même dossier BLUE SURF SCHOOL, son client Odoo et le prix figé
de la première commande, mais utilise une **autre référence SPHOT** portant
le suffixe `-DEMO-02`. La deuxième commande, sa facture et les transactions
de son portail restent séparées de S00001 et FAC/2026/00001.

**Reprise du test local :** le premier achat Odoo n'a volontairement pas été
écrit dans Firestore (`order` / `quoteOrderCompleted` peuvent être absents).
La deuxième commande reprend donc la ligne commerciale, le produit, le client,
la remise et les taxes **directement depuis la première vente Odoo déjà
facturée et soldée**. Les montants HT, TVA et TTC des deux commandes doivent
être identiques, sinon la confirmation s'arrête. Après navigation ou relance
du navigateur, le statut de ce deuxième achat est retrouvé dans Odoo.

Dans **Odoo local**, avant le paiement, vérifier :

- `Facturation → Configuration → Paiements en ligne → Démo` : prestataire
  en **Mode test**, **Publié**, moyen Démo activé.
- `Facturation → Configuration → Paramètres` : dans la section paiements
  clients, activer **Paiement en ligne des factures** si nécessaire, puis
  enregistrer. Cela permet d'obtenir « Payer maintenant » sur le portail.

Dans **SPHOT → PAIEMENT CB**, sous les anciens contrôles, la nouvelle section
`ACHAT N° 2 — PAIEMENT DÉMO NATIF ODOO` offre :

1. **CRÉER LA DEUXIÈME COMMANDE DE TEST** : Odoo crée la nouvelle vente à
   partir du devis SPHOT *historique* enregistré, sans nouveau compte ni
   écriture Firestore. Un autre clic retrouve la commande créée.
2. **CRÉER LA FACTURE DÉMO DANS ODOO** : l'assistant Odoo facture cette
   deuxième commande, attribue son propre numéro et la valide.
3. **PRÉPARER LE PORTAIL PAIEMENT ODOO** : le pont vérifie le prestataire
   Démo en mode test, que la facture est encore intégralement non réglée,
   puis demande à Odoo un lien d'accès au portail de cette facture.
4. **OUVRIR LE PAIEMENT DÉMO ODOO** : ouvrir ce lien dans un autre onglet,
   utiliser le moyen « Démo » d'Odoo et sélectionner le résultat voulu.
5. Retourner dans SPHOT et cliquer sur **ACTUALISER LA TRANSACTION ODOO
   DÉMO** : le serveur relit les transactions `payment.transaction` Odoo
   liées à cette **seconde** facture et vérifie le montant ainsi que le
   prestataire `demo`.

Le lien du portail contient un **jeton d'accès privé** : ne pas le publier,
le coller dans une conversation ni prendre une capture incluant l'URL
complète. La fenêtre de paiement doit rester sur `127.0.0.1:8069`.

La démo native enregistre des transactions **fictives** dans la seule base
Odoo de test. Elle peut laisser la facture au statut `in_payment` plutôt que
`paid` selon la comptabilité. Aucun succès Odoo Démo ne devient une preuve
d'encaissement réel ou une autorisation d'activation publicitaire SPHOT.

Documentation du portail de paiement :
https://www.odoo.com/documentation/20.0/fr/applications/finance/accounting/payments.html

## Protection

- Aucune écriture Firestore, aucune Cloud Function modifiée ou déployée.
- Une facture de test peut être créée et validée **uniquement après un clic
  explicite dans SPHOT** dans la base Odoo locale `sphot_publicitaire_test`.
- Un règlement **comptable manuel de test** peut être enregistré après
  confirmation explicite dans SPHOT, uniquement dans la base locale.
- Aucune transaction bancaire, aucun email envoyé, aucune campagne active.
- La TVA est calculée par Odoo selon sa configuration, jamais forcée à 20 %
  depuis SPHOT. Ne pas traiter une TVA à zéro comme une validation fiscale.
- Ne jamais coller la clé dans Git, Flutter, une capture ou un message.
- En cas d'erreur, **ne pas recréer BLUE SURF SCHOOL** ; recopier uniquement
  le message d'erreur sans secrets.
- L'ancienne simulation factice `:8765` est conservée, mais elle n'est pas
  utilisée avec le drapeau `SPHOT_ODOO_LOCAL=true`.
