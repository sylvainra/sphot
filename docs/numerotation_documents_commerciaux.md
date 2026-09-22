# Numérotation des documents commerciaux SPHOT

Ce document fixe la règle de numérotation validée pour le parcours Admin
SPHOT. Toute évolution doit faire l'objet d'un commit dédié avant modification
du code ou des données Firebase.

## Principes

- La référence administrative identifie le dossier Admin et l'adhérent. Elle
  ne constitue pas un numéro de facture.
- Les devis et commandes internes sont rattachés au dossier Admin et peuvent
  reprendre le numéro d'adhérent à six chiffres.
- Les factures utilisent une séquence fiscale globale, chronologique et
  continue, indépendante des références administratives.
- Les avoirs utilisent leur propre séquence et référencent obligatoirement la
  facture corrigée.
- Le numéro de bon de commande, le numéro d'engagement juridique et le code
  service Chorus Pro fournis par l'organisme restent des références externes.

## Formats validés

| Document | Format | Exemple |
| --- | --- | --- |
| Dossier Admin | `SPHOT-ADM-{PAYS}-{ANNEE}-{ADHERENT}` | `SPHOT-ADM-FRA-2026-000061` |
| Devis | `DV-{ANNEE}-{ADHERENT}-{SEQUENCE}` | `DV-2026-000061-001` |
| Commande interne | `CMD-{ANNEE}-{ADHERENT}-{SEQUENCE}` | `CMD-2026-000061-001` |
| Facture | `FA-{ANNEE}-{SEQUENCE_FISCALE}` | `FA-2026-000001` |
| Avoir | `AV-{ANNEE}-{SEQUENCE_AVOIR}` | `AV-2026-000001` |

## Hiérarchie et rattachements

```text
SPHOT-ADM-FRA-2026-000061
├── DV-2026-000061-001
├── CMD-2026-000061-001
├── FA-2026-000001
└── AV-2026-000001 → FA-2026-000001
```

Chaque document commercial stocke au minimum :

- `adminUid` ;
- `administrativeReference` ;
- son numéro propre (`quoteNumber`, `orderNumber`, `invoiceNumber` ou
  `creditNoteNumber`) ;
- `year` et `sequence` ;
- `createdAt` et `updatedAt` ;
- les références du document précédent lorsqu'elles existent.

Une facture conserve notamment `quoteNumber`, `orderNumber` et les références
externes de l'organisme. Un avoir conserve `originalInvoiceNumber` et
`originalInvoiceId`.

## Compteurs Firestore

Les compteurs sont distincts et ne doivent jamais être décrémentés ni
réutilisés après l'annulation d'un document :

- `counters/adminRequests_{ANNEE}` : dossiers Admin ;
- `counters/quotes_{ANNEE}_{ADHERENT}` : devis d'un adhérent ;
- `counters/orders_{ANNEE}_{ADHERENT}` : commandes internes d'un adhérent ;
- `counters/invoices_{ANNEE}` : factures fiscales globales ;
- `counters/creditNotes_{ANNEE}` : avoirs globaux.

L'attribution d'un numéro doit toujours être effectuée dans une transaction
Firestore afin d'empêcher les doublons lors de créations simultanées.

## Collections Firestore

- `quotes/{quoteId}` ;
- `orders/{orderId}` ;
- `invoices/{invoiceId}` ;
- `creditNotes/{creditNoteId}`.

Les identifiants techniques Firestore peuvent être générés automatiquement.
Les numéros commerciaux restent des champs métier immuables après émission.
