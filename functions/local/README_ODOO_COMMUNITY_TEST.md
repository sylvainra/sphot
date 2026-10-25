# SPHOT PUBLICITAIRE → Odoo Community local (TEST)

Cette passerelle est **strictement locale**. Elle ne doit jamais être déployée
dans Firebase ou exposée sur Internet. Elle écoute uniquement sur
`127.0.0.1:8767`, utilise l'API JSON-2 du serveur Odoo local
`127.0.0.1:8069`, et ne traite **aucun paiement**.

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

## Protection

- Aucune écriture Firestore, aucune Cloud Function modifiée ou déployée.
- Une facture de test peut être créée et validée **uniquement après un clic
  explicite dans SPHOT** dans la base Odoo locale `sphot_publicitaire_test`.
- Aucune transaction bancaire, aucun email envoyé, aucune campagne active.
- La TVA est calculée par Odoo selon sa configuration, jamais forcée à 20 %
  depuis SPHOT. Ne pas traiter une TVA à zéro comme une validation fiscale.
- Ne jamais coller la clé dans Git, Flutter, une capture ou un message.
- En cas d'erreur, **ne pas recréer BLUE SURF SCHOOL** ; recopier uniquement
  le message d'erreur sans secrets.
- L'ancienne simulation factice `:8765` est conservée, mais elle n'est pas
  utilisée avec le drapeau `SPHOT_ODOO_LOCAL=true`.
