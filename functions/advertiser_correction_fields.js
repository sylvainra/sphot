/* eslint-disable max-len, indent, comma-dangle, brace-style, operator-linebreak, object-curly-spacing, quote-props */
"use strict";

// Écriture strictement limitée aux champs demandés par le Super Admin.
// Le serveur relit le dossier et la liste autorisée dans une transaction.
const ACTIVITY_TYPES = new Set([
  "Cosmétique", "Optique / lunettes", "Surfwear / prêt-à-porter",
  "Sports nautiques", "Tourisme", "Restauration", "Produits alimentaires",
  "Boissons", "Hôtellerie", "Hôtellerie de plein air", "Commerce local",
  "Institutionnel", "Autre",
]);

const FIELD_SCOPES = Object.freeze({
  "identity.contactCivility": "identity",
  "identity.contactLastName": "identity",
  "identity.contactFirstName": "identity",
  "identity.contactFunction": "identity",
  "identity.contactPhone": "identity",
  "identity.contactEmail": "identity",
  "establishment.registrationMode": "establishment",
  "establishment.siret": "establishment",
  "establishment.legalName": "establishment",
  "establishment.businessName": "establishment",
  "establishment.activityTypes": "establishment",
  "establishment.registrationCountryCode": "establishment",
  "establishment.foreignRegistrationNumber": "establishment",
  "establishment.foreignRegistrationAuthority": "establishment",
  "establishment.foreignProof": "establishment",
  "establishment.address": "establishment",
  "establishment.addressComplement": "establishment",
  "establishment.postalCode": "establishment",
  "establishment.city": "establishment",
  "location": "location",
  "visual": "visual",
  "destination": "destination",
  "legal": "legal",
});

/**
 * Construit une erreur HTTP contrôlée.
 * @param {number} code Code HTTP.
 * @param {string} message Motif de refus.
 * @return {Error} Erreur annotée.
 */
function deny(code, message) {
  const e = new Error(message);
  e.httpStatus = code;
  return e;
}

/**
 * Normalise une chaîne et limite sa longueur.
 * @param {*} value Valeur à contrôler.
 * @param {string} key Nom du champ.
 * @param {number} limit Nombre maximal de caractères.
 * @return {string} Texte normalisé.
 */
function textValue(value, key, limit = 300) {
  if (typeof value !== "string" || value.trim().length > limit) {
    throw deny(400, "Valeur non conforme : " + key);
  }
  return value.trim();
}

/**
 * Normalise un texte obligatoire.
 * @param {*} value Valeur à contrôler.
 * @param {string} key Nom du champ.
 * @param {number} limit Nombre maximal de caractères.
 * @return {string} Texte obligatoire.
 */
function requireText(value, key, limit = 300) {
  const text = textValue(value, key, limit);
  if (!text) throw deny(400, "Valeur manquante : " + key);
  return text;
}

/**
 * Valide un patch de correction contre la liste du dossier Firestore.
 * Ne donne jamais au client le droit de modifier les statuts, revues,
 * historiques, abonnements, prix ou champs non sélectionnés.
 * @param {Object} data Dossier Firestore courant.
 * @param {Object} fields Valeurs fournies par le client.
 * @param {Object} fv Firebase FieldValue.
 * @param {string} requestId Identifiant du dossier.
 * @return {Object} Patch Firestore en dot notation.
 */
function buildCorrectionFieldPatch(data, fields, fv, requestId) {
  const correction = data.correctionRequest || {};
  if (data.status !== "changes_requested" ||
      correction.status !== "changes_requested" ||
      !Array.isArray(correction.fields) || !correction.fields.length) {
    throw deny(409, "Aucune correction champ par champ autorisée.");
  }
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
    throw deny(400, "Corrections invalides.");
  }
  const keys = Object.keys(fields);
  if (!keys.length || keys.length > correction.fields.length ||
      keys.some((key) => !Object.hasOwn(FIELD_SCOPES, key) ||
        !correction.fields.includes(key) ||
        ["location", "visual", "destination", "legal"].includes(key))) {
    throw deny(403, "Modification de champ non autorisée.");
  }
  const updates = {"updatedAt": fv.serverTimestamp()};
  const changes = {};
  for (const key of keys) {
    const value = fields[key];
    changes[key] = true;
    if (key === "identity.contactCivility") {
      const civility = requireText(value, key, 30);
      if (!["Madame", "Monsieur"].includes(civility)) throw deny(400, "Civilité invalide.");
      updates.contactCivility = civility;
      updates.civilite = civility;
    } else if (key === "identity.contactLastName") {
      updates.contactLastName = requireText(value, key, 100).toUpperCase();
    } else if (key === "identity.contactFirstName") {
      updates.contactFirstName = requireText(value, key, 100);
    } else if (key === "identity.contactFunction") {
      updates.contactFunction = requireText(value, key, 120);
    } else if (key === "identity.contactPhone") {
      updates.contactPhone = requireText(value, key, 60);
    } else if (key === "identity.contactEmail") {
      const mail = requireText(value, key, 250);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) throw deny(400, "Email invalide.");
      updates.contactEmail = mail;
    } else if (key === "establishment.registrationMode") {
      const mode = requireText(value, key, 20);
      if (!["france", "international"].includes(mode)) throw deny(400, "Immatriculation invalide.");
      updates.registrationMode = mode;
      if (mode === "france") {
        updates.registrationCountryCode = "FR";
        updates["establishment.country"] = "FRANCE";
      }
    } else if (key === "establishment.siret") {
      const siret = requireText(value, key, 20);
      if (!/^\d{14}$/.test(siret)) throw deny(400, "SIRET invalide.");
      updates["establishment.siret"] = siret;
      updates["establishment.siren"] = siret.slice(0, 9);
      updates.siret = siret;
      updates.siren = siret.slice(0, 9);
      updates["registryPrecheck.status"] = "unverified";
    } else if (key === "establishment.legalName") {
      const name = requireText(value, key, 200).toUpperCase();
      updates["establishment.legalName"] = name;
      updates.organisation = name;
    } else if (key === "establishment.businessName") {
      const name = requireText(value, key, 200).toUpperCase();
      updates["establishment.businessName"] = name;
      updates.advertiserName = name;
    } else if (key === "establishment.activityTypes") {
      if (!value || typeof value !== "object" || Array.isArray(value) ||
          Object.keys(value).some((item) => !["types", "other"].includes(item)) ||
          !Array.isArray(value.types) || !value.types.length ||
          value.types.length > ACTIVITY_TYPES.size ||
          value.types.some((item) => !ACTIVITY_TYPES.has(item)) ||
          new Set(value.types).size !== value.types.length) {
        throw deny(400, "Activités invalides.");
      }
      const other = textValue(value.other, key, 300);
      if (value.types.includes("Autre") && !other) {
        throw deny(400, "Précisez l’activité Autre.");
      }
      updates["establishment.activityTypes"] = value.types;
      updates["establishment.activityType"] = value.types[0];
      updates["establishment.activityTypeOther"] =
        value.types.includes("Autre") ? other : "";
    } else if (key === "establishment.registrationCountryCode") {
      const country = requireText(value, key, 100);
      if (!/^[A-Za-z][A-Za-z -]{1,99}$/.test(country)) {
        throw deny(400, "Pays invalide.");
      }
      // Le code pays et son libellé doivent être sélectionnés ensemble.
      // La mise à jour est limitée au pays d'immatriculation.
      updates.registrationCountryCode = country;
    } else if (key === "establishment.foreignRegistrationNumber") {
      updates.foreignRegistrationNumber = requireText(value, key, 100);
    } else if (key === "establishment.foreignRegistrationAuthority") {
      updates.foreignRegistrationAuthority = requireText(value, key, 160);
    } else if (key === "establishment.foreignProof") {
      if (!value || typeof value !== "object" || Array.isArray(value)) {
        throw deny(400, "Justificatif invalide.");
      }
      const urlText = requireText(value.url, key, 2048);
      let url;
      try {url = new URL(urlText);} catch (_) {
        throw deny(400, "URL de justificatif invalide.");
      }
      if (url.protocol !== "https:" ||
          url.hostname !== "firebasestorage.googleapis.com" ||
          !decodeURIComponent(url.pathname).includes(
              "/advertiser_requests/" + requestId + "/")) {
        throw deny(400, "Justificatif hors du dossier.");
      }
      updates.foreignProof = {
        url: urlText,
        fileName: requireText(value.fileName, key, 250),
        extension: requireText(value.extension, key, 10),
        fileSizeBytes: value.fileSizeBytes,
        uploadedAt: fv.serverTimestamp(),
      };
    } else if (key === "establishment.address") {
      updates["establishment.address"] = requireText(value, key, 300);
    } else if (key === "establishment.addressComplement") {
      updates["establishment.addressComplement"] = textValue(value, key, 300);
    } else if (key === "establishment.postalCode") {
      updates["establishment.postalCode"] = requireText(value, key, 20);
    } else if (key === "establishment.city") {
      updates["establishment.city"] = requireText(value, key, 120).toUpperCase();
    }
  }
  if (changes["identity.contactFirstName"] ||
      changes["identity.contactLastName"]) {
    const first = updates.contactFirstName || data.contactFirstName || "";
    const last = updates.contactLastName || data.contactLastName || "";
    updates.contactName = (first + " " + last).trim();
  }
  if (keys.some((key) => key.startsWith("identity."))) {
    updates.profileCompleted = true;
  }
  if (keys.some((key) => key.startsWith("establishment."))) {
    updates.establishmentCompleted = true;
    updates["establishment.updatedAt"] = fv.serverTimestamp();
  }
  return updates;
}

/**
 * Expose la sauvegarde des corrections après authentification Firebase.
 * @param {Object} dependencies Services Firebase injectés.
 * @param {Object} dependencies.admin SDK d'administration Firebase.
 * @param {Function} dependencies.onRequest Déclaration de fonction HTTPS.
 * @return {Function} Gestionnaire de requêtes.
 */
function registerAdvertiserCorrectionFields({admin, onRequest}) {
  return onRequest(
      {region: "us-central1", cors: true, cpu: 1, memory: "256MiB"},
      async (req, res) => {
        if (req.method !== "POST") {
          res.status(405).json({success: false, error: "Méthode refusée."});
          return;
        }
        const body = req.body || {};
        const requestId = typeof body.requestId === "string" ?
          body.requestId.trim() : "";
        if (!/^[A-Za-z0-9_-]{8,128}$/.test(requestId) ||
            Object.keys(body).some((key) => !["requestId", "fields"].includes(key))) {
          res.status(400).json({success: false, error: "Requête invalide."});
          return;
        }
        const header = req.headers.authorization || "";
        if (!header.startsWith("Bearer ")) {
          res.status(401).json({success: false, error: "Session absente."});
          return;
        }
        let identity;
        try {
          identity = await admin.auth().verifyIdToken(header.slice(7), true);
        } catch (_) {
          res.status(401).json({success: false, error: "Session expirée."});
          return;
        }
        if (identity.uid !== requestId ||
            identity.role !== "advertiser_candidate" ||
            identity.advertiserRequestId !== requestId) {
          res.status(403).json({success: false, error: "Accès refusé."});
          return;
        }
        try {
          const db = admin.firestore();
          const ref = db.collection("advertiserRequests").doc(requestId);
          await db.runTransaction(async (tx) => {
            const snapshot = await tx.get(ref);
            if (!snapshot.exists) throw deny(404, "Dossier introuvable.");
            const patch = buildCorrectionFieldPatch(snapshot.data() || {},
                body.fields, admin.firestore.FieldValue, requestId);
            tx.update(ref, patch);
          });
          res.status(200).json({success: true});
        } catch (error) {
          if (!error.httpStatus) console.error("Correction annonceur:", error);
          res.status(error.httpStatus || 500).json({
            success: false,
            error: error.httpStatus ? error.message : "Enregistrement indisponible.",
          });
        }
      },
  );
}

module.exports = {FIELD_SCOPES, buildCorrectionFieldPatch,
  registerAdvertiserCorrectionFields};
