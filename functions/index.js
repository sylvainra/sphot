const {sendSphotMail} = require("./sphot_email_design");
const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {getDownloadURL} = require("firebase-admin/storage");
const nodemailer = require("nodemailer");
const PDFDocument = require("pdfkit");

admin.initializeApp();

const SMTP_USER = "admin@sphot.app";
const MAIL_FROM = "\"SPHOT\" <no-reply@sphot.app>";
const SPHOT_LOGIN_URL = "https://sphot.app";


setGlobalOptions({maxInstances: 10});

/**
 * Construit la projection strictement publique d'un SPHOT.
 *
 * @param {string} territoireId Identifiant du territoire.
 * @param {string} spotId Identifiant du SPHOT.
 * @param {Object} spot Données internes du SPHOT.
 * @return {Object} Données autorisées sur la carte publique.
 */
function buildPublicSpot(territoireId, spotId, spot) {
  const publicFields = [
    "idSphot",
    "nomSecours",
    "nomSphot",
    "typeSphot",
    "isPosteSecours",
    "sphotLat",
    "sphotLng",
    "pays",
    "region",
    "departement",
    "ville",
    "villeLat",
    "villeLng",
    "departementLat",
    "departementLng",
    "logoVille",
    "siteInternetVille",
    "adresseWebcam",
    "arretesMunicipaux",
    "statutBaignade",
    "periode",
    "heureDebut",
    "heureFin",
    "phone",
    "telephonePoste",
    "activite",
    "equipement",
    "labelSphot",
    "liveFlag",
  ];

  const result = {territoireId, spotId};
  publicFields.forEach((field) => {
    if (spot[field] !== undefined && spot[field] !== null) {
      result[field] = spot[field];
    }
  });
  result.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  return result;
}

/**
 * Extrait uniquement l'état public temps réel d'un SPHOT historique.
 *
 * @param {Object} spot Données de la collection racine spots.
 * @return {Object} État public à fusionner dans la projection.
 */
function buildPublicLiveState(spot) {
  const liveFields = [
    "liveFlag",
    "statutBaignade",
    "periode",
    "heureDebut",
    "heureFin",
    "phone",
    "telephonePoste",
  ];
  const result = {};
  liveFields.forEach((field) => {
    if (spot[field] !== undefined && spot[field] !== null) {
      result[field] = spot[field];
    }
  });
  if (spot.liveFlag === undefined || spot.liveFlag === null) {
    result.liveFlag = admin.firestore.FieldValue.delete();
  }
  result.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  return result;
}

/**
 * Fusionne la configuration territoriale avec l'état historique public.
 * L'absence de liveFlag dans un document historique existant est conservée.
 *
 * @param {Object} spot Configuration du SPHOT territorial.
 * @param {Object|null} historical État de la collection racine spots.
 * @return {Object} Données consolidées.
 */
function mergePublicSpotData(spot, historical) {
  const result = {...spot, ...(historical || {})};
  if (historical && historical.liveFlag === undefined) {
    delete result.liveFlag;
  }
  return result;
}

/**
 * Complète les champs géographiques vides avec la demande administrative.
 *
 * @param {Object} spot Données consolidées du SPHOT.
 * @param {Object} territory Données publiques du territoire.
 * @return {Object} Données complétées sans écraser les valeurs du SPHOT.
 */
function mergePublicTerritoryData(spot, territory) {
  const result = {...spot};
  const normalizedTerritory = {
    ...territory,
    logoVille: territory.logoVille ||
      territory.logoUrl ||
      (territory.structure || {}).logoVille ||
      (territory.structure || {}).logoUrl ||
      "",
    siteInternetVille: territory.siteInternetVille ||
      territory.siteInternet ||
      (territory.structure || {}).siteInternet ||
      "",
    arretesMunicipaux: territory.arretesMunicipaux ||
      territory.reglementsBaignade ||
      territory.reglementBaignade ||
      territory.siteReglements ||
      "",
  };
  const territoryFields = [
    "pays",
    "region",
    "departement",
    "ville",
    "villeLat",
    "villeLng",
    "logoVille",
    "siteInternetVille",
    "arretesMunicipaux",
  ];

  territoryFields.forEach((field) => {
    const currentValue = result[field];
    const territoryValue = normalizedTerritory[field];
    const currentIsEmpty = currentValue === undefined ||
      currentValue === null ||
      (typeof currentValue === "string" && currentValue.trim() === "") ||
      ((field === "villeLat" || field === "villeLng") &&
        Number(currentValue) === 0);

    if (currentIsEmpty && territoryValue !== undefined &&
        territoryValue !== null) {
      result[field] = territoryValue;
    }
  });

  return result;
}

/**
 * Lit l'identifiant de territoire d'une demande administrative.
 *
 * @param {Object|null} data Données de la demande.
 * @return {string} Identifiant normalisé.
 */
function adminRequestTerritoryId(data) {
  if (!data) return "";
  const territoire = data.territoire || {};
  return (data.territoireId || territoire.territoireId || "")
      .toString()
      .trim();
}

/**
 * Indique si la demande a été validée par le Super Admin.
 *
 * @param {Object} data Données de la demande.
 * @return {boolean} Vrai lorsque l'accès administratif est validé.
 */
function isApprovedAdminRequest(data) {
  const administrativeTracking = data.administrativeTracking || {};
  return data.status === "approved" ||
    administrativeTracking.status === "approved" ||
    data.accessPhase === "configuration_access";
}

/**
 * Supprime puis reconstruit la projection publique d'un territoire.
 *
 * @param {string} territoireId Identifiant du territoire.
 * @param {boolean} publish Autorisation de publication.
 * @return {Promise<void>}
 */
async function reconcilePublicTerritory(territoireId, publish) {
  if (!territoireId) return;

  const db = admin.firestore();
  const territoryReference = db.collection("territoires").doc(territoireId);
  const publicSnapshot = await db
      .collection("publicSpots")
      .where("territoireId", "==", territoireId)
      .get();
  const spotSnapshot = publish ? await territoryReference
      .collection("spots")
      .get() : null;
  const territorySnapshot = publish ? await territoryReference.get() : null;
  const requestSnapshot = publish ? await db
      .collection("adminRequests")
      .where("territoire.territoireId", "==", territoireId)
      .get() : null;
  const approvedRequest = requestSnapshot ? requestSnapshot.docs.find(
      (document) => isApprovedAdminRequest(document.data()),
  ) : null;
  const approvedRequestData = approvedRequest ? approvedRequest.data() : {};
  const territorySources = [
    approvedRequestData.territoire || {},
    approvedRequestData,
    territorySnapshot && territorySnapshot.exists ?
      territorySnapshot.data() : {},
    ...(spotSnapshot ? spotSnapshot.docs.map((document) => {
      return document.data();
    }) : []),
    ...publicSnapshot.docs.map((document) => {
      return document.data();
    }),
  ];
  let territoryData = {};
  territorySources.forEach((source) => {
    territoryData = mergePublicTerritoryData(territoryData, source);
  });
  if (publish && (!territorySnapshot || !territorySnapshot.exists)) {
    const parentTerritoryData = {territoireId};
    const parentTerritoryFields = [
      "pays",
      "region",
      "departement",
      "ville",
      "villeLat",
      "villeLng",
      "departementLat",
      "departementLng",
      "logoVille",
      "siteInternetVille",
      "arretesMunicipaux",
    ];
    parentTerritoryFields.forEach((field) => {
      const value = territoryData[field];
      const hasValue = value !== undefined &&
        value !== null &&
        !(typeof value === "string" && value.trim() === "");
      if (hasValue) parentTerritoryData[field] = value;
    });
    parentTerritoryData.publicProjectionCreatedAt =
      admin.firestore.FieldValue.serverTimestamp();
    await territoryReference.set(parentTerritoryData, {merge: true});
  }
  const historicalSpots = new Map();
  if (spotSnapshot && !spotSnapshot.empty) {
    const historicalSnapshots = await db.getAll(
        ...spotSnapshot.docs.map((document) => {
          return db.collection("spots").doc(document.id);
        }),
    );
    historicalSnapshots.forEach((document) => {
      if (document.exists) {
        historicalSpots.set(document.id, document.data());
      }
    });
  }

  const writes = [];
  const desiredPublicIds = new Set(
      spotSnapshot ? spotSnapshot.docs.map((document) => {
        return `${territoireId}__${document.id}`;
      }) : [],
  );
  publicSnapshot.docs.forEach((document) => {
    if (!desiredPublicIds.has(document.id)) {
      writes.push({type: "delete", reference: document.ref});
    }
  });
  if (spotSnapshot) {
    spotSnapshot.docs.forEach((document) => {
      const reference = db.collection("publicSpots")
          .doc(`${territoireId}__${document.id}`);
      writes.push({
        type: "set",
        reference,
        data: buildPublicSpot(
            territoireId,
            document.id,
            mergePublicTerritoryData(
                mergePublicSpotData(
                    document.data(),
                    historicalSpots.get(document.id) || null,
                ),
                territoryData,
            ),
        ),
      });
    });
  }

  for (let index = 0; index < writes.length; index += 450) {
    const batch = db.batch();
    writes.slice(index, index + 450).forEach((write) => {
      if (write.type === "delete") {
        batch.delete(write.reference);
      } else {
        batch.set(write.reference, write.data);
      }
    });
    await batch.commit();
  }
}

/**
 * Vérifie que le territoire dispose d'un administrateur approuvé
 * dont les droits de diffusion SPHOT sont actuellement ouverts.
 *
 * @param {string} territoireId Identifiant du territoire.
 * @return {Promise<boolean>}
 */
async function isTerritoryPublic(territoireId) {
  const db = admin.firestore();
  const adminsSnapshot = await db.collection("admins")
      .where("territoireId", "==", territoireId)
      .get();

  return adminsSnapshot.docs.some((document) => {
    const data = document.data() || {};

    return data.accessStatus === "approved" &&
      data.diffusionAccessGranted === true;
  });
}

/**
 * Applique le statut d'un abonnement à la projection publique associée.
 *
 * @param {string} subscriptionId Identifiant du document abonnement.
 * @param {Object|null} subscription Données de l'abonnement.
 * @return {Promise<void>}
 */
async function reconcilePublicSubscription(subscriptionId, subscription) {
  const db = admin.firestore();
  const adminUid = ((subscription && subscription.adminUid) || subscriptionId)
      .toString().trim();
  if (!adminUid) return;

  const adminSnapshot = await db.collection("admins").doc(adminUid).get();
  const adminData = adminSnapshot.data() || {};
  const territoireId = (adminData.territoireId || "").toString().trim();
  if (!territoireId) return;

  const publish = await isTerritoryPublic(territoireId);
  await reconcilePublicTerritory(territoireId, publish);
}

/**
 * Nettoie une valeur texte et applique une valeur par défaut.
 *
 * @param {*} value Valeur à nettoyer.
 * @param {string} fallback Valeur utilisée lorsque le texte est vide.
 * @return {string} Valeur nettoyée.
 */
function cleanValue(value, fallback = "Non renseigné") {
  const result = (value || "").toString().trim();
  return result || fallback;
}

/**
 * Échappe une valeur avant son insertion dans un e-mail HTML.
 *
 * @param {*} value Valeur à sécuriser.
 * @return {string} Valeur échappée.
 */
function escapeHtml(value) {
  return (value || "")
      .toString()
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#039;");
}

/**
 * Construit la salutation administrative du demandeur.
 *
 * @param {Object} data Données de la demande.
 * @return {string} Salutation complète.
 */
function buildAdminGreeting(data) {
  const profile = data.profile || {};
  const proConnect = data.proConnect || {};

  const civilite = cleanValue(
      profile.civilite || data.civilite,
      "",
  );

  const nom = cleanValue(
      profile.nomAffiche ||
      data.nomResponsable ||
      proConnect.nom,
      "",
  ).toUpperCase();

  if (civilite && nom) {
    return `${civilite} ${nom} bonjour,`;
  }

  if (nom) {
    return `${nom} bonjour,`;
  }

  return "Bonjour,";
}

/**
 * Construit la salutation d'un demandeur annonceur.
 *
 * @param {Object} data Données de la demande.
 * @return {string} Salutation complète.
 */
function buildAdvertiserGreeting(data) {
  const civility = cleanValue(
      data.contactCivility || data.civilite,
      "",
  );
  const lastName = cleanValue(
      data.contactLastName || data.nomResponsable,
      "",
  ).toUpperCase();

  if (civility && lastName) {
    return `${civility} ${lastName} bonjour,`;
  }

  if (lastName) {
    return `${lastName} bonjour,`;
  }

  return "Bonjour,";
}

/**
 * Retourne la désignation complète de la structure.
 *
 * @param {Object} data Données de la demande.
 * @return {string} Désignation prête à être intégrée dans une phrase.
 */
function buildOrganisationDisplay(data) {
  const structure = data.structure || {};
  const proConnect = data.proConnect || {};

  return cleanValue(
      structure.organisationDisplay ||
      data.organisationDisplay ||
      structure.nom ||
      data.organisation ||
      proConnect.organisation,
      "votre structure",
  );
}

/**
 * Formate une date selon le format français.
 *
 * @param {Date} date Date à formater.
 * @return {string} Date et heure formatées.
 */
function formatFrenchDate(date) {
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

/**
 * Retourne le code ISO 3166-1 alpha-3 du pays de la demande.
 *
 * @param {Object} requestData Données de la demande.
 * @return {string} Code pays sur trois caractères.
 */
function resolveAdminCountryCode(requestData) {
  const territoire = requestData.territoire || {};
  const explicitCode = cleanValue(
      territoire.countryIso3 || requestData.countryIso3,
      "",
  ).toUpperCase();

  if (/^[A-Z]{3}$/.test(explicitCode)) {
    return explicitCode;
  }

  const countryName = cleanValue(
      territoire.pays || requestData.pays,
      "France",
  )
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase();

  if (countryName === "FRANCE" || countryName === "FR") {
    return "FRA";
  }

  return "XXX";
}

/**
 * Attribue un numéro séquentiel unique à une demande administrateur.
 *
 * Le numéro est généré une seule fois, même en cas de nouvelle exécution
 * de la fonction Cloud.
 *
 * @param {FirebaseFirestore.DocumentReference} requestReference
 * Référence Firestore de la demande.
 * @param {Date} date Date de création de la demande.
 * @return {Promise<string>} Numéro administratif de la demande.
 */
async function assignAdminRequestNumber(requestReference, date) {
  const db = admin.firestore();

  const year = Number(
      new Intl.DateTimeFormat("fr-FR", {
        timeZone: "Europe/Paris",
        year: "numeric",
      }).format(date),
  );

  const counterReference = db
      .collection("counters")
      .doc(`adminRequests_${year}`);

  return db.runTransaction(async (transaction) => {
    const requestSnapshot =
        await transaction.get(requestReference);

    const requestData = requestSnapshot.data() || {};
    const countryCode = resolveAdminCountryCode(requestData);

    const existingRequestNumber =
        (requestData.requestNumber || "").toString().trim();

    if (existingRequestNumber) {
      return existingRequestNumber;
    }

    const counterSnapshot =
        await transaction.get(counterReference);

    const counterData = counterSnapshot.data() || {};

    const currentNumber =
        Number(counterData.lastNumber || 0);

    const nextNumber = currentNumber + 1;

    const requestNumber =
        `SPHOT-ADM-${countryCode}-${year}-${nextNumber
            .toString()
            .padStart(6, "0")}`;

    transaction.set(
        counterReference,
        {
          year: year,
          lastNumber: nextNumber,
          updatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    transaction.set(
        requestReference,
        {
          requestNumber: requestNumber,
          requestCountryCode: countryCode,
          requestSequence: nextNumber,
          requestYear: year,
          updatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    return requestNumber;
  });
}

/**
 * Retourne l'année civile française d'un document commercial.
 *
 * @param {Object} data Données du document.
 * @param {string|undefined} eventTime Date de l'événement Cloud.
 * @return {number} Année utilisée dans le numéro commercial.
 */
function commercialDocumentYear(data, eventTime) {
  const candidates = [
    data.issueDate,
    data.createdAt,
  ];

  for (const value of candidates) {
    if (value && typeof value.toDate === "function") {
      return Number(
          new Intl.DateTimeFormat("fr-FR", {
            timeZone: "Europe/Paris",
            year: "numeric",
          }).format(value.toDate()),
      );
    }

    if (value instanceof Date && !Number.isNaN(value.getTime())) {
      return Number(
          new Intl.DateTimeFormat("fr-FR", {
            timeZone: "Europe/Paris",
            year: "numeric",
          }).format(value),
      );
    }
  }

  const fallbackDate = eventTime ? new Date(eventTime) : new Date();
  return Number(
      new Intl.DateTimeFormat("fr-FR", {
        timeZone: "Europe/Paris",
        year: "numeric",
      }).format(fallbackDate),
  );
}

/**
 * Extrait le numéro d'adhérent d'une référence Admin SPHOT.
 *
 * @param {string} administrativeReference Référence du dossier Admin.
 * @return {string} Numéro d'adhérent sur six chiffres ou chaîne vide.
 */
function adminMemberNumber(administrativeReference) {
  const match = cleanValue(administrativeReference, "").match(
      /^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-(\d{6})$/i,
  );
  return match ? match[1] : "";
}

/**
 * Construit l'identifiant du compteur d'un document commercial.
 *
 * @param {Object} definition Définition du type de document.
 * @param {number} year Année du document.
 * @param {string} memberNumber Numéro d'adhérent.
 * @return {string} Identifiant du compteur Firestore.
 */
function commercialCounterId(definition, year, memberNumber) {
  const suffix = definition.perMember ? `_${memberNumber}` : "";
  return `${definition.counterPrefix}_${year}${suffix}`;
}

/**
 * Construit le numéro métier d'un document commercial.
 *
 * @param {Object} definition Définition du type de document.
 * @param {number} year Année du document.
 * @param {string} memberNumber Numéro d'adhérent.
 * @param {number} sequence Séquence réservée.
 * @return {string} Numéro commercial définitif.
 */
function commercialDocumentNumber(
    definition,
    year,
    memberNumber,
    sequence,
) {
  const paddedSequence = sequence
      .toString()
      .padStart(definition.sequenceLength, "0");

  if (definition.perMember) {
    return `${definition.prefix}-${year}-${memberNumber}-${paddedSequence}`;
  }

  return `${definition.prefix}-${year}-${paddedSequence}`;
}

/**
 * Réserve atomiquement un numéro pour un document commercial.
 *
 * La fonction peut être rappelée sans consommer de nouveau numéro si le
 * document possède déjà son numéro métier.
 *
 * @param {Object} event Événement Firestore de seconde génération.
 * @param {Object} definition Définition du type de document.
 * @return {Promise<void>} Fin de l'attribution éventuelle.
 */
async function assignCommercialDocumentNumber(event, definition) {
  if (!event.data.after.exists) return;

  const documentReference = event.data.after.ref;
  const db = admin.firestore();

  await db.runTransaction(async (transaction) => {
    const documentSnapshot = await transaction.get(documentReference);
    if (!documentSnapshot.exists) return;

    const data = documentSnapshot.data() || {};
    const existingNumber = cleanValue(data[definition.numberField], "");
    if (existingNumber) return;

    const adminUid = cleanValue(data.adminUid, "");
    let administrativeReference = cleanValue(
        data.administrativeReference,
        "",
    );

    if (!administrativeReference && adminUid) {
      const requestReference = db.collection("adminRequests").doc(adminUid);
      const requestSnapshot = await transaction.get(requestReference);
      administrativeReference = cleanValue(
          (requestSnapshot.data() || {}).requestNumber,
          "",
      );
    }

    const memberNumber = adminMemberNumber(administrativeReference);
    if (!administrativeReference || !memberNumber) {
      console.warn(
          `Numérotation ${definition.label} différée : ` +
          "référence Admin absente ou invalide pour " +
          `${documentReference.path}.`,
      );
      return;
    }

    if (definition.originalNumberField &&
        !cleanValue(data[definition.originalNumberField], "")) {
      console.warn(
          `Numérotation ${definition.label} différée : ` +
          `facture d'origine absente pour ${documentReference.path}.`,
      );
      return;
    }

    const year = commercialDocumentYear(data, event.time);
    const counterId = commercialCounterId(
        definition,
        year,
        memberNumber,
    );
    const counterReference = db.collection("counters").doc(counterId);
    const counterSnapshot = await transaction.get(counterReference);
    const currentNumber = Number(
        (counterSnapshot.data() || {}).lastNumber || 0,
    );
    const nextNumber = currentNumber + 1;
    const documentNumber = commercialDocumentNumber(
        definition,
        year,
        memberNumber,
        nextNumber,
    );

    transaction.set(
        counterReference,
        {
          documentType: definition.documentType,
          year: year,
          perMember: definition.perMember,
          ...(definition.perMember ? {memberNumber: memberNumber} : {}),
          lastNumber: nextNumber,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    transaction.set(
        documentReference,
        {
          administrativeReference: administrativeReference,
          [definition.numberField]: documentNumber,
          year: year,
          sequence: nextNumber,
          numberedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
  });
}

const COMMERCIAL_DOCUMENTS = {
  quote: {
    label: "devis",
    documentType: "quote",
    numberField: "quoteNumber",
    counterPrefix: "quotes",
    prefix: "DV",
    perMember: true,
    sequenceLength: 3,
  },
  order: {
    label: "commande",
    documentType: "order",
    numberField: "orderNumber",
    counterPrefix: "orders",
    prefix: "CMD",
    perMember: true,
    sequenceLength: 3,
  },
  invoice: {
    label: "facture",
    documentType: "invoice",
    numberField: "invoiceNumber",
    counterPrefix: "invoices",
    prefix: "FA",
    perMember: false,
    sequenceLength: 6,
  },
  creditNote: {
    label: "avoir",
    documentType: "credit_note",
    numberField: "creditNoteNumber",
    originalNumberField: "originalInvoiceNumber",
    counterPrefix: "creditNotes",
    prefix: "AV",
    perMember: false,
    sequenceLength: 6,
  },
};

/**
 * Génère le PDF d'accusé de réception d'une demande administrateur.
 *
 * @param {Object} params Paramètres nécessaires à la génération du PDF.
 * @param {string} params.requestNumber Numéro de la demande.
 * @param {Date} params.createdAt Date de création de la demande.
 * @param {Object} params.profile Profil SPHOT du demandeur.
 * @param {Object} params.proConnect Identité transmise par ProConnect.
 * @param {Object} params.structure Informations concernant la structure.
 * @param {Object} params.territoire Informations concernant le territoire.
 * @param {Object} params.trialRequest Informations concernant l'essai.
 * @param {Object} params.subscriptionPreview Informations commerciales.
 * @return {Promise<Buffer>} Contenu du document PDF.
 */
/**
 * Génère le PDF d'accusé de réception d'une demande administrateur.
 *
 * @param {Object} params Paramètres nécessaires à la génération du PDF.
 * @param {string} params.requestNumber Numéro de la demande.
 * @param {Date} params.createdAt Date de création de la demande.
 * @param {Object} params.profile Profil SPHOT du demandeur.
 * @param {Object} params.proConnect Identité transmise par ProConnect.
 * @param {Object} params.structure Informations concernant la structure.
 * @param {Object} params.territoire Informations concernant le territoire.
 * @param {Object} params.trialRequest Informations concernant l'essai.
 * @return {Promise<Buffer>} Contenu du document PDF.
 */
function createAdminRequestPdf({
  requestNumber,
  documentNumber,
  createdAt,
  profile,
  proConnect,
  structure,
  territoire,
  trialRequest,
}) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: "A4",
        margins: {
          top: 30,
          bottom: 30,
          left: 40,
          right: 40,
        },
        info: {
          Title:
            "Accusé de réception de la demande d'accès administrateur",
          Author: "SPHOT",
          Subject: requestNumber,
        },
      });

      const chunks = [];
      doc.on("data", (chunk) => chunks.push(chunk));
      doc.on("end", () => resolve(Buffer.concat(chunks)));
      doc.on("error", reject);

      const blue = "#1E3A8A";
      const red = "#DC2626";
      const dark = "#263238";
      const grey = "#607D8B";
      const pale = "#F3F6FB";
      const paleWarm = "#FFF8E1";
      const white = "#FFFFFF";

      const left = doc.page.margins.left;
      const right = doc.page.width - doc.page.margins.right;
      const contentWidth = right - left;

      const safe = (value, fallback = "Non renseigné") =>
        cleanValue(value, fallback);

      const drawSectionTitle = (title) => {
        const y = doc.y + 3;
        doc
            .font("Helvetica-Bold")
            .fontSize(9)
            .fillColor(red)
            .text(title.toUpperCase(), left, y, {
              width: contentWidth,
            });
        doc
            .strokeColor(blue)
            .lineWidth(0.7)
            .moveTo(left, y + 14)
            .lineTo(right, y + 14)
            .stroke();
        doc.y = y + 21;
      };

      const drawInfoRow = (label, value, options = {}) => {
        const y = doc.y;
        const labelWidth = options.labelWidth || 104;
        doc
            .font("Helvetica-Bold")
            .fontSize(7.7)
            .fillColor(blue)
            .text(label, left + 10, y, {
              width: labelWidth,
            });
        doc
            .font("Helvetica")
            .fontSize(8)
            .fillColor(dark)
            .text(safe(value), left + 10 + labelWidth, y, {
              width: contentWidth - labelWidth - 20,
              ellipsis: true,
            });
        doc.y = y + 11.5;
      };

      const drawTwoColumnBox = ({
        titleLeft,
        rowsLeft,
        titleRight,
        rowsRight,
      }) => {
        const boxY = doc.y;
        const gap = 10;
        const boxWidth = (contentWidth - gap) / 2;
        const boxHeight = 112;

        for (const entry of [
          {x: left, title: titleLeft, rows: rowsLeft},
          {
            x: left + boxWidth + gap,
            title: titleRight,
            rows: rowsRight,
          },
        ]) {
          doc
              .roundedRect(entry.x, boxY, boxWidth, boxHeight, 10)
              .fillAndStroke(pale, "#D9E2EC");
          doc
              .font("Helvetica-Bold")
              .fontSize(8.5)
              .fillColor(red)
              .text(entry.title.toUpperCase(), entry.x + 12, boxY + 12, {
                width: boxWidth - 24,
              });

          let rowY = boxY + 31;
          for (const row of entry.rows) {
            const value = safe(row.value);
            doc
                .font("Helvetica-Bold")
                .fontSize(7.1)
                .fillColor(blue)
                .text(row.label, entry.x + 12, rowY, {
                  width: 78,
                });
            doc
                .font("Helvetica")
                .fontSize(7.3)
                .fillColor(dark)
                .text(value, entry.x + 92, rowY, {
                  width: boxWidth - 104,
                  ellipsis: true,
                });
            rowY += 13;
          }
        }

        doc.y = boxY + boxHeight + 10;
      };

      doc
          .roundedRect(left, 30, contentWidth, 72, 14)
          .fillAndStroke(white, "#D9E2EC");

      doc
          .font("Helvetica-Bold")
          .fontSize(25)
          .fillColor(red)
          .text("SPHOT", left + 18, 43, {
            width: 120,
          });

      doc
          .font("Helvetica")
          .fontSize(7.2)
          .fillColor(grey)
          .text(
              "Des plages plus sûres, propres et connectées",
              left + 18,
              73,
              {width: 200},
          );

      doc
          .font("Helvetica-Bold")
          .fontSize(8)
          .fillColor(blue)
          .text(
              "SURVEILLER  •  PRÉSERVER  •  INFORMER  •  ENSEMBLE",
              left + 222,
              56,
              {
                width: contentWidth - 240,
                align: "right",
              },
          );

      doc.y = 116;

      doc
          .font("Helvetica-Bold")
          .fontSize(13)
          .fillColor(blue)
          .text(
              "ACCUSÉ DE RÉCEPTION DE LA DEMANDE D'ACCÈS " +
              "ADMINISTRATEUR",
              {
                align: "center",
                width: contentWidth,
                lineGap: 1,
              },
          );

      doc.moveDown(0.35);

      const referenceY = doc.y;
      doc
          .roundedRect(left, referenceY, contentWidth, 72, 12)
          .fillAndStroke(pale, blue);

      doc
          .font("Helvetica-Bold")
          .fontSize(7.2)
          .fillColor(grey)
          .text("RÉFÉRENCE DU DOCUMENT", left + 14, referenceY + 11);

      doc
          .font("Helvetica-Bold")
          .fontSize(10.6)
          .fillColor(red)
          .text(documentNumber, left + 14, referenceY + 26, {
            width: 325,
          });

      doc
          .font("Helvetica")
          .fontSize(7)
          .fillColor(grey)
          .text(
              `Dossier : ${requestNumber}`,
              left + 14,
              referenceY + 47,
          );

      doc
          .font("Helvetica")
          .fontSize(7)
          .fillColor(grey)
          .text(
              `Émis le ${formatFrenchDate(createdAt)}`,
              left + 14,
              referenceY + 60,
          );

      doc
          .font("Helvetica-Bold")
          .fontSize(7.1)
          .fillColor(blue)
          .text("RUBRIQUE", right - 138, referenceY + 11, {
            width: 120,
            align: "right",
          });

      doc
          .font("Helvetica-Bold")
          .fontSize(8.4)
          .fillColor(dark)
          .text("DEMANDE D'ACCÈS", right - 138, referenceY + 27, {
            width: 120,
            align: "right",
          });

      doc
          .font("Helvetica-Bold")
          .fontSize(7.1)
          .fillColor(blue)
          .text("STATUT", right - 138, referenceY + 49, {
            width: 120,
            align: "right",
          });

      doc
          .font("Helvetica-Bold")
          .fontSize(8.2)
          .fillColor(dark)
          .text("ÉMIS", right - 138, referenceY + 62, {
            width: 120,
            align: "right",
          });

      doc.y = referenceY + 84;

      drawTwoColumnBox({
        titleLeft: "Demandeur",
        rowsLeft: [
          {label: "Nom", value: profile.nomAffiche},
          {label: "Prénom", value: profile.prenomAffiche},
          {label: "Fonction", value: profile.fonction},
          {label: "Email", value: profile.email},
          {label: "Téléphone", value: profile.telephone},
        ],
        titleRight: "Structure et territoire",
        rowsRight: [
          {label: "Structure", value: structure.nom},
          {label: "Type", value: structure.type},
          {label: "SIRET", value: structure.siret},
          {label: "Commune", value: territoire.ville},
          {label: "Département", value: territoire.departement},
        ],
      });

      const proConnectValues = [
        proConnect.nom,
        proConnect.prenom,
        proConnect.email,
        proConnect.organisation,
        proConnect.siret,
        proConnect.siren,
      ].map((value) => cleanValue(value));

      if (proConnectValues.some((value) => value)) {
        drawSectionTitle("Identité certifiée transmise par ProConnect");
        drawInfoRow(
            "Identité",
            [proConnect.prenom, proConnect.nom]
                .map((value) => cleanValue(value))
                .filter(Boolean)
                .join(" "),
        );
        drawInfoRow("Email", proConnect.email);
        drawInfoRow("Organisation", proConnect.organisation);
        drawInfoRow(
            "SIRET / SIREN",
            [
              cleanValue(proConnect.siret),
              cleanValue(proConnect.siren),
            ].filter(Boolean).join(" / "),
        );
        doc.moveDown(0.2);
      }

      drawSectionTitle("Objet du document");

      doc
          .font("Helvetica")
          .fontSize(8.3)
          .fillColor(dark)
          .text(
              "Votre demande d'accès au portail d'administration SPHOT " +
              "a bien été enregistrée. Elle va maintenant faire l'objet " +
              "d'une instruction par l'équipe SPHOT. Une décision " +
              "distincte vous sera communiquée à l'issue de cette " +
              "instruction.",
              left + 10,
              doc.y,
              {
                width: contentWidth - 20,
                lineGap: 1.2,
              },
          );

      doc.moveDown(0.45);
      drawSectionTitle("Consentements enregistrés");

      const acceptedDocuments = trialRequest.acceptedDocuments || {};
      const consentY = doc.y;
      const consentRows = [
        [
          "Habilitation",
          trialRequest.certifyRepresentative === true ? "Oui" : "Non",
        ],
        [
          "CGU",
          acceptedDocuments.cgu === true ? "Acceptées" : "Non acceptées",
        ],
        [
          "Confidentialité",
          acceptedDocuments.privacy === true ?
            "Acceptée" :
            "Non acceptée",
        ],
        [
          "Données personnelles",
          acceptedDocuments.rgpd === true ? "Accepté" : "Non accepté",
        ],
      ];

      const consentColumnWidth = contentWidth / 2;
      for (let index = 0; index < consentRows.length; index++) {
        const column = index % 2;
        const row = Math.floor(index / 2);
        const x = left + (column * consentColumnWidth) + 10;
        const y = consentY + (row * 18);

        doc
            .font("Helvetica-Bold")
            .fontSize(7.3)
            .fillColor(blue)
            .text(consentRows[index][0], x, y, {width: 92});

        doc
            .font("Helvetica")
            .fontSize(7.5)
            .fillColor(dark)
            .text(
                consentRows[index][1],
                x + 94,
                y,
                {width: consentColumnWidth - 112},
            );
      }

      doc.y = consentY + 41;

      const warningY = doc.y + 5;
      doc
          .roundedRect(left, warningY, contentWidth, 63, 10)
          .fillAndStroke(paleWarm, "#F59E0B");

      doc
          .font("Helvetica-Bold")
          .fontSize(8.2)
          .fillColor(red)
          .text("INFORMATION IMPORTANTE", left + 13, warningY + 11);

      doc
          .font("Helvetica")
          .fontSize(7.8)
          .fillColor(dark)
          .text(
              "Le présent document atteste uniquement de la réception " +
              "de votre demande. Il ne constitue ni une décision " +
              "d'approbation, ni une autorisation d'accès au portail " +
              "SPHOT. La période d'essai, l'abonnement et la facturation " +
              "font l'objet d'étapes et de documents distincts.",
              left + 13,
              warningY + 27,
              {
                width: contentWidth - 26,
                lineGap: 1,
              },
          );

      const signatureY = warningY + 76;
      doc
          .font("Helvetica")
          .fontSize(8.2)
          .fillColor(dark)
          .text("À bientôt sur SPHOT,", left, signatureY, {
            width: contentWidth,
            align: "right",
          });

      doc
          .font("Helvetica-Bold")
          .fontSize(8.5)
          .fillColor(blue)
          .text("L'équipe SPHOT", left, signatureY + 13, {
            width: contentWidth,
            align: "right",
          });

      const footerY = doc.page.height - 54;
      doc
          .strokeColor("#D9E2EC")
          .lineWidth(0.7)
          .moveTo(left, footerY)
          .lineTo(right, footerY)
          .stroke();

      doc
          .font("Helvetica")
          .fontSize(6.6)
          .fillColor(grey)
          .text(
              "Document généré automatiquement par SPHOT",
              left,
              footerY + 10,
              {width: 220},
          );

      doc
          .font("Helvetica")
          .fontSize(6.6)
          .fillColor(grey)
          .text(
              `${documentNumber}  •  Version 01  •  Page 1 / 1`,
              left + 210,
              footerY + 10,
              {
                width: contentWidth - 210,
                align: "right",
              },
          );

      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}

/**
 * Envoie l'email standard de confirmation d'une demande d'accès Admin.
 *
 * Utilisé aussi bien lors de la première demande que lors d'un renvoi
 * après correction.
 *
 * @param {Object} data Données de la demande.
 * @param {string} recipientEmail Adresse du destinataire.
 * @param {string} requestNumber Référence administrative.
 * @return {Promise<Object>} Résultat Nodemailer.
 */
async function sendAdminAccessAcknowledgementEmail(
    data,
    recipientEmail,
    requestNumber,
) {
  const greeting = buildAdminGreeting(data);
  const organisation = buildOrganisationDisplay(data);

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: SMTP_USER,
      pass: process.env.GMAIL_APP_PASSWORD,
    },
  });

  return sendSphotMail(transporter, {
    from: MAIL_FROM,
    to: recipientEmail,
    subject:
        "SPHOT - Confirmation de votre demande d'accès administrateur",

    html: `
<p style="font-size:16px;line-height:1.6;">
  ${escapeHtml(greeting)}
</p>

<p style="font-size:16px;line-height:1.6;">
  Votre demande d'accès administrateur à la plateforme
  <strong>SPHOT</strong> pour
  <strong>${escapeHtml(organisation)}</strong>
  a bien été enregistrée.
</p>

<div style="
  margin:26px 0;
  padding:20px;
  background:#f3f6fb;
  border:1px solid #1e3a8a;
  border-radius:14px;
">
  <div style="
    color:#607d8b;
    font-size:12px;
    font-weight:bold;
    text-transform:uppercase;
  ">
    Référence du dossier
  </div>

  <div style="
    margin-top:5px;
    color:#dc2626;
    font-size:21px;
    font-weight:bold;
  ">
    ${escapeHtml(requestNumber)}
  </div>
</div>

<p style="font-size:16px;line-height:1.6;">
  Votre demande va maintenant faire l'objet d'une instruction
  par l'équipe SPHOT. Une décision distincte vous sera communiquée
  à l'issue de cette instruction.
</p>

<div style="
  margin-top:28px;
  padding:16px;
  background:#fff8e1;
  border-left:5px solid #ff9800;
  border-radius:8px;
  font-size:14px;
  line-height:1.6;
">
  Ce message confirme uniquement la bonne réception de votre demande.
  Il ne constitue ni une décision d'approbation, ni une autorisation
  d'accès au portail SPHOT. La période d'essai, l'abonnement et la
  facturation font l'objet d'étapes distinctes.
</div>

<p style="margin-top:34px;font-size:15px;line-height:1.6;">
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>
`,

    text:
`${greeting}

Votre demande d'accès administrateur à la plateforme SPHOT
pour ${organisation} a bien été enregistrée.

Référence du dossier : ${requestNumber}

Votre demande va maintenant faire l'objet d'une instruction par l'équipe SPHOT.
Une décision distincte vous sera communiquée à l'issue de cette instruction.

Ce message confirme uniquement la bonne réception de votre demande.
Il ne constitue ni une décision d'approbation, ni une autorisation d'accès
au portail SPHOT. La période d'essai, l'abonnement et la facturation font
l'objet d'étapes distinctes.

À bientôt sur SPHOT,

L'équipe SPHOT`,

  });
}

exports.generateAdminRequestAcknowledgement = onDocumentCreated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "512MiB",
    },
    async (event) => {
      const requestSnapshot = event.data;

      if (!requestSnapshot) {
        console.error("Document adminRequests introuvable.");
        return;
      }

      const requestReference = requestSnapshot.ref;
      const data = requestSnapshot.data() || {};
      const requestId = event.params.requestId;

      const existingDocument = data.acknowledgementDocument || {};

      if (
        existingDocument.status === "generated" ||
        existingDocument.status === "sent"
      ) {
        console.log(
            "Accusé de réception déjà généré pour:",
            requestId,
        );
        return;
      }

      const profile = data.profile || {};
      const proConnect = data.proConnect || {};
      const structure = data.structure || {};
      const territoire = data.territoire || {};
      const trialRequest = data.trialRequest || {};
      const subscriptionPreview = data.subscriptionPreview || {};

      const recipientEmail = cleanValue(
          profile.email || proConnect.email,
          "",
      );

      if (!recipientEmail) {
        await requestReference.set(
            {
              acknowledgementDocument: {
                status: "failed",
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
              acknowledgementEmail: {
                status: "failed",
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        console.error(
            "Adresse email absente pour la demande:",
            requestId,
        );

        return;
      }

      const createdAt =
          data.requestedAt &&
          typeof data.requestedAt.toDate === "function" ?
            data.requestedAt.toDate() :
            new Date();

      const requestNumber =
    data.requestNumber ||
    await assignAdminRequestNumber(
        requestReference,
        createdAt,
    );

      const documentNumber = `${requestNumber}-INS-AR-01`;
      const documentYear = Number(
          data.requestYear ||
          new Intl.DateTimeFormat("fr-FR", {
            timeZone: "Europe/Paris",
            year: "numeric",
          }).format(createdAt),
      );
      const fileName = `${documentNumber}.pdf`;

      const storagePath =
          `adminRequests/${requestId}/documents/administratif/` +
          `${documentYear}/inscription/${fileName}`;

      await requestReference.set(
          {
            requestNumber: requestNumber,

            acknowledgementDocument: {
              status: "generating",
              documentType: "admin_request_acknowledgement",
              fileName: fileName,
              storagePath: storagePath,
              version: "1.0",
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },

            acknowledgementEmail: {
              status: "pending",
              recipient: recipientEmail,
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          {merge: true},
      );

      try {
        const pdfBuffer = await createAdminRequestPdf({
          requestNumber: requestNumber,
          documentNumber: documentNumber,
          createdAt: createdAt,
          profile: profile,
          proConnect: proConnect,
          structure: structure,
          territoire: territoire,
          trialRequest: trialRequest,
          subscriptionPreview: subscriptionPreview,
        });

        const bucket = admin.storage().bucket();
        const file = bucket.file(storagePath);

        await file.save(pdfBuffer, {
          contentType: "application/pdf",
          resumable: false,
          metadata: {
            contentDisposition:
                `attachment; filename="${fileName}"`,
            metadata: {
              requestId: requestId,
              requestNumber: requestNumber,
              documentType: "admin_request_acknowledgement",
            },
          },
        });

        const downloadUrl = await getDownloadURL(file);

        const registryId = cleanValue(
            `${requestId}_${documentNumber}`,
        )
            .replace(/[^A-Za-z0-9_-]/g, "_")
            .replace(/_+/g, "_")
            .slice(0, 700);

        await admin.firestore().collection("documents").doc(registryId).set(
            {
              requestId: requestId,
              adminUid: cleanValue(data.uid || requestId),
              dossierNumber: requestNumber,
              documentNumber: documentNumber,
              documentType: "registration_acknowledgement",
              category: "administrative",
              subcategory: "inscription",
              year: documentYear,
              version: 1,
              title:
                  "Accusé de réception de la demande d'accès " +
                  "administrateur",
              status: "issued",
              storagePath: storagePath,
              downloadUrl: downloadUrl,
              issuedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
              createdAt:
                  admin.firestore.FieldValue.serverTimestamp(),
              createdByRole: "system",
            },
            {merge: true},
        );

        const mailResult = await sendAdminAccessAcknowledgementEmail(
            data,
            recipientEmail,
            requestNumber,
        );

        await requestReference.set(
            {
              requestNumber: requestNumber,

              acknowledgementDocument: {
                status: "generated",
                documentType: "admin_request_acknowledgement",
                fileName: fileName,
                storagePath: storagePath,
                downloadUrl: downloadUrl,
                version: "1.0",
                documentNumber: documentNumber,
                category: "administrative",
                subcategory: "inscription",
                generatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                generatedBy: "system",
              },

              acknowledgementEmail: {
                status: "sent",
                recipient: recipientEmail,
                messageId: mailResult.messageId || null,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                error: null,
              },

              lastEvent: {
                type: "request_acknowledgement_sent",
                category: "administrative",
                label:
                    "Confirmation envoyée sans PDF joint ; document archivé",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Confirmation envoyée sans PDF joint ; document archivé:",
            requestNumber,
            recipientEmail,
        );
      } catch (error) {
        console.error(
            "Erreur génération ou envoi accusé de réception:",
            error,
        );

        await requestReference.set(
            {
              acknowledgementDocument: {
                status: "failed",
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              acknowledgementEmail: {
                status: "failed",
                recipient: recipientEmail,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "request_acknowledgement_failed",
                category: "administrative",
                label:
                    "Échec de génération ou d'envoi de l'accusé de réception",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      }
    },
);

/**
 * Renvoie l'email standard de confirmation lorsque l'administrateur
 * renvoie son dossier après une demande de correction.
 */
exports.sendAdminRequestResubmissionAcknowledgement = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const beforeData = event.data.before.data() || {};
      const afterData = event.data.after.data() || {};

      const beforeCount = Number(
          beforeData.resubmissionCount || 0,
      );

      const afterCount = Number(
          afterData.resubmissionCount || 0,
      );

      // Aucun nouveau renvoi après correction.
      if (afterCount <= beforeCount) {
        return;
      }

      const requestReference = event.data.after.ref;

      /*
       * Protection contre les doubles envois en cas de nouvelle
       * exécution automatique de la Cloud Function.
       */
      const claimed = await admin.firestore().runTransaction(
          async (transaction) => {
            const freshSnapshot =
                await transaction.get(requestReference);

            const freshData = freshSnapshot.data() || {};

            const freshCount = Number(
                freshData.resubmissionCount || 0,
            );

            const acknowledgementEmail =
                freshData.acknowledgementEmail || {};

            const lastAcknowledgedCount = Number(
                acknowledgementEmail.resubmissionCount || 0,
            );

            if (freshCount <= lastAcknowledgedCount) {
              return false;
            }

            transaction.set(
                requestReference,
                {
                  acknowledgementEmail: {
                    ...acknowledgementEmail,
                    status: "sending",
                    resubmissionCount: freshCount,
                    sentAt: null,
                    messageId: null,
                    error: null,
                    updatedAt:
                        admin.firestore.FieldValue.serverTimestamp(),
                  },
                },
                {merge: true},
            );

            return true;
          },
      );

      if (!claimed) {
        return;
      }

      const profile = afterData.profile || {};
      const proConnect = afterData.proConnect || {};

      const recipientEmail = cleanValue(
          profile.email || proConnect.email,
          "",
      ).toLowerCase();

      const requestNumber = cleanValue(
          afterData.requestNumber || event.params.requestId,
          event.params.requestId,
      );

      if (!recipientEmail) {
        await requestReference.set(
            {
              acknowledgementEmail: {
                status: "failed",
                resubmissionCount: afterCount,
                sentAt: null,
                messageId: null,
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        return;
      }

      try {
        const mailResult =
            await sendAdminAccessAcknowledgementEmail(
                afterData,
                recipientEmail,
                requestNumber,
            );

        await requestReference.set(
            {
              acknowledgementEmail: {
                status: "sent",
                recipient: recipientEmail,
                resubmissionCount: afterCount,
                messageId: mailResult.messageId || null,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                error: null,
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_request_resubmission_acknowledgement_sent",
                category: "administrative",
                label:
                    "Confirmation de renvoi de la demande envoyée",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      } catch (error) {
        await requestReference.set(
            {
              acknowledgementEmail: {
                status: "failed",
                recipient: recipientEmail,
                resubmissionCount: afterCount,
                sentAt: null,
                messageId: null,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        throw error;
      }
    },
);

/**
 * Génère un mot de passe provisoire conforme aux règles SPHOT :
 * - au moins une majuscule ;
 * - au moins un chiffre ;
 * - au moins un caractère spécial autorisé.
 *
 * @return {string} Mot de passe provisoire.
 */
function generateAdminTemporaryPassword() {
  const upperCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lowerCharacters = "abcdefghijkmnopqrstuvwxyz";
  const numberCharacters = "23456789";
  const specialCharacters = "!@#?*-";

  const allCharacters =
      upperCharacters +
      lowerCharacters +
      numberCharacters +
      specialCharacters;

  const randomCharacter = (characters) => {
    const index = Math.floor(Math.random() * characters.length);
    return characters[index];
  };

  const passwordCharacters = [
    randomCharacter(upperCharacters),
    randomCharacter(lowerCharacters),
    randomCharacter(numberCharacters),
    randomCharacter(specialCharacters),
  ];

  while (passwordCharacters.length < 12) {
    passwordCharacters.push(randomCharacter(allCharacters));
  }

  for (let index = passwordCharacters.length - 1; index > 0; index--) {
    const randomIndex = Math.floor(Math.random() * (index + 1));

    const temporaryValue = passwordCharacters[index];
    passwordCharacters[index] = passwordCharacters[randomIndex];
    passwordCharacters[randomIndex] = temporaryValue;
  }

  return passwordCharacters.join("");
}

/**
 * Crée le compte administrateur et envoie le mail d'acceptation.
 *
 * Le mail est envoyé une seule fois lorsque approvalEmail.status
 * passe à "pending" sur une demande approuvée.
 */
exports.sendAdminRequestApprovalEmail = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const beforeSnapshot = event.data.before;
      const afterSnapshot = event.data.after;

      if (!afterSnapshot.exists) {
        return;
      }

      const beforeData = beforeSnapshot.data() || {};
      const afterData = afterSnapshot.data() || {};

      const beforeApprovalEmail =
          beforeData.approvalEmail || {};

      const afterApprovalEmail =
          afterData.approvalEmail || {};

      const requestStatus = cleanValue(
          afterData.status,
          "",
      ).toLowerCase();

      const previousEmailStatus = cleanValue(
          beforeApprovalEmail.status,
          "",
      ).toLowerCase();

      const currentEmailStatus = cleanValue(
          afterApprovalEmail.status,
          "",
      ).toLowerCase();

      if (requestStatus !== "approved") {
        return;
      }

      if (currentEmailStatus !== "pending") {
        return;
      }

      if (
        previousEmailStatus === "sending" ||
        previousEmailStatus === "sent"
      ) {
        return;
      }

      const requestReference = afterSnapshot.ref;

      const profile = afterData.profile || {};
      const proConnect = afterData.proConnect || {};
      const territoire = afterData.territoire || {};

      const email = cleanValue(
          afterApprovalEmail.recipient ||
          profile.email ||
          proConnect.email,
          "",
      ).toLowerCase();

      if (!email) {
        await requestReference.set(
            {
              approvalEmail: {
                ...afterApprovalEmail,
                status: "failed",
                sentAt: null,
                messageId: null,
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        return;
      }

      const transactionStarted =
          await admin.firestore().runTransaction(
              async (transaction) => {
                const freshSnapshot =
                    await transaction.get(requestReference);

                const freshData =
                    freshSnapshot.data() || {};

                const freshApprovalEmail =
                    freshData.approvalEmail || {};

                const freshStatus = cleanValue(
                    freshApprovalEmail.status,
                    "",
                ).toLowerCase();

                if (freshStatus !== "pending") {
                  return false;
                }

                transaction.set(
                    requestReference,
                    {
                      approvalEmail: {
                        ...freshApprovalEmail,
                        status: "sending",
                        sentAt: null,
                        messageId: null,
                        error: null,
                        updatedAt:
                            admin.firestore.FieldValue
                                .serverTimestamp(),
                      },
                    },
                    {merge: true},
                );

                return true;
              },
          );

      if (!transactionStarted) {
        return;
      }

      const greeting = buildAdminGreeting(afterData);
      const organisation = buildOrganisationDisplay(afterData);

      const requestNumber = cleanValue(
          afterData.requestNumber ||
          event.params.requestId,
          event.params.requestId,
      );

      /*
       * L'adresse email devient l'identifiant de connexion.
       * ProfessionalLoginPage affiche déjà "Adresse email".
       */
      const login = email;

      /*
       * On conserve les identifiants déjà créés si la fonction
       * est relancée, afin de ne pas modifier le mot de passe
       * après un premier envoi réussi ou partiel.
       */
      const accountReference = admin.firestore()
          .collection("adminAccounts")
          .doc(login);

      const existingAccountSnapshot =
          await accountReference.get();

      const existingAccountData =
          existingAccountSnapshot.data() || {};

      const existingPassword = cleanValue(
          existingAccountData.temporaryPassword,
          "",
      );

      const temporaryPassword = existingPassword ?
    existingPassword :
    generateAdminTemporaryPassword();

      const nom = cleanValue(
          profile.nomAffiche ||
          afterData.nomResponsable ||
          proConnect.nom,
          "",
      ).toUpperCase();

      const prenom = cleanValue(
          profile.prenomAffiche ||
          afterData.prenomResponsable ||
          proConnect.prenom,
          "",
      );

      const territoireId = cleanValue(
          afterData.territoireId ||
          territoire.territoireId ||
          territoire.id,
          "",
      );

      const adminUid = cleanValue(
          afterData.uid ||
          afterData.adminUid ||
          event.params.requestId,
          event.params.requestId,
      );

      await accountReference.set(
          {
            login: login,
            email: email,
            temporaryPassword: temporaryPassword,
            mustChangePassword:
                existingAccountData.mustChangePassword == false ?
                    false :
                    true,
            accountStatus: "ACTIVE",
            role: "ADMIN",
            adminUid: adminUid,
            territoireId: territoireId,
            nom: nom,
            prenom: prenom,
            organisation: organisation,
            requestId: event.params.requestId,
            requestNumber: requestNumber,
            createdAt:
                existingAccountSnapshot.exists ?
                    existingAccountData.createdAt :
                    admin.firestore.FieldValue.serverTimestamp(),
            updatedAt:
                admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );

      /*
       * Le lien ne doit plus ouvrir directement le dashboard.
       * Il ouvre désormais la page de connexion professionnelle.
       */
      const loginUrl =
          `${SPHOT_LOGIN_URL}/#/professional-login`;

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      try {
        const mailResult = await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: email,
          subject:
              "SPHOT - Votre demande d'accès administrateur a été acceptée",

          text:
`${greeting}

Votre demande d'accès à votre SPHOT ADMIN
pour ${organisation} a été acceptée.

Référence administrative : ${requestNumber}

VOS IDENTIFIANTS DE CONNEXION

Identifiant :
${login}

Mot de passe provisoire :
${temporaryPassword}

Lors de votre première connexion, vous devrez obligatoirement
choisir un nouveau mot de passe.

SE CONNECTER À VOTRE SPHOT ADMIN :
${loginUrl}

Vous pourrez ensuite renseigner vos SPHOTS, vos sauveteurs
et vos périodes de surveillance.

Essai gratuit, sans engagement ni facturation.

La période d'essai de 8 jours ne commencera qu'une fois la
configuration complète et l'essai activé.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          html: `
<p style="font-size:16px;line-height:1.6;">
      ${escapeHtml(greeting)}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Votre demande d'accès à votre SPHOT ADMIN
      pour <strong>${escapeHtml(organisation)}</strong>
      a été acceptée.
    </p>

    <div style="
      margin:24px 0;
      padding:16px 18px;
      border:1.5px solid #1e3a8a;
      border-radius:14px;
      background:#f5f7fc;
    ">
      <div style="
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Référence administrative
      </div>

      <div style="
        margin-top:7px;
        color:#dc2626;
        font-size:19px;
        font-weight:900;
      ">
        ${escapeHtml(requestNumber)}
      </div>
    </div>

    <div style="
      margin:26px 0;
      padding:22px;
      border:2px solid #1e3a8a;
      border-radius:14px;
      background:#f3f6fb;
    ">
      <div style="
        margin-bottom:18px;
        color:#1e3a8a;
        font-size:17px;
        font-weight:900;
        text-align:center;
        text-transform:uppercase;
      ">
        Vos identifiants de connexion
      </div>

      <div style="
        margin-bottom:8px;
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Identifiant
      </div>

      <div style="
        padding:12px 14px;
        background:#ffffff;
        border:1px solid #c8d3e3;
        border-radius:9px;
        color:#1e3a8a;
        font-size:16px;
        font-weight:900;
        word-break:break-all;
      ">
        ${escapeHtml(login)}
      </div>

      <div style="
        margin-top:18px;
        margin-bottom:8px;
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Mot de passe provisoire
      </div>

      <div style="
        padding:12px 14px;
        background:#ffffff;
        border:1px solid #c8d3e3;
        border-radius:9px;
        color:#dc2626;
        font-size:18px;
        font-weight:900;
        letter-spacing:1px;
        word-break:break-all;
      ">
        ${escapeHtml(temporaryPassword)}
      </div>
    </div>

    <div style="
      margin:20px 0;
      padding:16px;
      border-left:4px solid #f59e0b;
      border-radius:8px;
      background:#fff7df;
      font-size:14px;
      line-height:1.6;
    ">
      Lors de votre première connexion, vous devrez obligatoirement
      choisir un nouveau mot de passe.
    </div>

    <div style="text-align:center;margin:30px 0;">
      <a
        href="${loginUrl}"
        style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
"
      >
        SE CONNECTER À VOTRE SPHOT ADMIN
      </a>
    </div>

    <p style="font-size:16px;line-height:1.6;">
      Vous pourrez ensuite renseigner vos SPHOTS, vos sauveteurs
      et vos périodes de surveillance.
    </p>

    <p style="
      color:#dc2626;
      font-size:16px;
      line-height:1.6;
      font-weight:900;
    ">
      Essai gratuit, sans engagement ni facturation.
    </p>

    <div style="
      margin-top:20px;
      padding:16px;
      border-left:4px solid #f59e0b;
      border-radius:8px;
      background:#fff7df;
      font-size:14px;
      line-height:1.6;
    ">
      La période d'essai de 8 jours ne commencera qu'une fois
      vos SPHOTS, vos sauveteurs et vos périodes de surveillance
      renseignés, puis l'essai activé.
    </div>

    <p style="margin-top:28px;font-size:15px;line-height:1.6;">
      À bientôt sur SPHOT,<br>
      <strong>L'équipe SPHOT</strong>
    </p>
`,

        });

        await requestReference.set(
            {
              adminAccount: {
                login: login,
                accountStatus: "ACTIVE",
                mustChangePassword:
                    existingAccountData.mustChangePassword == false ?
                        false :
                        true,
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              approvalEmail: {
                ...afterApprovalEmail,
                status: "sent",
                recipient: email,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                messageId: mailResult.messageId || null,
                error: null,
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_approval_email_sent",
                category: "administrative",
                label:
                    "Compte administrateur créé et identifiants envoyés",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Compte administrateur créé et identifiants envoyés :",
            login,
            requestNumber,
        );
      } catch (error) {
        console.error(
            "Erreur création compte ou envoi email administrateur :",
            error,
        );

        await requestReference.set(
            {
              approvalEmail: {
                ...afterApprovalEmail,
                status: "failed",
                recipient: email,
                sentAt: null,
                messageId: null,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_approval_email_failed",
                category: "administrative",
                label:
                    "Échec de création du compte ou d'envoi des identifiants",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        throw error;
      }
    },
);

/**
 * Envoie le mail de refus d'une demande administrateur SPHOT.
 *
 * Le mail contient le motif du refus et un lien permettant
 * au demandeur de corriger la demande existante.
 */
exports.sendAdminRequestRejectionEmail = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const beforeSnapshot = event.data.before;
      const afterSnapshot = event.data.after;

      if (!afterSnapshot.exists) {
        return;
      }

      const beforeData = beforeSnapshot.data() || {};
      const afterData = afterSnapshot.data() || {};

      const beforeRejectionEmail =
          beforeData.rejectionEmail || {};

      const afterRejectionEmail =
          afterData.rejectionEmail || {};

      const requestStatus = cleanValue(
          afterData.status,
          "",
      ).toLowerCase();

      const previousEmailStatus = cleanValue(
          beforeRejectionEmail.status,
          "",
      ).toLowerCase();

      const currentEmailStatus = cleanValue(
          afterRejectionEmail.status,
          "",
      ).toLowerCase();

      if (requestStatus !== "rejected") {
        return;
      }

      if (currentEmailStatus !== "pending") {
        return;
      }

      if (previousEmailStatus === "sending" ||
          previousEmailStatus === "sent") {
        return;
      }

      const requestReference = afterSnapshot.ref;

      const email = cleanValue(
          afterRejectionEmail.recipient ||
          (afterData.profile && afterData.profile.email) ||
          (afterData.proConnect && afterData.proConnect.email),
          "",
      );

      if (!email) {
        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "failed",
                sentAt: null,
                messageId: null,
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        return;
      }

      const transactionStarted =
          await admin.firestore().runTransaction(
              async (transaction) => {
                const freshSnapshot =
                    await transaction.get(requestReference);

                const freshData =
                    freshSnapshot.data() || {};

                const freshRejectionEmail =
                    freshData.rejectionEmail || {};

                const freshStatus = cleanValue(
                    freshRejectionEmail.status,
                    "",
                ).toLowerCase();

                if (freshStatus !== "pending") {
                  return false;
                }

                transaction.set(
                    requestReference,
                    {
                      rejectionEmail: {
                        ...freshRejectionEmail,
                        status: "sending",
                        sentAt: null,
                        messageId: null,
                        error: null,
                        updatedAt:
                            admin.firestore.FieldValue
                                .serverTimestamp(),
                      },
                    },
                    {merge: true},
                );

                return true;
              },
          );

      if (!transactionStarted) {
        return;
      }

      const administrativeTracking =
    afterData.administrativeTracking || {};

      const greeting =
    buildAdminGreeting(afterData);

      const organisation =
    buildOrganisationDisplay(afterData);

      const requestNumber = cleanValue(
          afterData.requestNumber ||
          event.params.requestId,
          event.params.requestId,
      );

      const rejectionReason = cleanValue(
          administrativeTracking.rejectionReason,
          "Des informations doivent être corrigées.",
      );

      const rejectionReasonHtml = escapeHtml(rejectionReason)
          .replace(/\r\n|\r|\n/g, "<br>");

      const correctionUrl =
          `${SPHOT_LOGIN_URL}/#/admin-request-correction` +
          `?requestId=${encodeURIComponent(event.params.requestId)}`;

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      try {
        const mailResult = await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: email,
          subject:
              "SPHOT - Votre demande d'accès administrateur doit être corrigée",

          text:
`${greeting}

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} ne peut pas être validée en l'état.

Référence administrative : ${requestNumber}

Motif :
${rejectionReason}

Vous ne devez pas créer une nouvelle demande.

Utilisez le lien suivant pour corriger les informations
de votre demande existante :

${correctionUrl}

Après validation de vos corrections, votre demande sera
automatiquement remise en attente d'instruction.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          html: `
<p style="font-size:16px;line-height:1.6;">
      ${greeting}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Votre demande d'accès au portail d'administration SPHOT
      pour <strong>${organisation}</strong> ne peut pas être
      validée en l'état.
    </p>

    <div style="
      margin:24px 0;
      padding:16px 18px;
      border:1.5px solid #1e3a8a;
      border-radius:14px;
      background:#f5f7fc;
    ">
      <div style="
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Référence administrative
      </div>

      <div style="
        margin-top:7px;
        color:#dc2626;
        font-size:19px;
        font-weight:900;
      ">
        ${requestNumber}
      </div>
    </div>

    <div style="
      margin:24px 0;
      padding:18px;
      background:#fff1f1;
      border-left:5px solid #dc2626;
      border-radius:8px;
      font-size:15px;
      line-height:1.6;
    ">
      <strong>Motif :</strong><br><br>
      ${rejectionReasonHtml}
    </div>

    <p style="font-size:16px;line-height:1.6;">
      Vous ne devez pas créer une nouvelle demande.
      Les informations déjà renseignées seront conservées.
    </p>

    <div style="text-align:center;margin:30px 0;">
      <a
        href="${correctionUrl}"
        style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
"
      >
        CORRIGER MA DEMANDE
      </a>
    </div>

    <p style="font-size:15px;line-height:1.6;">
      Après validation de vos corrections, votre demande sera
      automatiquement remise en attente d'instruction.
    </p>

    <p style="margin-top:28px;font-size:15px;line-height:1.6;">
      À bientôt sur SPHOT,<br>
      <strong>L'équipe SPHOT</strong>
    </p>
`,
        });

        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "sent",
                recipient: email,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                messageId: mailResult.messageId || null,
                error: null,
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_rejection_email_sent",
                category: "administrative",
                label:
                    "Email de refus envoyé au demandeur",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Email de refus administrateur envoyé :",
            email,
            requestNumber,
        );
      } catch (error) {
        console.error(
            "Erreur envoi email refus administrateur :",
            error,
        );

        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "failed",
                recipient: email,
                sentAt: null,
                messageId: null,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_rejection_email_failed",
                category: "administrative",
                label:
                    "Échec de l'envoi de l'email de refus",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        throw error;
      }
    },
);

exports.sendSubscriptionActivatedEmail = onDocumentUpdated(
    {
      document: "subscriptions/{subscriptionId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === "active") {
        return;
      }

      if (after.status !== "active") {
        return;
      }

      if (after.activationEmailSentAt) {
        return;
      }

      const email = after.billingContactEmail;

      if (!email) {
        console.log(
            "Email facturation absent, aucun email envoyé.",
        );
        return;
      }

      const organisation =
          after.billingOrganisation || "votre organisation";

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      await sendSphotMail(transporter, {
        from: MAIL_FROM,
        to: email,
        subject: "Activation de votre abonnement SPHOT",
        text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation} est maintenant actif.

Vous pouvez désormais utiliser les services associés
à votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
      });

      await event.data.after.ref.set(
          {
            activationEmailSentAt:
                admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );

      console.log(
          "Email activation abonnement envoyé à:",
          email,
      );
    },
);

exports.syncPublicSpotsForSubscription = onDocumentWritten(
    {
      document: "subscriptions/{subscriptionId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const subscription = event.data.after.exists ?
        event.data.after.data() : null;
      await reconcilePublicSubscription(
          event.params.subscriptionId,
          subscription,
      );
    },
);

exports.syncPublicSpotsForAdmin = onDocumentWritten(
    {
      document: "admins/{adminUid}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.exists ?
        event.data.before.data() : null;
      const after = event.data.after.exists ?
        event.data.after.data() : null;
      const territoireIds = new Set();

      [before, after].forEach((data) => {
        const territoireId = ((data && data.territoireId) || "")
            .toString()
            .trim();
        if (territoireId) territoireIds.add(territoireId);
      });

      for (const territoireId of territoireIds) {
        const publish = await isTerritoryPublic(territoireId);
        await reconcilePublicTerritory(territoireId, publish);
      }
    },
);

exports.syncPublicSpotsForAdminRequest = onDocumentWritten(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.exists ?
        event.data.before.data() : null;
      const after = event.data.after.exists ?
        event.data.after.data() : null;
      const territoireIds = new Set([
        adminRequestTerritoryId(before),
        adminRequestTerritoryId(after),
      ]);
      territoireIds.delete("");

      for (const territoireId of territoireIds) {
        const publish = await isTerritoryPublic(territoireId);
        await reconcilePublicTerritory(territoireId, publish);
      }
    },
);

exports.syncPublicSpotsForAdminAccount = onDocumentWritten(
    {
      document: "adminAccounts/{accountId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.exists ?
        event.data.before.data() : null;
      const after = event.data.after.exists ?
        event.data.after.data() : null;
      const territoireIds = new Set([
        adminRequestTerritoryId(before),
        adminRequestTerritoryId(after),
      ]);
      territoireIds.delete("");

      for (const territoireId of territoireIds) {
        const publish = await isTerritoryPublic(territoireId);
        await reconcilePublicTerritory(territoireId, publish);
      }
    },
);

exports.syncPublicSpotsForTerritory = onDocumentWritten(
    {
      document: "territoires/{territoireId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const territoireId = event.params.territoireId;
      const publish = await isTerritoryPublic(territoireId);
      await reconcilePublicTerritory(territoireId, publish);
    },
);

exports.syncPublicSpotOnWrite = onDocumentWritten(
    {
      document: "territoires/{territoireId}/spots/{spotId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const territoireId = event.params.territoireId;
      const spotId = event.params.spotId;
      const publicReference = admin.firestore().collection("publicSpots")
          .doc(`${territoireId}__${spotId}`);

      if (!event.data.after.exists) {
        await publicReference.delete();
        return;
      }

      const publish = await isTerritoryPublic(territoireId);
      if (!publish) {
        await publicReference.delete();
        return;
      }

      await reconcilePublicTerritory(territoireId, true);
    },
);

exports.syncPublicSpotLiveStateOnWrite = onDocumentWritten(
    {
      document: "spots/{spotId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const db = admin.firestore();
      const publicSnapshot = await db.collection("publicSpots")
          .where("spotId", "==", event.params.spotId)
          .get();
      if (publicSnapshot.empty) return;

      const liveState = buildPublicLiveState(
          event.data.after.exists ? event.data.after.data() : {},
      );
      const batch = db.batch();
      publicSnapshot.docs.forEach((document) => {
        batch.set(document.ref, liveState, {merge: true});
      });
      await batch.commit();
    },
);

exports.assignQuoteNumberOnWrite = onDocumentWritten(
    {
      document: "quotes/{quoteId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      await assignCommercialDocumentNumber(
          event,
          COMMERCIAL_DOCUMENTS.quote,
      );
    },
);

exports.assignOrderNumberOnWrite = onDocumentWritten(
    {
      document: "orders/{orderId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      await assignCommercialDocumentNumber(
          event,
          COMMERCIAL_DOCUMENTS.order,
      );
    },
);

exports.assignInvoiceNumberOnWrite = onDocumentWritten(
    {
      document: "invoices/{invoiceId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      await assignCommercialDocumentNumber(
          event,
          COMMERCIAL_DOCUMENTS.invoice,
      );
    },
);

exports.assignCreditNoteNumberOnWrite = onDocumentWritten(
    {
      document: "creditNotes/{creditNoteId}",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      await assignCommercialDocumentNumber(
          event,
          COMMERCIAL_DOCUMENTS.creditNote,
      );
    },
);

exports.updateSubscriptionStatuses = onSchedule(
    {
      schedule: "0 1 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const trialSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", "<", now)
          .get();

      const activeSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "active")
          .where("nextInvoiceDate", "<", now)
          .get();

      const batch = db.batch();

      trialSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      activeSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      await batch.commit();

      console.log(
          "Statuts abonnements mis à jour:",
          trialSnapshot.size + activeSnapshot.size,
      );
    },
);

exports.sendTrialEndingReminderEmails = onSchedule(
    {
      schedule: "0 9 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();

      const start = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 3,
          0,
          0,
          0,
      );

      const end = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 4,
          0,
          0,
          0,
      );

      const startTimestamp = admin.firestore.Timestamp.fromDate(start);
      const endTimestamp = admin.firestore.Timestamp.fromDate(end);

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", ">=", startTimestamp)
          .where("trialEndDate", "<", endTimestamp)
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.trialReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: email,
          subject: "Votre essai SPHOT arrive bientôt à échéance",
          text:
`Bonjour,

Votre période d'essai SPHOT pour ${organisation}
arrive bientôt à échéance.

Pour continuer à utiliser SPHOT sans interruption,
vous pouvez activer votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              trialReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails rappel fin essai envoyés:",
          sentCount,
      );
    },
);

exports.sendOverdueSubscriptionReminderEmails = onSchedule(
    {
      schedule: "0 10 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "overdue")
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.overdueReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: email,
          subject: "Votre abonnement SPHOT nécessite une régularisation",
          text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation}
nécessite une régularisation.

Pour éviter toute interruption de service,
merci de régulariser votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              overdueReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails relance abonnements en retard envoyés:",
          sentCount,
      );
    },
);

exports.testEmailSphot = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      try {
        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: "rabreau.sylvain@gmail.com",
          subject: "Test email SPHOT",
          text: "Test email Firebase Functions SPHOT.",
        });

        response.status(200).send("Email SPHOT envoyé avec succès.");
      } catch (error) {
        console.error("Erreur envoi email SPHOT:", error);
        response.status(500).send("Erreur lors de l'envoi email SPHOT.");
      }
    },
);

exports.sendSauveteurCredentialsEmail = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "GET, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const email = request.query.email;
        const identifiant = request.query.identifiant || "";
        const motDePasse = request.query.motdepasse || "";
        const type = request.query.type || "creation";
        const isReset = type === "reset";
        let nom = (request.query.nom || "").toString().trim();
        let civilite = (request.query.civilite || "")
            .toString()
            .trim();

        if (!email) {
          response.status(400).send("Email manquant.");
          return;
        }

        if (identifiant && (!nom || !civilite)) {
          const accountSnapshot = await admin.firestore()
              .collection("sauveteurAccounts")
              .doc(identifiant.toString().trim().toLowerCase())
              .get();

          if (accountSnapshot.exists) {
            const accountData = accountSnapshot.data() || {};
            nom = nom || (accountData.nom || "").toString().trim();
            civilite = civilite || (
              accountData.civilite ||
              accountData.sexe ||
              accountData.genre ||
              ""
            ).toString().trim();
          }
        }

        const civiliteNormalisee = (() => {
          const valeur = civilite.toLowerCase();

          if (["madame", "mme", "f", "femme"].includes(valeur)) {
            return "Madame";
          }

          if (["monsieur", "m", "m.", "homme"].includes(valeur)) {
            return "Monsieur";
          }

          return civilite;
        })();

        const destinataire = [
          civiliteNormalisee,
          nom.toUpperCase(),
        ]
            .filter((value) => value)
            .join(" ") || "Sauveteur";

        const destinataireHtml =
          `<span style="font-weight:400 !important;">${
            escapeHtml(civiliteNormalisee)
          }</span> <span style="font-weight:700 !important;">${
            escapeHtml(nom.toUpperCase() || "Sauveteur")
          }</span>`;

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: email,
          subject: isReset ?
    "Vos nouveaux accès SPHOT" :
    "Vos accès SPHOT",
          html: `
<p style="font-weight:400 !important;">
  ${destinataireHtml} bonjour,
</p>

${isReset ?
  `` :
  `
<p>
  Bienvenue sur SPHOT.
</p>
`
}

${isReset ? `
<p>
  Votre administrateur SPHOT a procédé à la réinitialisation
de votre mot de passe.
</p>

<p>
  Votre identifiant reste inchangé.
</p>

<p>
  Vous trouverez ci-dessous votre nouveau mot de passe temporaire.
</p>
`:
`
<p>
  Votre compte SPHOT a été créé par votre administrateur.
</p>

<p>
  Vous trouverez ci-dessous votre identifiant
  et votre mot de passe temporaire.
</p>
`
}

      <div style="
          margin:28px 0;
          background:#f7f9fc;
          border:1px solid #d9e2ec;
          border-radius:14px;
          padding:22px;">

        <div style="margin-bottom:18px;">
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Identifiant
          </div>

          <div style="font-size:22px;font-weight:bold;color:#1e3a8a;">
            ${identifiant}
          </div>
        </div>

        <div>
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Mot de passe temporaire
          </div>

          <div style="font-size:22px;font-weight:bold;color:#d91c1c;">
            ${motDePasse}
          </div>
        </div>

      </div>

      ${isReset ? `
<div style="
    background:#fff8e1;
    border-left:5px solid #ff9800;
    padding:16px;
    border-radius:8px;
    margin-bottom:28px;">

<strong>Important</strong><br><br>

À votre prochaine connexion,
vous devrez modifier votre mot de passe.

</div>
`:
`
<div style="
    background:#fff8e1;
    border-left:5px solid #ff9800;
    padding:16px;
    border-radius:8px;
    margin-bottom:28px;">

<strong>Important</strong><br>

Lors de votre première connexion,
vous devrez modifier votre mot de passe.

</div>
`
}

      ${isReset ? "" : `
<div style="
    background:#f3f6fb;
    border-left:5px solid #1e3a8a;
    padding:16px;
    border-radius:8px;
    margin-bottom:28px;">

<strong>SPHOT OFF / SPHOT ON</strong><br><br>

Vous pouvez vous connecter à SPHOT SAUVETEUR dès maintenant,
même si votre administration n'a pas encore ouvert ses droits de diffusion.
<br><br>

En <strong>SPHOT OFF</strong>, vous pouvez découvrir et tester l'application,
mais vos actions ne modifient ni l'état opérationnel réel du poste
ni les informations des sauveteurs actuellement en <strong>SPHOT ON</strong>.
<br><br>

Lorsque votre administration de tutelle ouvre les droits de diffusion
et que vous êtes affecté à un poste de secours,
votre espace passe automatiquement en <strong>SPHOT ON</strong>.

</div>
`}

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p style="margin-top:40px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
`,
          text: isReset ?
`${destinataire} bonjour,

Votre administrateur SPHOT a réinitialisé votre mot de passe.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Utilisez le mot de passe temporaire ci-dessus.

À votre prochaine connexion, vous devrez le modifier.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT` :
`${destinataire} bonjour,

Votre compte SPHOT a été créé par votre administrateur.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Lors de votre première connexion, vous devrez modifier votre mot de passe.

SPHOT OFF / SPHOT ON

Vous pouvez vous connecter à SPHOT SAUVETEUR dès maintenant.

En SPHOT OFF, vous pouvez découvrir et tester l'application, mais vos actions
ne modifient ni l'état opérationnel réel du poste ni les informations des
sauveteurs actuellement en SPHOT ON.

Lorsque votre administration de tutelle ouvre les droits de diffusion et que
vous êtes affecté à un poste de secours, votre espace passe automatiquement
en SPHOT ON.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT`,
        });

        response.status(200).send("Email d'identifiants envoyé.");
      } catch (error) {
        console.error(
            "Erreur envoi email identifiants SPHOT:",
            error,
        );
        response.status(500).send("Erreur lors de l'envoi.");
      }
    },
);

exports.notifySauveteurSphotOffAfterAssignment = onDocumentUpdated(
    {
      document: "sauveteurAccounts/{login}",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data?.before.data() || {};
      const after = event.data?.after.data() || {};

      const beforeSpots = Array.isArray(before.postesAffectes) ?
        before.postesAffectes.filter((value) => value) :
        [];
      const afterSpots = Array.isArray(after.postesAffectes) ?
        after.postesAffectes.filter((value) => value) :
        [];

      if (beforeSpots.length === 0 || afterSpots.length > 0) return;
      if (after.accountStatus !== "ACTIVE") return;

      const email = (after.email || "").toString().trim();
      if (!email) return;

      const prenom = (after.prenom || "").toString().trim();
      const nom = (after.nom || "").toString().trim().toUpperCase();
      const destinataire = [prenom, nom]
          .filter((value) => value)
          .join(" ") || "Sauveteur";

      const mailTransporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      await sendSphotMail(mailTransporter, {
        from: MAIL_FROM,
        to: email,
        subject: "SPHOT SAUVETEUR — Passage en SPHOT OFF",
        html: `
<p>${escapeHtml(destinataire)} bonjour,</p>

<p>
  Votre période d'affectation opérationnelle à un poste de secours
  SPHOT est terminée.
</p>

<div style="
    background:#fff1f2;
    border-left:5px solid #dc2626;
    padding:16px;
    border-radius:8px;
    margin:24px 0;">

<strong>SPHOT OFF</strong><br><br>

Votre compte SPHOT reste accessible et vous pouvez continuer
à consulter, découvrir ou tester l'application.
<br><br>

En SPHOT OFF, vos actions de test
<strong>ne modifient pas l'état opérationnel réel</strong>
des postes de secours et ne peuvent pas altérer les informations
renseignées par les sauveteurs actuellement en SPHOT ON.

</div>

<p>
  Lors d'une nouvelle affectation, SPHOT ON sera réactivé
  automatiquement dès lors que les droits de diffusion de votre
  administration de tutelle seront ouverts.
</p>

<div style="text-align:center;margin:35px 0;">
  <a
    href="${SPHOT_LOGIN_URL}"
    style="
      display:inline-block;
      padding:15px 28px;
      border-radius:14px;
      background:#1e3a8a;
      color:#ffffff;
      text-decoration:none;
      font-size:16px;
      font-weight:900;">
    SE CONNECTER À SPHOT
  </a>
</div>

<p>
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>
`,
        text: `${destinataire} bonjour,

Votre période d'affectation opérationnelle à un poste de secours SPHOT
est terminée.

SPHOT OFF

Votre compte SPHOT reste accessible et vous pouvez continuer à consulter,
découvrir ou tester l'application.

En SPHOT OFF, vos actions de test ne modifient pas l'état opérationnel réel
des postes de secours et ne peuvent pas altérer les informations renseignées
par les sauveteurs actuellement en SPHOT ON.

Lors d'une nouvelle affectation, SPHOT ON sera réactivé automatiquement dès
lors que les droits de diffusion de votre administration de tutelle
seront ouverts.

${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT`,
      });

      await event.data.after.ref.set({
        sphotOffNotificationAt:
          admin.firestore.FieldValue.serverTimestamp(),
        sphotOffNotificationReason: "assignment_ended",
      }, {merge: true});
    },
);

/**
 * Normalise les fonctions métier d'un sauveteur.
 *
 * @param {Object} data Données du compte ou du profil sauveteur.
 * @return {Array<string>} Fonctions normalisées.
 */
function sauveteurFunctions(data) {
  if (Array.isArray(data.fonctions)) {
    return data.fonctions
        .map((value) => (value || "").toString().trim())
        .filter((value) => value);
  }

  const role = (data.role || "").toString().trim();
  return role ? [role] : ["Sauveteur"];
}

/**
 * Indique si le profil peut administrer le planning et la main courante.
 *
 * @param {Array<string>} functions Fonctions du sauveteur.
 * @return {boolean} Vrai pour chef de poste ou adjoint.
 */
function isSauveteurSupervisor(functions) {
  return functions.some((value) => {
    const role = value.toString().trim().toLowerCase();
    return role === "chef de poste" || role === "adjoint chef de poste";
  });
}

/**
 * Reconstitue le contexte opérationnel SPHOT ON / SPHOT OFF.
 *
 * SPHOT ON exige :
 * - un compte actif ;
 * - au moins une affectation à un SPHOT ;
 * - des droits de diffusion ouverts par l'administration de tutelle.
 *
 * @param {Object} accountData Données sauveteurAccounts.
 * @param {string} login Identifiant du compte.
 * @return {Promise<Object>} Contexte opérationnel.
 */
async function resolveSauveteurOperationalContext(accountData, login) {
  const db = admin.firestore();
  const territoireId = (accountData.territoireId || "").toString().trim();
  let sauveteurId = (accountData.sauveteurId || "").toString().trim();
  let profileData = {};

  if (territoireId && sauveteurId) {
    const profileSnapshot = await db.collection("territoires")
        .doc(territoireId)
        .collection("sauveteurs")
        .doc(sauveteurId)
        .get();

    if (profileSnapshot.exists) {
      profileData = profileSnapshot.data() || {};
    }
  } else if (territoireId && login) {
    const profileSnapshot = await db.collection("territoires")
        .doc(territoireId)
        .collection("sauveteurs")
        .where("login", "==", login)
        .limit(1)
        .get();

    if (!profileSnapshot.empty) {
      sauveteurId = profileSnapshot.docs[0].id;
      profileData = profileSnapshot.docs[0].data() || {};
    }
  }

  const functions = sauveteurFunctions({
    ...accountData,
    ...(Array.isArray(profileData.fonctions) ?
      {fonctions: profileData.fonctions} : {}),
  });

  const rawSpots = Array.isArray(profileData.postesAffectes) ?
    profileData.postesAffectes :
    Array.isArray(accountData.postesAffectes) ?
      accountData.postesAffectes :
      [];

  const assignedSpotIds = [...new Set(
      rawSpots
          .map((value) => (value || "").toString().trim())
          .filter((value) => value),
  )];

  let diffusionAccessGranted = false;
  if (territoireId) {
    const adminsSnapshot = await db.collection("admins")
        .where("territoireId", "==", territoireId)
        .get();

    diffusionAccessGranted = adminsSnapshot.docs.some((document) => {
      return document.data().diffusionAccessGranted === true;
    });
  }

  const accountActive = accountData.accountStatus === "ACTIVE";
  const sphotOn = accountActive &&
    diffusionAccessGranted &&
    assignedSpotIds.length > 0;

  let modeReason = "active";
  if (!accountActive) {
    modeReason = "account_inactive";
  } else if (assignedSpotIds.length === 0) {
    modeReason = "no_active_assignment";
  } else if (!diffusionAccessGranted) {
    modeReason = "administration_diffusion_off";
  }

  const userRole = functions[0] ||
    (accountData.role || "Sauveteur").toString();

  return {
    sauveteurId: sauveteurId || login,
    territoireId,
    functions,
    userRole,
    assignedSpotIds,
    diffusionAccessGranted,
    sphotMode: sphotOn ? "ON" : "OFF",
    sphotModeReason: modeReason,
    canManageRestrictedOperationalData:
      isSauveteurSupervisor(functions),
  };
}

/**
 * Crée une session sauveteur non persistante côté client.
 *
 * @param {string} login Identifiant du compte.
 * @param {Object} context Contexte opérationnel.
 * @return {Promise<string>} Jeton de session.
 */
async function createSauveteurSession(login, context) {
  const token = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");

  await admin.firestore()
      .collection("sauveteurSessions")
      .doc(tokenHash)
      .set({
        login,
        sauveteurId: context.sauveteurId,
        territoireId: context.territoireId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + 12 * 60 * 60 * 1000,
        ),
      });

  return token;
}

/**
 * Valide une session sauveteur et recalcule ses droits en temps réel.
 *
 * @param {string} token Jeton reçu lors de la connexion.
 * @return {Promise<Object|null>} Session et contexte courant.
 */
async function resolveSauveteurSession(token) {
  const normalizedToken = (token || "").toString().trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalizedToken)) return null;

  const db = admin.firestore();
  const tokenHash = crypto
      .createHash("sha256")
      .update(normalizedToken)
      .digest("hex");
  const sessionReference = db.collection("sauveteurSessions").doc(tokenHash);
  const sessionSnapshot = await sessionReference.get();

  if (!sessionSnapshot.exists) return null;

  const session = sessionSnapshot.data() || {};
  const expiresAt = session.expiresAt;

  if (!expiresAt ||
      typeof expiresAt.toMillis !== "function" ||
      expiresAt.toMillis() < Date.now()) {
    await sessionReference.delete();
    return null;
  }

  const login = (session.login || "").toString().trim().toLowerCase();
  const accountSnapshot = await db.collection("sauveteurAccounts")
      .doc(login)
      .get();

  if (!accountSnapshot.exists) return null;

  const accountData = accountSnapshot.data() || {};
  if (accountData.accountStatus !== "ACTIVE") return null;

  const context = await resolveSauveteurOperationalContext(
      accountData,
      login,
  );

  return {
    login,
    accountData,
    context,
  };
}

exports.loginSauveteur = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const password = (request.body.password || "")
            .toString()
            .trim();

        if (!login || !password) {
          response.status(400).json({success: false});
          return;
        }

        const accountDoc = await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .get();

        if (!accountDoc.exists) {
          response.status(401).json({success: false});
          return;
        }

        const data = accountDoc.data() || {};

        if (data.accountStatus !== "ACTIVE") {
          response.status(401).json({success: false});
          return;
        }

        if (data.temporaryPassword !== password) {
          response.status(401).json({success: false});
          return;
        }

        const context = await resolveSauveteurOperationalContext(
            data,
            login,
        );

        await accountDoc.ref.set(
            {
              sauveteurId: context.sauveteurId,
              fonctions: context.functions,
              postesAffectes: context.assignedSpotIds,
              lastLoginAt:
                  admin.firestore.FieldValue.serverTimestamp(),
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        const sauveteurSessionToken = await createSauveteurSession(
            login,
            context,
        );

        let webSessionToken = "";

        if (context.userRole.toUpperCase() === "SUPER_ADMIN") {
          webSessionToken = crypto.randomBytes(32).toString("hex");
          const tokenHash = crypto
              .createHash("sha256")
              .update(webSessionToken)
              .digest("hex");

          await admin.firestore()
              .collection("superAdminWebSessions")
              .doc(tokenHash)
              .set({
                login: accountDoc.id,
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: admin.firestore.Timestamp.fromMillis(
                    Date.now() + 5 * 60 * 1000,
                ),
              });
        }

        response.status(200).json({
          success: true,
          sauveteurId: context.sauveteurId,
          territoireId: context.territoireId,
          userRole: context.userRole,
          fonctions: context.functions,
          postesAffectes: context.assignedSpotIds,
          diffusionAccessGranted: context.diffusionAccessGranted,
          sphotMode: context.sphotMode,
          sphotModeReason: context.sphotModeReason,
          canManageRestrictedOperationalData:
            context.canManageRestrictedOperationalData,
          mustChangePassword: data.mustChangePassword === true,
          sauveteurSessionToken,
          webSessionToken,
        });
      } catch (error) {
        console.error("Erreur login sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.getSauveteurSessionState = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const session = await resolveSauveteurSession(
            request.body.sauveteurSessionToken,
        );

        if (!session) {
          response.status(401).json({
            success: false,
            error: "invalid_session",
          });
          return;
        }

        const {context} = session;

        response.status(200).json({
          success: true,
          sauveteurId: context.sauveteurId,
          territoireId: context.territoireId,
          userRole: context.userRole,
          fonctions: context.functions,
          postesAffectes: context.assignedSpotIds,
          diffusionAccessGranted: context.diffusionAccessGranted,
          sphotMode: context.sphotMode,
          sphotModeReason: context.sphotModeReason,
          canManageRestrictedOperationalData:
            context.canManageRestrictedOperationalData,
        });
      } catch (error) {
        console.error("Erreur lecture état session sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.saveSauveteurPlanning = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({success: false});
        return;
      }

      try {
        const session = await resolveSauveteurSession(
            request.body.sauveteurSessionToken,
        );

        if (!session) {
          response.status(401).json({
            success: false,
            error: "invalid_session",
          });
          return;
        }

        const {context} = session;
        const spotId = (request.body.spotId || "").toString().trim();
        const monthId = (request.body.monthId || "").toString().trim();

        if (!context.sphotMode || context.sphotMode !== "ON") {
          response.status(403).json({
            success: false,
            error: "sphot_off",
          });
          return;
        }

        if (!context.assignedSpotIds.includes(spotId)) {
          response.status(403).json({
            success: false,
            error: "spot_not_assigned",
          });
          return;
        }

        if (!context.canManageRestrictedOperationalData) {
          response.status(403).json({
            success: false,
            error: "insufficient_role",
          });
          return;
        }

        if (!spotId || !monthId) {
          response.status(400).json({
            success: false,
            error: "missing_fields",
          });
          return;
        }

        await admin.firestore()
            .collection("territoires")
            .doc(context.territoireId)
            .collection("spots")
            .doc(spotId)
            .collection("planningSauveteurs")
            .doc(monthId)
            .set({
              spotId,
              spotLabel: (request.body.spotLabel || "").toString(),
              monthId,
              openingHours:
                (request.body.openingHours || "").toString(),
              cells: request.body.cells || {},
              names: request.body.names || {},
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedBy: {
                sauveteurId: context.sauveteurId,
                login: session.login,
                role: context.userRole,
              },
            }, {merge: true});

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur sauvegarde planning sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.updateSauveteurLiveState = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({success: false});
        return;
      }

      try {
        const session = await resolveSauveteurSession(
            request.body.sauveteurSessionToken,
        );

        if (!session) {
          response.status(401).json({
            success: false,
            error: "invalid_session",
          });
          return;
        }

        const {context} = session;
        const spotId = (request.body.spotId || "").toString().trim();
        const changes = request.body.changes || {};

        if (context.sphotMode !== "ON") {
          response.status(403).json({
            success: false,
            error: "sphot_off",
          });
          return;
        }

        if (!context.assignedSpotIds.includes(spotId)) {
          response.status(403).json({
            success: false,
            error: "spot_not_assigned",
          });
          return;
        }

        const allowedFields = new Set([
          "liveFlag",
          "statutBaignade",
          "dangers",
          "meteoTerrestre",
          "meteoMarine",
          "ephemeride",
        ]);
        const sanitizedChanges = {};

        Object.entries(changes).forEach(([key, value]) => {
          if (allowedFields.has(key)) sanitizedChanges[key] = value;
        });

        if (Object.keys(sanitizedChanges).length === 0) {
          response.status(400).json({
            success: false,
            error: "no_allowed_changes",
          });
          return;
        }

        const db = admin.firestore();
        const spotReference = db.collection("spots").doc(spotId);
        const auditReference = db.collection("sauveteurOperationalAudit").doc();

        const batch = db.batch();
        batch.set(spotReference, {
          ...sanitizedChanges,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBySauveteurId: context.sauveteurId,
        }, {merge: true});
        batch.set(auditReference, {
          territoireId: context.territoireId,
          spotId,
          sauveteurId: context.sauveteurId,
          login: session.login,
          role: context.userRole,
          changes: sanitizedChanges,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await batch.commit();

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur mise à jour live sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.getSauveteurMainCourante = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const session = await resolveSauveteurSession(
            request.body.sauveteurSessionToken,
        );

        if (!session) {
          response.status(401).json({
            success: false,
            error: "invalid_session",
          });
          return;
        }

        const {context} = session;
        const spotId = (request.body.spotId || "").toString().trim();

        if (context.sphotMode !== "ON" ||
            !context.assignedSpotIds.includes(spotId)) {
          response.status(403).json({
            success: false,
            error: "main_courante_not_available",
          });
          return;
        }

        const snapshot = await admin.firestore()
            .collection("territoires")
            .doc(context.territoireId)
            .collection("spots")
            .doc(spotId)
            .collection("mainCourante")
            .orderBy("occurredAt", "desc")
            .limit(100)
            .get();

        const canSeeRestricted =
          context.canManageRestrictedOperationalData;

        const entries = snapshot.docs
            .map((document) => {
              const data = document.data() || {};
              return {id: document.id, ...data};
            })
            .filter((entry) => {
              return entry.visibility !== "restricted" || canSeeRestricted;
            })
            .map((entry) => ({
              id: entry.id,
              type: entry.type || "Observation",
              description: entry.description || "",
              actionTaken: entry.actionTaken || "",
              visibility: entry.visibility || "operational",
              occurredAt: entry.occurredAt &&
                  typeof entry.occurredAt.toMillis === "function" ?
                entry.occurredAt.toMillis() : null,
              createdBy: entry.createdBy || {},
            }));

        await admin.firestore()
            .collection("mainCouranteAccessLogs")
            .add({
              territoireId: context.territoireId,
              spotId,
              viewerId: context.sauveteurId,
              viewerLogin: session.login,
              viewerRole: context.userRole,
              viewerType: "sauveteur",
              action: "view",
              viewedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        response.status(200).json({
          success: true,
          entries,
          canWrite: context.canManageRestrictedOperationalData,
        });
      } catch (error) {
        console.error("Erreur lecture main courante:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.addSauveteurMainCouranteEntry = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const session = await resolveSauveteurSession(
            request.body.sauveteurSessionToken,
        );

        if (!session) {
          response.status(401).json({
            success: false,
            error: "invalid_session",
          });
          return;
        }

        const {context} = session;
        const spotId = (request.body.spotId || "").toString().trim();

        if (context.sphotMode !== "ON" ||
            !context.assignedSpotIds.includes(spotId)) {
          response.status(403).json({
            success: false,
            error: "sphot_off",
          });
          return;
        }

        if (!context.canManageRestrictedOperationalData) {
          response.status(403).json({
            success: false,
            error: "insufficient_role",
          });
          return;
        }

        const description = (request.body.description || "")
            .toString()
            .trim();

        if (!description) {
          response.status(400).json({
            success: false,
            error: "description_required",
          });
          return;
        }

        const visibility = request.body.visibility === "restricted" ?
          "restricted" :
          "operational";

        const entryReference = admin.firestore()
            .collection("territoires")
            .doc(context.territoireId)
            .collection("spots")
            .doc(spotId)
            .collection("mainCourante")
            .doc();

        await entryReference.set({
          type: (request.body.type || "Observation").toString(),
          description,
          actionTaken: (request.body.actionTaken || "").toString().trim(),
          visibility,
          occurredAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: {
            sauveteurId: context.sauveteurId,
            login: session.login,
            role: context.userRole,
          },
          immutableOriginal: true,
        });

        response.status(200).json({
          success: true,
          entryId: entryReference.id,
        });
      } catch (error) {
        console.error("Erreur écriture main courante:", error);
        response.status(500).json({success: false});
      }
    },
);

/** Valide et consomme un passage unique vers le dashboard Super Admin. */
exports.consumeSuperAdminWebSession = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const token = cleanValue(
            (request.body || {}).token,
            "",
        ).toLowerCase();

        if (!/^[a-f0-9]{64}$/.test(token)) {
          response.status(401).json({success: false});
          return;
        }

        const tokenHash = crypto
            .createHash("sha256")
            .update(token)
            .digest("hex");
        const sessionReference = admin.firestore()
            .collection("superAdminWebSessions")
            .doc(tokenHash);

        const accepted = await admin.firestore().runTransaction(
            async (transaction) => {
              const snapshot = await transaction.get(sessionReference);
              if (!snapshot.exists) return false;

              const session = snapshot.data() || {};
              const expiresAt = session.expiresAt;
              if (!expiresAt ||
                  typeof expiresAt.toMillis !== "function" ||
                  expiresAt.toMillis() < Date.now()) {
                transaction.delete(sessionReference);
                return false;
              }

              transaction.delete(sessionReference);
              return true;
            },
        );

        if (!accepted) {
          response.status(401).json({success: false});
          return;
        }

        response.status(200).json({success: true});
      } catch (error) {
        console.error(
            "Erreur validation session Web Super Admin:",
            error,
        );
        response.status(500).json({success: false});
      }
    },
);

exports.requestAdminReplacement = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({
          success: false,
          error: "method_not_allowed",
        });
        return;
      }

      try {
        const body = request.body || {};

        const adminUid = cleanValue(
            body.adminUid,
            "",
        );

        const currentEmail = cleanValue(
            body.currentEmail,
            "",
        ).toLowerCase();

        const currentPassword = cleanValue(
            body.currentPassword,
            "",
        );

        const newCivilite = cleanValue(
            body.newCivilite,
            "",
        );

        const newPrenom = cleanValue(
            body.newPrenom,
            "",
        );

        const newNom = cleanValue(
            body.newNom,
            "",
        ).toUpperCase();

        const newFonction = cleanValue(
            body.newFonction,
            "",
        );

        const newEmail = cleanValue(
            body.newEmail,
            "",
        ).toLowerCase();

        const newTelephone = cleanValue(
            body.newTelephone,
            "",
        );

        if (
          !adminUid ||
          !currentEmail ||
          !currentPassword ||
          !newPrenom ||
          !newNom ||
          !newEmail
        ) {
          response.status(400).json({
            success: false,
            error: "missing_fields",
          });
          return;
        }

        if (currentEmail === newEmail) {
          response.status(400).json({
            success: false,
            error: "same_email",
          });
          return;
        }

        const db = admin.firestore();

        const currentAccountReference = db
            .collection("adminAccounts")
            .doc(currentEmail);

        const newAccountReference = db
            .collection("adminAccounts")
            .doc(newEmail);

        const currentAccountSnapshot =
            await currentAccountReference.get();

        if (!currentAccountSnapshot.exists) {
          response.status(401).json({
            success: false,
            error: "invalid_credentials",
          });
          return;
        }

        const currentAccountData =
            currentAccountSnapshot.data() || {};

        const currentAccountStatus = cleanValue(
            currentAccountData.accountStatus,
            "",
        ).toUpperCase();

        const storedPassword = cleanValue(
            currentAccountData.temporaryPassword,
            "",
        );

        if (
          currentAccountStatus !== "ACTIVE" ||
          storedPassword !== currentPassword
        ) {
          response.status(401).json({
            success: false,
            error: "invalid_credentials",
          });
          return;
        }

        const storedAdminUid = cleanValue(
            currentAccountData.adminUid,
            "",
        );

        if (
          storedAdminUid &&
          storedAdminUid !== adminUid
        ) {
          response.status(403).json({
            success: false,
            error: "admin_mismatch",
          });
          return;
        }

        const newAccountSnapshot =
    await newAccountReference.get();

        const newAccountData =
    newAccountSnapshot.data() || {};

        const newAccountStatus = cleanValue(
            newAccountData.accountStatus,
            "",
        ).toUpperCase();

        const newAccountAdminUid = cleanValue(
            newAccountData.adminUid,
            "",
        );

        const reusableFormerAdmin =
    newAccountSnapshot.exists &&
    newAccountStatus === "REPLACED" &&
    newAccountAdminUid === adminUid;

        if (
          newAccountSnapshot.exists &&
  !reusableFormerAdmin
        ) {
          response.status(409).json({
            success: false,
            error: "email_already_used",
          });
          return;
        }

        const requestId = cleanValue(
            currentAccountData.requestId || adminUid,
            adminUid,
        );

        const territoireId = cleanValue(
            currentAccountData.territoireId,
            "",
        );

        const organisation = cleanValue(
            currentAccountData.organisation,
            "votre organisme",
        );

        const requestNumber = cleanValue(
            currentAccountData.requestNumber,
            "",
        );

        const temporaryPassword =
            generateAdminTemporaryPassword();

        const now = admin.firestore.Timestamp.now();

        const adminReference = db
            .collection("admins")
            .doc(adminUid);

        const requestReference = db
            .collection("adminRequests")
            .doc(requestId);

        const [
          adminSnapshot,
          requestSnapshot,
        ] = await Promise.all([
          adminReference.get(),
          requestReference.get(),
        ]);

        const replacementData = {
          status: "pending_activation",
          previousEmail: currentEmail,
          newEmail: newEmail,
          newCivilite: newCivilite,
          newPrenom: newPrenom,
          newNom: newNom,
          newFonction: newFonction,
          newTelephone: newTelephone,
          requestedAt: now,
          activatedAt: null,
        };

        const batch = db.batch();

        batch.set(
            newAccountReference,
            {
              login: newEmail,
              email: newEmail,
              temporaryPassword: temporaryPassword,
              mustChangePassword: true,
              accountStatus: "ACTIVE",
              role: "ADMIN",
              adminUid: adminUid,
              territoireId: territoireId,
              civilite: newCivilite,
              prenom: newPrenom,
              nom: newNom,
              fonction: newFonction,
              telephone: newTelephone,
              organisation: organisation,
              requestId: requestId,
              requestNumber: requestNumber,

              replacementPending: true,
              replacesLogin: currentEmail,

              createdAt:
    reusableFormerAdmin &&
    newAccountData.createdAt ?
      newAccountData.createdAt :
      now,

              reactivatedAt:
    reusableFormerAdmin ?
      now :
      null,

              reactivatedFormerAdmin:
    reusableFormerAdmin,

              updatedAt: now,
            },
        );

        batch.set(
            currentAccountReference,
            {
              replacementPending: true,
              replacementTargetLogin: newEmail,
              replacementRequestedAt: now,
              updatedAt: now,
            },
            {merge: true},
        );

        if (adminSnapshot.exists) {
          batch.set(
              adminReference,
              {
                administratorReplacement:
                    replacementData,
                updatedAt: now,
              },
              {merge: true},
          );
        }

        if (requestSnapshot.exists) {
          batch.set(
              requestReference,
              {
                administratorReplacement:
                    replacementData,
                updatedAt: now,
              },
              {merge: true},
          );
        }

        await batch.commit();

        const transporter =
            nodemailer.createTransport({
              service: "gmail",
              auth: {
                user: SMTP_USER,
                pass:
                    process.env.GMAIL_APP_PASSWORD,
              },
            });

        const loginUrl =
            `${SPHOT_LOGIN_URL}/#/professional-login`;

        try {
          await sendSphotMail(
              transporter,
              {
                from: MAIL_FROM,
                to: newEmail,
                replyTo: "contact@sphot.app",
                subject:
                    "SPHOT - Vous devenez administrateur SPHOT",

                text:
`${newCivilite} ${newNom} bonjour,

Vous avez été désigné(e) comme nouvel administrateur
du SPHOT ADMIN de ${organisation}.

VOS IDENTIFIANTS DE CONNEXION

Adresse email :
${newEmail}

Mot de passe provisoire :
${temporaryPassword}

Lors de votre première connexion, vous devrez
obligatoirement choisir un nouveau mot de passe.

SE CONNECTER À VOTRE SPHOT ADMIN :
${loginUrl}

La configuration existante du SPHOT ADMIN,
ses SPHOTS, ses sauveteurs, ses périodes de surveillance
et ses informations administratives seront conservés.

À bientôt sur SPHOT,

L'équipe SPHOT`,

                html: `
<p>
  ${escapeHtml(newCivilite)}
  <strong>${escapeHtml(newNom)}</strong> bonjour,
</p>

<p>
  Vous avez été désigné(e) comme
  <strong>nouvel administrateur</strong>
  du SPHOT ADMIN de
  <strong>${escapeHtml(organisation)}</strong>.
</p>

<div style="
  margin:24px 0;
  padding:18px;
  background:#f3f6fb;
  border:1px solid #1e3a8a;
  border-radius:12px;
">
  <strong>VOS IDENTIFIANTS DE CONNEXION</strong>
  <br><br>

  Adresse email :<br>
  <strong>${escapeHtml(newEmail)}</strong>
  <br><br>

  Mot de passe provisoire :<br>
  <strong>${escapeHtml(temporaryPassword)}</strong>
</div>

<p>
  Lors de votre première connexion,
  vous devrez obligatoirement choisir
  un nouveau mot de passe.
</p>

<div style="text-align:center;margin:30px 0;">
  <a
    href="${loginUrl}"
    style="
      display:inline-block;
      padding:15px 28px;
      border-radius:14px;
      background:#1e3a8a;
      color:#ffffff;
      text-decoration:none;
      font-weight:900;
    "
  >
    SE CONNECTER À VOTRE SPHOT ADMIN
  </a>
</div>

<p>
  La configuration existante du SPHOT ADMIN,
  ses SPHOTS, ses sauveteurs,
  ses périodes de surveillance et ses informations
  administratives seront conservés.
</p>

<p>
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>
`,
              },
          );
        } catch (mailError) {
          /*
           * Si l'invitation ne peut pas partir,
           * on annule la création du successeur.
           * L'ancien administrateur reste donc actif.
           */
          const rollbackBatch = db.batch();

          rollbackBatch.delete(
              newAccountReference,
          );

          rollbackBatch.set(
              currentAccountReference,
              {
                replacementPending: false,
                replacementTargetLogin: null,
                replacementRequestedAt: null,
                updatedAt:
                    admin.firestore.Timestamp.now(),
              },
              {merge: true},
          );

          if (adminSnapshot.exists) {
            rollbackBatch.set(
                adminReference,
                {
                  administratorReplacement: {
                    ...replacementData,
                    status: "invitation_failed",
                  },
                  updatedAt:
                      admin.firestore.Timestamp.now(),
                },
                {merge: true},
            );
          }

          if (requestSnapshot.exists) {
            rollbackBatch.set(
                requestReference,
                {
                  administratorReplacement: {
                    ...replacementData,
                    status: "invitation_failed",
                  },
                  updatedAt:
                      admin.firestore.Timestamp.now(),
                },
                {merge: true},
            );
          }

          await rollbackBatch.commit();

          console.error(
              "Erreur invitation nouvel administrateur:",
              mailError,
          );

          response.status(500).json({
            success: false,
            error: "invitation_email_failed",
          });
          return;
        }

        /*
         * Confirmation à l'administrateur actuel.
         * Une erreur sur ce second mail ne bloque pas
         * le changement déjà préparé.
         */
        try {
          await sendSphotMail(
              transporter,
              {
                from: MAIL_FROM,
                to: currentEmail,
                replyTo: "contact@sphot.app",
                subject:
                    "SPHOT - Changement d'administrateur enregistré",

                text:
`Bonjour,

Votre demande de changement d'administrateur
pour ${organisation} a bien été enregistrée.

Le nouvel administrateur invité est :
${newPrenom} ${newNom}
${newEmail}

Votre accès SPHOT ADMIN reste actif
jusqu'à l'activation du compte du nouvel administrateur.

Aucune configuration, aucun SPHOT,
aucun sauveteur ni aucune période de surveillance
ne sera supprimé lors du transfert.

Cordialement,

L'équipe SPHOT`,
              },
          );
        } catch (confirmationError) {
          console.error(
              "Erreur confirmation ancien administrateur:",
              confirmationError,
          );
        }

        const sentAt =
            admin.firestore.Timestamp.now();

        await newAccountReference.set(
            {
              invitationEmailStatus: "sent",
              invitationEmailSentAt: sentAt,
              updatedAt: sentAt,
            },
            {merge: true},
        );

        response.status(200).json({
          success: true,
          newEmail: newEmail,
        });
      } catch (error) {
        console.error(
            "Erreur changement administrateur:",
            error,
        );

        response.status(500).json({
          success: false,
          error: "internal_error",
        });
      }
    },
);

/**
 * Met à jour le profil administrateur dans une transaction Firestore.
 *
 * @param {Object} transaction Transaction Firestore en cours.
 * @param {Object|null} reference Référence du document à modifier.
 * @param {Object|null} snapshot Snapshot du document.
 * @param {Object} data Données à enregistrer.
 * @return {void}
 */
function finaliseAdministratorProfile(
    transaction,
    reference,
    snapshot,
    data,
) {
  if (!reference || !snapshot || !snapshot.exists) {
    return;
  }

  transaction.update(reference, data);
}

exports.loginAdmin = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const password = (request.body.password || "")
            .toString()
            .trim();

        if (!login || !password) {
          response.status(400).json({success: false});
          return;
        }

        const accountDoc = await admin.firestore()
            .collection("adminAccounts")
            .doc(login)
            .get();

        if (!accountDoc.exists) {
          response.status(401).json({success: false});
          return;
        }

        const data = accountDoc.data();

        if (data.accountStatus !== "ACTIVE") {
          response.status(401).json({success: false});
          return;
        }

        if (data.temporaryPassword !== password) {
          response.status(401).json({success: false});
          return;
        }

        /*
         * Si ce compte est celui d'un administrateur successeur,
         * sa première connexion valide définitivement le transfert.
         */
        if (data.replacementPending === true) {
          const replacesLogin = cleanValue(
              data.replacesLogin,
              "",
          ).toLowerCase();

          if (replacesLogin) {
            const db = admin.firestore();

            const currentAccountReference =
                accountDoc.ref;

            const previousAccountReference = db
                .collection("adminAccounts")
                .doc(replacesLogin);

            const adminUid = cleanValue(
                data.adminUid,
                "",
            );

            const requestId = cleanValue(
                data.requestId || adminUid,
                adminUid,
            );

            const adminReference = adminUid ?
              db.collection("admins").doc(adminUid) :
              null;

            const requestReference = requestId ?
              db.collection("adminRequests").doc(requestId) :
              null;

            const historyReference = db
                .collection("adminReplacementHistory")
                .doc();

            const replacementResult = await db.runTransaction(
                async (transaction) => {
                  /*
                   * On relit le compte successeur dans la transaction
                   * afin d'éviter une double activation.
                   */
                  const freshCurrentSnapshot =
                      await transaction.get(
                          currentAccountReference,
                      );

                  if (!freshCurrentSnapshot.exists) {
                    throw new Error(
                        "Compte successeur introuvable.",
                    );
                  }

                  const freshCurrentData =
                      freshCurrentSnapshot.data() || {};

                  if (
                    freshCurrentData.replacementPending !== true
                  ) {
                    return {
                      activated: false,
                    };
                  }

                  const previousAccountSnapshot =
                      await transaction.get(
                          previousAccountReference,
                      );

                  let adminSnapshot = null;
                  let requestSnapshot = null;

                  if (adminReference) {
                    adminSnapshot =
                        await transaction.get(
                            adminReference,
                        );
                  }

                  if (requestReference) {
                    requestSnapshot =
                        await transaction.get(
                            requestReference,
                        );
                  }

                  const activatedAt =
                      admin.firestore.Timestamp.now();

                  const newCivilite = cleanValue(
                      freshCurrentData.civilite,
                      "",
                  );

                  const newPrenom = cleanValue(
                      freshCurrentData.prenom,
                      "",
                  );

                  const newNom = cleanValue(
                      freshCurrentData.nom,
                      "",
                  ).toUpperCase();

                  const newFonction = cleanValue(
                      freshCurrentData.fonction,
                      "",
                  );

                  const newTelephone = cleanValue(
                      freshCurrentData.telephone,
                      "",
                  );

                  const newEmail = cleanValue(
                      freshCurrentData.email ||
                      freshCurrentData.login,
                      login,
                  ).toLowerCase();

                  /*
                   * Le nouveau compte devient définitivement
                   * l'administrateur actif.
                   */
                  transaction.set(
                      currentAccountReference,
                      {
                        replacementPending: false,
                        replacementActivatedAt:
                            activatedAt,
                        replacementActivatedBy:
                            "first_login",
                        updatedAt: activatedAt,
                      },
                      {merge: true},
                  );

                  /*
                   * L'ancien compte est désactivé.
                   * Il reste conservé pour la traçabilité.
                   */
                  if (previousAccountSnapshot.exists) {
                    transaction.set(
                        previousAccountReference,
                        {
                          accountStatus: "REPLACED",
                          replacementPending: false,
                          replacedByLogin: newEmail,
                          replacedAt: activatedAt,
                          updatedAt: activatedAt,
                        },
                        {merge: true},
                    );
                  }

                  finaliseAdministratorProfile(
                      transaction,
                      adminReference,
                      adminSnapshot,
                      {
                        "profile.civilite":
                            newCivilite,
                        "profile.prenom":
                            newPrenom,
                        "profile.prenomAffiche":
                            newPrenom,
                        "profile.nom":
                            newNom,
                        "profile.nomAffiche":
                            newNom,
                        "profile.fonction":
                            newFonction,
                        "profile.email":
                            newEmail,
                        "profile.telephone":
                            newTelephone,
                        "civilite":
                            newCivilite,
                        "prenomResponsable":
                            newPrenom,
                        "nomResponsable":
                            newNom,
                        "fonction":
                            newFonction,
                        "email":
                            newEmail,
                        "telephone":
                            newTelephone,
                        "administratorReplacement.status":
                            "activated",
                        "administratorReplacement.activatedAt":
                            activatedAt,
                        "updatedAt":
                            activatedAt,
                      },
                  );

                  finaliseAdministratorProfile(
                      transaction,
                      requestReference,
                      requestSnapshot,
                      {
                        "profile.civilite":
                            newCivilite,
                        "profile.prenom":
                            newPrenom,
                        "profile.prenomAffiche":
                            newPrenom,
                        "profile.nom":
                            newNom,
                        "profile.nomAffiche":
                            newNom,
                        "profile.fonction":
                            newFonction,
                        "profile.email":
                            newEmail,
                        "profile.telephone":
                            newTelephone,
                        "civilite":
                            newCivilite,
                        "prenomResponsable":
                            newPrenom,
                        "nomResponsable":
                            newNom,
                        "fonction":
                            newFonction,
                        "email":
                            newEmail,
                        "telephone":
                            newTelephone,
                        "administratorReplacement.status":
                            "activated",
                        "administratorReplacement.activatedAt":
                            activatedAt,
                        "updatedAt":
                            activatedAt,
                      },
                  );

                  /*
                   * Historique indépendant : aucune ancienne
                   * information n'est écrasée.
                   */
                  transaction.set(
                      historyReference,
                      {
                        adminUid: adminUid,
                        requestId: requestId,
                        previousEmail:
                            replacesLogin,
                        newEmail:
                            newEmail,
                        newCivilite:
                            newCivilite,
                        newPrenom:
                            newPrenom,
                        newNom:
                            newNom,
                        newFonction:
                            newFonction,
                        newTelephone:
                            newTelephone,
                        activatedAt:
                            activatedAt,
                        activationMode:
                            "first_login",
                      },
                  );
                  return {
                    activated: true,
                    previousEmail: replacesLogin,
                    organisation: cleanValue(
                        freshCurrentData.organisation,
                        "votre organisme",
                    ),
                    newPrenom: newPrenom,
                    newNom: newNom,
                    newEmail: newEmail,
                  };
                },
            );
            if (
              replacementResult &&
  replacementResult.activated === true &&
  replacementResult.previousEmail
            ) {
              try {
                const transporter = nodemailer.createTransport({
                  service: "gmail",
                  auth: {
                    user: SMTP_USER,
                    pass: process.env.GMAIL_APP_PASSWORD,
                  },
                });

                const organisation = cleanValue(
                    replacementResult.organisation,
                    "votre organisme",
                );

                const newPrenom = cleanValue(
                    replacementResult.newPrenom,
                    "",
                );

                const newNom = cleanValue(
                    replacementResult.newNom,
                    "",
                ).toUpperCase();

                const newEmail = cleanValue(
                    replacementResult.newEmail,
                    "",
                );

                await sendSphotMail(transporter, {
                  from: MAIL_FROM,
                  to: replacementResult.previousEmail,
                  replyTo: "contact@sphot.app",
                  subject:
          "SPHOT - Changement d'administrateur finalisé",

                  text:
`Bonjour,

Nous vous confirmons que le changement d'administrateur
du SPHOT ADMIN de ${organisation} est désormais effectif.

Le nouvel administrateur :

${newPrenom} ${newNom}
${newEmail}

a activé son accès à SPHOT ADMIN.

Votre accès administrateur est désormais désactivé.
Vos anciens identifiants ne permettent plus de vous connecter
à ce SPHOT ADMIN.

L'ensemble de la configuration, des SPHOTS, des sauveteurs,
des périodes de surveillance et des informations administratives
a été conservé et reste accessible au nouvel administrateur.

Si vous n'êtes pas à l'origine de cette demande,
contactez immédiatement l'équipe SPHOT :
contact@sphot.app

Cordialement,

L'équipe SPHOT`,

                  html: `
<p>
  Bonjour,
</p>

<p>
  Nous vous confirmons que le changement d'administrateur
  du SPHOT ADMIN de
  <strong>${escapeHtml(organisation)}</strong>
  est désormais <strong>effectif</strong>.
</p>

<p>
  Le nouvel administrateur :
</p>

<div style="
  margin:20px 0;
  padding:16px;
  border-left:4px solid #1e3a8a;
  border-radius:8px;
  background:#f3f6fb;
">
  <strong>
    ${escapeHtml(newPrenom)}
    ${escapeHtml(newNom)}
  </strong>
  <br>
  ${escapeHtml(newEmail)}
</div>

<p>
  a activé son accès à SPHOT ADMIN.
</p>

<div style="
  margin:20px 0;
  padding:16px;
  border-left:4px solid #dc2626;
  border-radius:8px;
  background:#fff1f1;
">
  <strong>Votre accès administrateur est désormais désactivé.</strong>
  <br><br>
  Vos anciens identifiants ne permettent plus de vous connecter
  à ce SPHOT ADMIN.
</div>

<p>
  L'ensemble de la configuration, des SPHOTS, des sauveteurs,
  des périodes de surveillance et des informations administratives
  a été conservé et reste accessible au nouvel administrateur.
</p>

<p>
  Si vous n'êtes pas à l'origine de cette demande,
  contactez immédiatement l'équipe SPHOT à l'adresse
  <a
    href="mailto:contact@sphot.app"
    style="color:#1e3a8a;font-weight:700;"
  >
    contact@sphot.app
  </a>.
</p>

<p>
  Cordialement,<br>
  <strong>L'équipe SPHOT</strong>
</p>
`,
                });

                await currentAccountReference.set(
                    {
                      replacementCompletionEmailStatus: "sent",
                      replacementCompletionEmailSentAt:
              admin.firestore.FieldValue.serverTimestamp(),
                    },
                    {merge: true},
                );
              } catch (mailError) {
                console.error(
                    "Erreur email clôture changement administrateur:",
                    mailError,
                );

                await currentAccountReference.set(
                    {
                      replacementCompletionEmailStatus: "error",
                      replacementCompletionEmailError:
              mailError.toString(),
                      updatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
                    },
                    {merge: true},
                );
              }
            }
          }
        }

        await accountDoc.ref.set(
            {
              lastLoginAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        response.status(200).json({
          success: true,
          adminId: accountDoc.id,
          adminUid: (data.adminUid || "").toString(),
          territoireId: (data.territoireId || "").toString(),
          userRole: (data.role || "ADMIN").toString(),
          mustChangePassword: data.mustChangePassword === true,
          civilite: (data.civilite || "").toString(),
          prenom: (data.prenom || "").toString(),
          nom: (data.nom || "").toString(),
        });
      } catch (error) {
        console.error("Erreur login admin:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.upsertSauveteurAccount = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const data = request.body || {};
        const login = (data.login || "").toString().trim().toLowerCase();

        if (!login) {
          response.status(400).json({success: false});
          return;
        }

        await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .set(
                {
                  ...data,
                  login: login,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur upsert sauveteurAccount:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.changeSauveteurPassword = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const newPassword = (request.body.newPassword || "")
            .toString()
            .trim();

        if (!login || !newPassword) {
          response.status(400).json({success: false});
          return;
        }

        const accountReference = admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login);

        const accountResult = await admin.firestore().runTransaction(
            async (transaction) => {
              const accountSnapshot = await transaction.get(
                  accountReference,
              );

              if (!accountSnapshot.exists) {
                return {exists: false};
              }

              const accountData = accountSnapshot.data() || {};
              const storedPassword =
                  (accountData.temporaryPassword || "")
                      .toString();

              const alreadyProcessed =
                  accountData.mustChangePassword === false &&
                  storedPassword === newPassword;

              if (!alreadyProcessed) {
                transaction.set(
                    accountReference,
                    {
                      temporaryPassword: newPassword,
                      mustChangePassword: false,
                      passwordUpdatedAt:
                          admin.firestore.FieldValue.serverTimestamp(),
                      updatedAt:
                          admin.firestore.FieldValue.serverTimestamp(),
                    },
                    {merge: true},
                );
              }

              return {
                exists: true,
                email: (accountData.email || "").toString().trim(),
                prenom: (accountData.prenom || "Sauveteur")
                    .toString()
                    .trim(),
                nom: (accountData.nom || "").toString().trim(),
                civilite: (accountData.civilite || "")
                    .toString()
                    .trim(),
                territoireId: (accountData.territoireId || "")
                    .toString()
                    .trim(),
                sauveteurId: (accountData.sauveteurId || "")
                    .toString()
                    .trim(),
                sendEmail: !alreadyProcessed,
              };
            },
        );

        if (!accountResult.exists) {
          response.status(404).json({success: false});
          return;
        }

        const email = accountResult.email;
        const prenom = accountResult.prenom;
        let nom = accountResult.nom;
        let civiliteSource = accountResult.civilite;

        if ((!nom || !civiliteSource) &&
            accountResult.territoireId &&
            accountResult.sauveteurId) {
          const sauveteurSnapshot = await admin.firestore()
              .collection("territoires")
              .doc(accountResult.territoireId)
              .collection("sauveteurs")
              .doc(accountResult.sauveteurId)
              .get();

          if (sauveteurSnapshot.exists) {
            const sauveteurData = sauveteurSnapshot.data() || {};

            nom = nom || (sauveteurData.nom || "")
                .toString()
                .trim();

            civiliteSource = civiliteSource ||
                (sauveteurData.civilite || "")
                    .toString()
                    .trim();

            if (nom || civiliteSource) {
              await accountReference.set(
                  {
                    nom: nom,
                    civilite: civiliteSource,
                    updatedAt:
                        admin.firestore.FieldValue.serverTimestamp(),
                  },
                  {merge: true},
              );
            }
          }
        }

        nom = nom.toUpperCase();
        const civiliteValue = civiliteSource.toLowerCase();

        const civilite = ["madame", "mme"].includes(civiliteValue) ?
          "Madame" :
          ["monsieur", "m", "m."].includes(civiliteValue) ?
            "Monsieur" :
            civiliteSource;

        const destinataire = [civilite, nom]
            .filter((value) => value)
            .join(" ") || prenom;

        const destinataireHtml = nom ?
          `${civilite ?
            `<span style="font-weight:400 !important;">${
              escapeHtml(civilite)
            }</span> ` :
            ""}<span style="font-weight:700 !important;">${
            escapeHtml(nom)
          }</span>` :
          `<span style="font-weight:700 !important;">${
            escapeHtml(prenom)
          }</span>`;

        if (email && accountResult.sendEmail) {
          try {
            const transporter = nodemailer.createTransport({
              service: "gmail",
              auth: {
                user: SMTP_USER,
                pass: process.env.GMAIL_APP_PASSWORD,
              },
            });

            await sendSphotMail(transporter, {
              from: MAIL_FROM,
              to: email,
              replyTo: "contact@sphot.app",
              subject: "Mise à jour de votre compte SPHOT",
              html: `
<p style="font-weight:400 !important;">
        ${destinataireHtml} bonjour,
      </p>

      <p>
        Nous vous confirmons que le mot de passe de votre compte
        SPHOT a été modifié avec succès.
      </p>

<p>
  Si vous n'êtes pas à l'origine de cette modification,
  contactez immédiatement l'équipe SPHOT à l'adresse
  <a
    href="mailto:contact@sphot.app"
    style="color:#1e3a8a;font-weight:700;">
    contact@sphot.app
  </a>.
</p>

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p>
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
`,
              text: `${destinataire} bonjour,

Nous vous confirmons que votre mot de passe SPHOT
a été modifié avec succès.

Si vous n'êtes pas à l'origine de cette modification,
contactez immédiatement l'équipe SPHOT :
contact@sphot.app

À bientôt sur SPHOT,

L'équipe SPHOT`,
            });
          } catch (mailError) {
            console.error("Erreur email confirmation mot de passe:", mailError);
          }
        }

        response.status(200).json({
          success: true,
          duplicate: !accountResult.sendEmail,
        });
      } catch (error) {
        console.error("Erreur changement mot de passe sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.changeAdminPassword = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const newPassword = (request.body.newPassword || "")
            .toString()
            .trim();

        if (!login || !newPassword) {
          response.status(400).json({success: false});
          return;
        }

        const accountReference = admin.firestore()
            .collection("adminAccounts")
            .doc(login);

        const accountSnapshot = await accountReference.get();

        let email = "";
        let requestId = "";
        let accountData = {};

        if (accountSnapshot.exists) {
          accountData = accountSnapshot.data() || {};

          email = cleanValue(
              accountData.email || login,
              "",
          ).toLowerCase();

          requestId = cleanValue(
              accountData.requestId,
              "",
          );
        }

        /*
         * Données utilisées par défaut si la demande administrateur
         * d'origine n'est pas retrouvée.
         */
        let adminData = {
          profile: {
            civilite: accountData.civilite || "",
            nomAffiche: accountData.nom || "",
            prenomAffiche: accountData.prenom || "",
          },
          structure: {
            organisationDisplay:
                accountData.organisation || "",
            nom:
                accountData.organisation || "",
          },
          organisation:
              accountData.organisation || "",
          civilite:
              accountData.civilite || "",
          nomResponsable:
              accountData.nom || "",
          prenomResponsable:
              accountData.prenom || "",
        };

        /*
         * La demande administrateur contient les données complètes :
         * civilité, nom et organisme.
         */
        if (requestId) {
          const requestSnapshot = await admin.firestore()
              .collection("adminRequests")
              .doc(requestId)
              .get();

          if (requestSnapshot.exists) {
            adminData = requestSnapshot.data() || adminData;
          }
        }

        const greeting = buildAdminGreeting(adminData);

        const organisation =
            buildOrganisationDisplay(adminData);

        const loginUrl =
            `${SPHOT_LOGIN_URL}/#/professional-login`;

        await accountReference.set(
            {
              temporaryPassword: newPassword,
              mustChangePassword: false,
              passwordUpdatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        if (email) {
          try {
            const transporter = nodemailer.createTransport({
              service: "gmail",
              auth: {
                user: SMTP_USER,
                pass: process.env.GMAIL_APP_PASSWORD,
              },
            });

            await sendSphotMail(transporter, {
              from: MAIL_FROM,
              to: email,
              replyTo: "contact@sphot.app",
              subject:
                  "Mise à jour de votre compte administrateur SPHOT",

              text:
`${greeting}

Nous vous confirmons que le mot de passe de votre SPHOT ADMIN
pour ${organisation} a été modifié avec succès.

Vous pouvez désormais accéder à votre SPHOT ADMIN
afin de renseigner vos SPHOTS, vos sauveteurs et vos périodes
de surveillance.

Essai gratuit, sans engagement ni facturation.

La période d'essai gratuite de 8 jours ne commencera qu'une fois
vos SPHOTS, vos sauveteurs et vos périodes de surveillance
renseignés, puis l'essai activé.

Si vous n'êtes pas à l'origine de cette modification,
contactez immédiatement l'équipe SPHOT :
contact@sphot.app

Accéder à la page de connexion :
${loginUrl}

À bientôt sur SPHOT,

L'équipe SPHOT`,

              html: `
<p style="font-size:16px;line-height:1.6;">
      ${escapeHtml(greeting)}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Nous vous confirmons que le mot de passe de votre SPHOT ADMIN pour
      <strong>${escapeHtml(organisation)}</strong>
      a été modifié avec succès.
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Vous pouvez désormais accéder à votre SPHOT ADMIN
      afin de renseigner vos SPHOTS, vos sauveteurs et vos
      périodes de surveillance.
    </p>

    <p style="
      color:#dc2626;
      font-size:16px;
      line-height:1.6;
      font-weight:900;
    ">
      Essai gratuit, sans engagement ni facturation.
    </p>

    <div style="
      margin-top:20px;
      padding:16px;
      border-left:4px solid #f59e0b;
      border-radius:8px;
      background:#fff7df;
      font-size:14px;
      line-height:1.6;
    ">
      La période d'essai gratuite de 8 jours ne commencera
      qu'une fois vos SPHOTS, vos sauveteurs et vos périodes
      de surveillance renseignés, puis l'essai activé.
    </div>

    <div style="
      margin:20px 0;
      padding:16px;
      border-left:4px solid #dc2626;
      border-radius:8px;
      background:#fff1f1;
      font-size:14px;
      line-height:1.6;
    ">
      Si vous n'êtes pas à l'origine de cette modification,
contactez immédiatement l'équipe SPHOT à l'adresse
<a
  href="mailto:contact@sphot.app"
  style="color:#1e3a8a;font-weight:700;"
>
  contact@sphot.app
</a>.
    </div>

    <div style="text-align:center;margin:30px 0;">
      <a
        href="${loginUrl}"
        style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
"
      >
        SE CONNECTER À SPHOT ADMIN
      </a>
    </div>

    <p style="
      margin-top:28px;
      font-size:15px;
      line-height:1.6;
    ">
      À bientôt sur SPHOT,<br>
      <strong>L'équipe SPHOT</strong>
    </p>
`,
            });
          } catch (mailError) {
            console.error(
                "Erreur email confirmation mot de passe admin:",
                mailError,
            );
          }
        }

        response.status(200).json({success: true});
      } catch (error) {
        console.error(
            "Erreur changement mot de passe admin:",
            error,
        );

        response.status(500).json({success: false});
      }
    },
);

exports.deleteSauveteurAccount = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        if (!login) {
          response.status(400).json({success: false});
          return;
        }

        await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .delete();

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur suppression sauveteurAccount:", error);
        response.status(500).json({success: false});
      }
    },
);

/**
 * Retourne uniquement les données nécessaires aux marqueurs publicitaires.
 */
exports.getPublicAdvertisingSpots = onRequest(
    {
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "GET, OPTIONS");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "GET") {
        response.status(405).json({success: false});
        return;
      }

      try {
        const snapshot = await admin.firestore()
            .collection("advertiserRequests")
            .where("status", "in", ["approved", "active"])
            .limit(500)
            .get();

        const spots = snapshot.docs.map((document) => {
          const data = document.data() || {};
          const applicantLocation = data.applicantLocation || {};
          const approvedApplication = data.approvedApplication || {};
          const approvedLocation = approvedApplication.location || {};
          const advertisingSpot = data.advertisingSpot || {};
          const application = data.application || {};

          const latitude = Number([
            applicantLocation.latitude,
            approvedLocation.latitude,
            advertisingSpot.latitude,
            data.centerLat,
          ].find((value) => value !== undefined && value !== null));
          const longitude = Number([
            applicantLocation.longitude,
            approvedLocation.longitude,
            advertisingSpot.longitude,
            data.centerLng,
          ].find((value) => value !== undefined && value !== null));

          return {
            id: document.id,
            name: cleanValue(
                data.advertiserName ||
                data.companyName ||
                data.businessName ||
                data.organisation,
                "SPHOT PUBLICITAIRE",
            ),
            latitude: latitude,
            longitude: longitude,
            destinationUrl: cleanValue(
                data.destinationUrl || application.destinationUrl,
                "",
            ),
          };
        }).filter((spot) =>
          Number.isFinite(spot.latitude) &&
          Number.isFinite(spot.longitude) &&
          !(spot.latitude === 0 && spot.longitude === 0),
        );

        response.status(200).json({success: true, spots: spots});
      } catch (error) {
        console.error("Erreur chargement SPHOTs publicitaires:", error);
        response.status(500).json({success: false, spots: []});
      }
    },
);

exports.recordPublicClick = onRequest(
    {
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({success: false});
        return;
      }

      try {
        const payload = request.body || {};
        const territoireId = (payload.territoireId || "")
            .toString()
            .trim();
        const targetId = (payload.targetId || "").toString().trim();
        const targetType = (payload.targetType || "").toString().trim();
        const targetName = (payload.targetName || "")
            .toString()
            .trim()
            .slice(0, 160);
        const source = (payload.source || "").toString().trim();

        if (!territoireId || !targetId || !targetName) {
          response.status(400).json({success: false});
          return;
        }

        if (!["spot", "admin"].includes(targetType) ||
            !["web", "app"].includes(source)) {
          response.status(400).json({success: false});
          return;
        }

        const statId = Buffer.from(
            `${territoireId}|${targetType}|${targetId}`,
        ).toString("base64url");
        const dayKey = new Intl.DateTimeFormat(
            "fr-CA",
            {
              timeZone: "Europe/Paris",
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            },
        ).format(new Date());
        const sourceField = source === "app" ?
            "appClicks" :
            "webClicks";
        const increment =
            admin.firestore.FieldValue.increment(1);
        const updatedAt =
            admin.firestore.FieldValue.serverTimestamp();
        const statReference = admin.firestore()
            .collection("publicClickStats")
            .doc(statId);
        const dayReference = statReference
            .collection("daily")
            .doc(dayKey);
        const batch = admin.firestore().batch();

        batch.set(
            statReference,
            {
              territoireId: territoireId,
              targetId: targetId,
              targetType: targetType,
              targetName: targetName,
              totalClicks: increment,
              [sourceField]: increment,
              updatedAt: updatedAt,
            },
            {merge: true},
        );

        batch.set(
            dayReference,
            {
              date: dayKey,
              totalClicks: increment,
              [sourceField]: increment,
              updatedAt: updatedAt,
            },
            {merge: true},
        );

        await batch.commit();
        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur comptage clic public SPHOT:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.getPublicClickStats = onRequest(
    {
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).json({success: false});
        return;
      }

      try {
        const territoireId = ((request.body || {}).territoireId || "")
            .toString()
            .trim();

        if (!territoireId) {
          response.status(400).json({success: false});
          return;
        }

        const firestore = admin.firestore();
        const [snapshot, publicSpotsSnapshot] = await Promise.all([
          firestore
              .collection("publicClickStats")
              .where("territoireId", "==", territoireId)
              .get(),
          firestore
              .collection("publicSpots")
              .where("territoireId", "==", territoireId)
              .get(),
        ]);
        const publicSpotsById = new Map();

        publicSpotsSnapshot.docs.forEach((document) => {
          const data = document.data();
          const metadata = {
            typeSphot: (data.typeSphot || "").toString(),
            isPosteSecours: data.isPosteSecours === true,
          };
          const identifiers = [
            document.id,
            data.spotId,
            data.idSphot,
          ];

          identifiers.forEach((identifier) => {
            const normalizedIdentifier = (identifier || "")
                .toString()
                .trim();
            if (normalizedIdentifier) {
              publicSpotsById.set(normalizedIdentifier, metadata);
            }
          });
        });

        const statistics = snapshot.docs.map((document) => {
          const data = document.data();
          const targetId = (data.targetId || "").toString();
          const targetType = (data.targetType || "").toString();
          const spotMetadata = targetType === "spot" ?
            publicSpotsById.get(targetId) :
            null;

          return {
            id: document.id,
            targetId: targetId,
            targetType: targetType,
            targetName: (data.targetName || "").toString(),
            typeSphot: spotMetadata ? spotMetadata.typeSphot : "",
            isPosteSecours: spotMetadata ?
              spotMetadata.isPosteSecours :
              false,
            appClicks: Number(data.appClicks || 0),
            webClicks: Number(data.webClicks || 0),
            totalClicks: Number(data.totalClicks || 0),
          };
        });

        response.status(200).json({
          success: true,
          statistics: statistics,
        });
      } catch (error) {
        console.error("Erreur lecture statistiques SPHOT:", error);
        response.status(500).json({success: false});
      }
    },
);

/**
 * Transforme un nom en fragment d'identifiant stable et sans accent.
 *
 * @param {string} value Valeur à normaliser.
 * @return {string} Fragment utilisable dans un identifiant.
 */
function normalizeAdvertiserLoginPart(value) {
  return (value || "")
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "");
}

/**
 * Construit un UID Firebase stable sans exposer l'identifiant Firestore.
 *
 * @param {string} requestId Identifiant de la demande annonceur.
 * @return {string} UID réservé au compte Firebase de l'annonceur.
 */
function advertiserFirebaseUid(requestId) {
  const digest = crypto.createHash("sha256")
      .update(requestId)
      .digest("hex");
  return `advertiser_${digest}`;
}

/**
 * Réserve le premier identifiant annonceur disponible.
 *
 * @param {string} firstName Prénom du responsable.
 * @param {string} lastName Nom du responsable.
 * @param {string} requestId Identifiant de la demande.
 * @return {Promise<string>} Identifiant disponible.
 */
async function findAdvertiserLogin(firstName, lastName, requestId) {
  const normalizedFirstName = normalizeAdvertiserLoginPart(firstName);
  const normalizedLastName = normalizeAdvertiserLoginPart(lastName);
  const base = `${normalizedFirstName.substring(0, 1)}${normalizedLastName}` ||
    `annonceur${normalizeAdvertiserLoginPart(requestId).substring(0, 6)}`;

  for (let suffix = 1; suffix < 1000; suffix++) {
    const login = suffix === 1 ? base : `${base}${suffix}`;
    const snapshot = await admin.firestore()
        .collection("advertiserAccounts")
        .doc(login)
        .get();
    if (!snapshot.exists ||
        cleanValue((snapshot.data() || {}).requestId, "") === requestId) {
      return login;
    }
  }

  throw new Error("Impossible de générer un identifiant annonceur unique.");
}

/**
 * Conserve un même lien personnel entre réception et correction du dossier.
 * Le secret reste dans Secret Manager ; seul le hash du jeton est enregistré.
 * @param {Object} reference Référence Firestore du dossier.
 * @param {string} recipient Destinataire du mail.
 * @return {Promise<string>} URL personnelle valable 30 jours après cet envoi.
 */
async function advertiserRequestAccessUrl(reference, recipient) {
  const secret = process.env.ADVERTISER_ACCESS_LINK_SECRET;
  if (!secret) throw new Error("Secret des liens annonceurs absent.");
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new Error("Dossier annonceur introuvable.");
    const access = (snapshot.data() || {}).correctionAccess || {};
    const email = recipient.trim().toLowerCase();
    const nonce = access.recipient === email && access.nonce ?
      access.nonce : crypto.randomBytes(32).toString("hex");
    const token = crypto.createHmac("sha256", secret)
        .update(JSON.stringify(["advertiser-request-v1", reference.id, nonce]))
        .digest("hex");
    transaction.set(reference, {
      correctionAccess: {
        nonce,
        recipient: email,
        tokenHash: crypto.createHash("sha256").update(token).digest("hex"),
        expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + 30 * 24 * 60 * 60 * 1000,
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    }, {merge: true});
    return `${SPHOT_LOGIN_URL}/#/advertiser-correction` +
      `?requestId=${encodeURIComponent(reference.id)}` +
      `&token=${encodeURIComponent(token)}`;
  });
}

/** Envoie l'accusé de réception d'une candidature annonceur. */
exports.sendAdvertiserRequestAcknowledgement = onDocumentUpdated(
    {
      document: "advertiserRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD", "ADVERTISER_ACCESS_LINK_SECRET"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const afterData = event.data.after.data() || {};
      const acknowledgement = afterData.acknowledgementEmail || {};
      const status = cleanValue(afterData.status, "").toLowerCase();
      const emailStatus = cleanValue(acknowledgement.status, "")
          .toLowerCase();

      if (status !== "pending" || emailStatus !== "pending") {
        return;
      }

      const requestReference = event.data.after.ref;
      const recipient = cleanValue(
          acknowledgement.recipient ||
          afterData.contactEmail ||
          afterData.email,
          "",
      ).toLowerCase();

      if (!recipient) {
        await requestReference.set({
          acknowledgementEmail: {
            ...acknowledgement,
            status: "failed",
            error: "Adresse email absente.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        return;
      }

      const claimed = await admin.firestore().runTransaction(
          async (transaction) => {
            const snapshot = await transaction.get(requestReference);
            const freshEmail = (snapshot.data() || {})
                .acknowledgementEmail || {};
            if (cleanValue(freshEmail.status, "").toLowerCase() !==
                "pending") {
              return false;
            }
            transaction.set(requestReference, {
              acknowledgementEmail: {
                ...freshEmail,
                status: "sending",
                error: null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            }, {merge: true});
            return true;
          },
      );
      if (!claimed) return;

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {user: SMTP_USER, pass: process.env.GMAIL_APP_PASSWORD},
      });
      const greeting = buildAdvertiserGreeting(afterData);
      const company = cleanValue(
          afterData.advertiserName || afterData.organisation,
          "votre établissement",
      );

      try {
        const applicantUrl = await advertiserRequestAccessUrl(
            requestReference, recipient,
        );
        const mailResult = await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: recipient,
          subject:
              "SPHOT - Votre demande annonceur est en cours de traitement",
          text: `${greeting}

Votre demande de SPHOT PUBLICITAIRE pour ${company} a bien été reçue.

Elle est maintenant en cours de vérification par l'équipe SPHOT.
Votre dossier reste consultable, mais ne peut plus être modifié
pendant ce contrôle.

Accéder à ma demande : ${applicantUrl}
Ce lien personnel est valable 30 jours à compter de cet envoi.

Vous recevrez un nouveau message dès qu'une décision aura été prise.

À bientôt sur SPHOT,

L'équipe SPHOT`,
          html: `
<p>${escapeHtml(greeting)}</p>

      <p>
        Votre demande de SPHOT PUBLICITAIRE pour
        <strong>${escapeHtml(company)}</strong> a bien été reçue.
      </p>

      <div style="
        margin:26px 0;
        padding:20px;
        background:#f3f6fb;
        border:1px solid #1e3a8a;
        border-radius:14px;
      ">
        <div style="
          color:#607d8b;
          font-size:12px;
          font-weight:bold;
          text-transform:uppercase;
        ">
          État de la demande
        </div>
        <div style="
          margin-top:5px;
          color:#dc2626;
          font-size:21px;
          font-weight:bold;
        ">
          EN COURS DE VÉRIFICATION
        </div>
      </div>

      <p>
        Votre dossier reste consultable, mais ne peut plus être modifié
        pendant son contrôle par l'équipe SPHOT.
      </p>

      <p>
        Vous recevrez un nouveau message dès qu'une décision aura été prise.
      </p>

      <p style="
        margin-top:28px;
        padding:16px;
        background:#fff8e1;
        border-left:5px solid #ff9800;
        border-radius:8px;
      ">
        Ce message confirme le bon enregistrement de votre demande de
        SPHOT PUBLICITAIRE.
      </p>

      <div style="text-align:center;margin:30px 0;">
        <a href="${applicantUrl}" style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
">ACCÉDER À MA DEMANDE</a>
      </div>
      <p>Ce lien personnel est valable 30 jours à compter de cet envoi.</p>

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
`,
        });
        await requestReference.set({
          acknowledgementEmail: {
            ...acknowledgement,
            status: "sent",
            recipient: recipient,
            messageId: mailResult.messageId || null,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: null,
          },
        }, {merge: true});
      } catch (error) {
        await requestReference.set({
          acknowledgementEmail: {
            ...acknowledgement,
            status: "failed",
            recipient: recipient,
            error: error.message || error.toString(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        throw error;
      }
    },
);

/** Crée le compte annonceur et transmet ses identifiants après validation. */
exports.sendAdvertiserRequestApprovalEmail = onDocumentUpdated(
    {
      document: "advertiserRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const afterData = event.data.after.data() || {};
      const approvalEmail = afterData.approvalEmail || {};
      const status = cleanValue(afterData.status, "").toLowerCase();
      const emailStatus = cleanValue(approvalEmail.status, "").toLowerCase();
      if (status !== "approved" || emailStatus !== "pending") {
        return;
      }

      const requestReference = event.data.after.ref;
      const requestId = event.params.requestId;
      const recipient = cleanValue(
          approvalEmail.recipient ||
          afterData.contactEmail ||
          afterData.email,
          "",
      ).toLowerCase();
      if (!recipient) {
        await requestReference.set({
          approvalEmail: {
            ...approvalEmail,
            status: "failed",
            error: "Adresse email absente.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        return;
      }

      const claimed = await admin.firestore().runTransaction(
          async (transaction) => {
            const snapshot = await transaction.get(requestReference);
            const freshEmail = (snapshot.data() || {}).approvalEmail || {};
            if (cleanValue(freshEmail.status, "").toLowerCase() !==
                "pending") {
              return false;
            }
            transaction.set(requestReference, {
              approvalEmail: {
                ...freshEmail,
                status: "sending",
                error: null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            }, {merge: true});
            return true;
          },
      );
      if (!claimed) return;

      const firstName = cleanValue(afterData.contactFirstName, "");
      const lastName = cleanValue(afterData.contactLastName, "");
      const greeting = buildAdvertiserGreeting(afterData);
      const company = cleanValue(
          afterData.advertiserName || afterData.organisation,
          "votre établissement",
      );
      const existingLogin = cleanValue(afterData.accountLogin, "");
      const login = existingLogin ||
        await findAdvertiserLogin(firstName, lastName, requestId);
      const accountReference = admin.firestore()
          .collection("advertiserAccounts")
          .doc(login);
      const existingAccount = await accountReference.get();
      const accountData = existingAccount.data() || {};
      const firebaseUid = cleanValue(accountData.firebaseUid, "") ||
        advertiserFirebaseUid(requestId);
      const temporaryPassword = cleanValue(
          accountData.temporaryPassword,
          "",
      ) || generateAdminTemporaryPassword();

      await accountReference.set({
        login: login,
        email: recipient,
        temporaryPassword: temporaryPassword,
        mustChangePassword: accountData.mustChangePassword === false ?
          false : true,
        accountStatus: "ACTIVE",
        role: "ANNONCEUR",
        firebaseUid: firebaseUid,
        advertiserRequestId: requestId,
        requestId: requestId,
        prenom: firstName,
        nom: lastName,
        organisation: company,
        createdAt: existingAccount.exists ?
          accountData.createdAt :
          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await requestReference.set({
        accountLogin: login,
        accountStatus: "ACTIVE",
        firebaseUid: firebaseUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      let loginUrl = `${SPHOT_LOGIN_URL}/#/professional-login` +
        "?audience=advertiser";
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {user: SMTP_USER, pass: process.env.GMAIL_APP_PASSWORD},
      });

      try {
        if (accountData.mustChangePassword !== false) {
          const firstAccessToken = crypto.randomBytes(32).toString("hex");
          await accountReference.set({
            firstAccess: {
              tokenHash: crypto.createHash("sha256")
                  .update(firstAccessToken).digest("hex"),
              expiresAt: admin.firestore.Timestamp.fromMillis(
                  Date.now() + 30 * 24 * 60 * 60 * 1000,
              ),
            },
          }, {merge: true});
          loginUrl = `${SPHOT_LOGIN_URL}/#/advertiser-first-access` +
            `?login=${encodeURIComponent(login)}` +
            `&token=${encodeURIComponent(firstAccessToken)}`;
        }
        const mailResult = await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: recipient,
          subject: "SPHOT - Votre accès annonceur est approuvé",
          text: `${greeting}

Votre demande annonceur pour ${company} a été approuvée.

Votre SPHOT PUBLICITAIRE est désormais accessible. Utilisez l’identifiant
ci-dessous, il vous permettra de vous connecter à SPHOT avec le mot de passe
que vous aurez choisi.

Identifiant : ${login}

Lors de votre première connexion, vous devrez obligatoirement
renseigner votre mot de passe.

Connexion : ${loginUrl}

À bientôt sur SPHOT,

L'équipe SPHOT`,
          html: `
<p>${escapeHtml(greeting)}</p>

      <p>
        Votre demande de SPHOT PUBLICITAIRE pour
        <strong>${escapeHtml(company)}</strong> a été approuvée.
      </p>

      <div style="
        margin:26px 0;
        padding:20px;
        background:#eefaf2;
        border:1px solid #15803d;
        border-radius:14px;
      ">
        <div style="
          color:#607d8b;
          font-size:12px;
          font-weight:bold;
          text-transform:uppercase;
        ">
          Décision de l'équipe SPHOT
        </div>
        <div style="
          margin-top:5px;
          color:#15803d;
          font-size:21px;
          font-weight:bold;
        ">
          DEMANDE APPROUVÉE
        </div>
      </div>

      <p>
        Votre SPHOT PUBLICITAIRE est désormais accessible. Utilisez
        l’identifiant ci-dessous, il vous permettra de vous connecter
        à SPHOT avec le mot de passe que vous aurez choisi.
      </p>

      <div style="
        margin:26px 0;
        padding:20px;
        background:#f3f6fb;
        border:1px solid #1e3a8a;
        border-radius:14px;
      ">
        <p style="margin-top:0;">
          <strong>Identifiant :</strong><br>
          <span style="color:#1e3a8a;font-size:20px;font-weight:bold;">
            ${escapeHtml(login)}
          </span>
        </p>
      </div>

      <p style="
        margin-top:28px;
        padding:16px;
        background:#fff8e1;
        border-left:5px solid #ff9800;
        border-radius:8px;
      ">
        Lors de votre première connexion, vous devrez obligatoirement
        renseigner votre mot de passe.
      </p>

      <div style="text-align:center;margin:35px 0;">
        <a href="${loginUrl}" style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
">
          SE CONNECTER À SPHOT
        </a>
      </div>

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
`,
        });
        await requestReference.set({
          approvalEmail: {
            ...approvalEmail,
            status: "sent",
            recipient: recipient,
            messageId: mailResult.messageId || null,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: null,
          },
        }, {merge: true});
      } catch (error) {
        await requestReference.set({
          approvalEmail: {
            ...approvalEmail,
            status: "failed",
            recipient: recipient,
            error: error.message || error.toString(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        throw error;
      }
    },
);

/** Informe l'annonceur d'une demande de correction ou d'un refus. */
exports.sendAdvertiserReviewEmail = onDocumentUpdated(
    {
      document: "advertiserRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD", "ADVERTISER_ACCESS_LINK_SECRET"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const afterData = event.data.after.data() || {};
      const status = cleanValue(afterData.status, "").toLowerCase();
      const assetChangeStatus = cleanValue(
          (afterData.assetChangeRequest || {}).status,
          "",
      ).toLowerCase();
      const fieldName = status === "changes_requested" ||
          assetChangeStatus === "authorized" ?
        "changeRequestEmail" :
        status === "rejected" || assetChangeStatus === "rejected" ?
          "rejectionEmail" : "";
      if (!fieldName) return;
      const emailData = afterData[fieldName] || {};
      if (cleanValue(emailData.status, "").toLowerCase() !== "pending") {
        return;
      }

      const requestReference = event.data.after.ref;
      const recipient = cleanValue(
          emailData.recipient || afterData.contactEmail || afterData.email,
          "",
      ).toLowerCase();
      const reason = cleanValue(
          emailData.reason || (afterData.review || {}).reason,
          "",
      );
      if (!recipient) {
        await requestReference.set({
          [fieldName]: {
            ...emailData,
            status: "failed",
            error: "Adresse email absente.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        return;
      }

      const claimed = await admin.firestore().runTransaction(
          async (transaction) => {
            const snapshot = await transaction.get(requestReference);
            const freshEmail = (snapshot.data() || {})[fieldName] || {};
            if (cleanValue(freshEmail.status, "").toLowerCase() !==
                "pending") {
              return false;
            }
            transaction.set(requestReference, {
              [fieldName]: {
                ...freshEmail,
                status: "sending",
                error: null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            }, {merge: true});
            return true;
          },
      );
      if (!claimed) return;

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {user: SMTP_USER, pass: process.env.GMAIL_APP_PASSWORD},
      });
      const greeting = buildAdvertiserGreeting(afterData);
      const isCorrection = status === "changes_requested" ||
        assetChangeStatus === "authorized";
      try {
        const applicantUrl = isCorrection ?
          await advertiserRequestAccessUrl(requestReference, recipient) :
          SPHOT_LOGIN_URL;
        const mailResult = await sendSphotMail(transporter, {
          from: MAIL_FROM,
          to: recipient,
          subject: isCorrection ?
            "SPHOT - Une modification de votre demande est nécessaire" :
            "SPHOT - Décision concernant votre demande annonceur",
          text: `${greeting}

${isCorrection ?
  "Une modification est nécessaire avant validation." :
  "Votre demande de SPHOT PUBLICITAIRE n'a pas été retenue."}

Motif : ${reason}

${isCorrection ?
  `Ce lien personnel vous permet de retrouver les renseignements déjà
enregistrés, d'effectuer la modification demandée, puis de transmettre
à nouveau votre dossier. Il reste valable pendant 30 jours.

Accéder à votre demande : ${applicantUrl}` :
  "Vous pouvez contacter l'équipe SPHOT pour toute précision."}

À bientôt sur SPHOT,

L'équipe SPHOT`,
          html: `
<p>${escapeHtml(greeting)}</p>

      <p>
        ${isCorrection ?
          "Une modification est nécessaire avant validation de votre " +
          "demande de SPHOT PUBLICITAIRE." :
          "Votre demande de SPHOT PUBLICITAIRE n'a pas été retenue."}
      </p>

      <div style="
        margin:26px 0;
        padding:20px;
        background:#fff1f2;
        border:1px solid #dc2626;
        border-radius:14px;
      ">
        <div style="
          color:#607d8b;
          font-size:12px;
          font-weight:bold;
          text-transform:uppercase;
        ">
          Décision de l'équipe SPHOT
        </div>
        <div style="
          margin-top:5px;
          color:#dc2626;
          font-size:21px;
          font-weight:bold;
        ">
          ${isCorrection ? "MODIFICATION DEMANDÉE" : "DEMANDE REFUSÉE"}
        </div>
      </div>

      <div style="
        margin:26px 0;
        padding:18px;
        background:#f3f6fb;
        border-left:5px solid #1e3a8a;
        border-radius:8px;
      ">
        <strong>Motif communiqué par l'équipe SPHOT :</strong><br>
        ${escapeHtml(reason)}
      </div>

      ${isCorrection ? `
        <p>
          Ce lien personnel vous permet de retrouver les renseignements
          déjà enregistrés afin d'effectuer la modification demandée, puis
          de transmettre à nouveau le dossier. Il reste valable 30 jours.
        </p>

        <div style="text-align:center;margin:35px 0;">
          <a href="${applicantUrl}" style="
display:inline-block;
padding:15px 28px;
border-radius:14px;
background:#1e3a8a;
color:#ffffff;
text-decoration:none;
font-size:16px;
font-weight:900;
">
            ACCÉDER À MA DEMANDE
          </a>
        </div>
      ` : `
        <p>
          Vous pouvez contacter l'équipe SPHOT pour toute précision.
        </p>
      `}

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
`,
        });
        await requestReference.set({
          [fieldName]: {
            ...emailData,
            status: "sent",
            messageId: mailResult.messageId || null,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            error: null,
          },
        }, {merge: true});
      } catch (error) {
        await requestReference.set({
          [fieldName]: {
            ...emailData,
            status: "failed",
            error: error.message || error.toString(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
        throw error;
      }
    },
);

/** Ouvre un dossier en consultation ou correction selon son statut courant. */
exports.redeemAdvertiserCorrectionAccess = onRequest(
    {region: "us-central1", cors: true},
    async (request, response) => {
      if (request.method !== "POST") {
        response.status(405).json({error: "Méthode non autorisée."});
        return;
      }

      const requestId = cleanValue(request.body && request.body.requestId, "");
      const suppliedToken = cleanValue(request.body && request.body.token, "");
      if (!requestId || !suppliedToken) {
        response.status(400).json({error: "Lien de correction incomplet."});
        return;
      }

      let modificationRequested = false;
      try {
        const reference = admin.firestore()
            .collection("advertiserRequests")
            .doc(requestId);
        const snapshot = await reference.get();
        const data = snapshot.data() || {};
        const access = data.correctionAccess || {};
        const storedHash = cleanValue(access.tokenHash, "");
        const suppliedHash = crypto
            .createHash("sha256")
            .update(suppliedToken)
            .digest("hex");
        const expiresAt = access.expiresAt && access.expiresAt.toMillis ?
          access.expiresAt.toMillis() : 0;
        const status = cleanValue(data.status, "").toLowerCase();
        const assetStatus = cleanValue(
            (data.assetChangeRequest || {}).status,
            "",
        ).toLowerCase();
        const accessible = status === "pending" ||
          status === "changes_requested" ||
          assetStatus === "authorized";
        const hashesMatch = storedHash.length === suppliedHash.length &&
          crypto.timingSafeEqual(
              Buffer.from(storedHash, "utf8"),
              Buffer.from(suppliedHash, "utf8"),
          );

        if (!snapshot.exists || !hashesMatch || expiresAt <= Date.now() ||
            !accessible) {
          response.status(403).json({
            error: "Ce lien est invalide, expiré ou n'autorise plus " +
              "l'accès au dossier.",
          });
          return;
        }

        modificationRequested = status === "changes_requested" ||
          assetStatus === "authorized";
        const firebaseToken = await admin.auth().createCustomToken(requestId, {
          role: "advertiser_candidate",
          advertiserRequestId: requestId,
        });
        response.status(200).json({
          token: firebaseToken, requestId, modificationRequested,
        });
      } catch (error) {
        console.error("Échange accès correction annonceur impossible", error);
        response.status(500).json({
          error: "Session temporairement indisponible.",
          modificationRequested,
        });
      }
    },
);

/** Ouvre la première connexion à partir du lien personnel du mail. */
exports.redeemAdvertiserFirstAccess = onRequest(
    {region: "us-central1", cors: true},
    async (request, response) => {
      if (request.method !== "POST") {
        response.status(405).json({error: "Méthode non autorisée."});
        return;
      }
      const login = cleanValue((request.body || {}).login, "").toLowerCase();
      const token = cleanValue((request.body || {}).token, "");
      if (!login || login.includes("/") || !token) {
        response.status(400).json({error: "Lien incomplet ou invalide."});
        return;
      }
      try {
        const account = await admin.firestore()
            .collection("advertiserAccounts").doc(login).get();
        const data = account.data() || {};
        const access = data.firstAccess || {};
        const storedHash = cleanValue(access.tokenHash, "");
        const suppliedHash = crypto.createHash("sha256")
            .update(token).digest("hex");
        const matches = storedHash.length === suppliedHash.length &&
          crypto.timingSafeEqual(Buffer.from(storedHash),
              Buffer.from(suppliedHash));
        const expiry = access.expiresAt && access.expiresAt.toMillis ?
          access.expiresAt.toMillis() : 0;
        const requestId = cleanValue(
            data.advertiserRequestId || data.requestId, "",
        );
        if (!account.exists || data.accountStatus !== "ACTIVE" ||
            data.mustChangePassword !== true || !matches ||
            expiry <= Date.now() || !requestId) {
          response.status(403).json({
            error: "Ce lien est expiré, remplacé ou déjà utilisé. " +
              "Contactez l’équipe SPHOT si nécessaire.",
          });
          return;
        }
        const dossier = await admin.firestore()
            .collection("advertiserRequests").doc(requestId).get();
        const identity = dossier.data() || {};
        if (cleanValue(identity.status, "").toLowerCase() !== "approved") {
          response.status(403).json({error: "Demande non approuvée."});
          return;
        }
        const uid = cleanValue(data.firebaseUid, "") ||
          advertiserFirebaseUid(requestId);
        const firebaseToken = await admin.auth().createCustomToken(uid, {
          role: "ANNONCEUR",
          advertiserRequestId: requestId,
          firstAccessHash: storedHash,
        });
        response.status(200).json({
          firebaseToken,
          advertiserRequestId: requestId,
          login,
          civilite: cleanValue(
              identity.contactCivility || identity.civilite, "",
          ),
          nom: cleanValue(data.nom, ""),
        });
      } catch (error) {
        console.error("Première connexion annonceur impossible:", error);
        response.status(500).json({
          error: "Session temporairement indisponible.",
        });
      }
    },
);

/** Connexion des comptes annonceurs approuvés. */
exports.loginAdvertiser = onRequest(
    {cpu: 1, memory: "256MiB"},
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");
      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = cleanValue((request.body || {}).login, "")
            .toLowerCase();
        const password = cleanValue((request.body || {}).password, "");
        if (!login || !password) {
          response.status(400).json({success: false});
          return;
        }
        const snapshot = await admin.firestore()
            .collection("advertiserAccounts")
            .doc(login)
            .get();
        const data = snapshot.data() || {};
        if (!snapshot.exists || data.accountStatus !== "ACTIVE" ||
            cleanValue(data.temporaryPassword, "") !== password) {
          response.status(401).json({success: false});
          return;
        }
        const advertiserRequestId = cleanValue(
            data.advertiserRequestId || data.requestId,
            "",
        );
        if (!advertiserRequestId) {
          response.status(409).json({success: false});
          return;
        }
        const firebaseUid = cleanValue(data.firebaseUid, "") ||
          advertiserFirebaseUid(advertiserRequestId);
        const firebaseToken = await admin.auth().createCustomToken(
            firebaseUid,
            {
              role: "ANNONCEUR",
              advertiserRequestId: advertiserRequestId,
            },
        );
        await snapshot.ref.set({
          firebaseUid: firebaseUid,
          lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        response.status(200).json({
          success: true,
          advertiserRequestId: advertiserRequestId,
          firebaseToken: firebaseToken,
          userRole: "ANNONCEUR",
          mustChangePassword: data.mustChangePassword === true,
          prenom: cleanValue(data.prenom, ""),
          nom: cleanValue(data.nom, ""),
        });
      } catch (error) {
        console.error("Erreur login annonceur:", error);
        response.status(500).json({success: false});
      }
    },
);

/** Changement obligatoire du mot de passe annonceur. */
exports.changeAdvertiserPassword = onRequest(
    {cpu: 1, memory: "256MiB"},
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set(
          "Access-Control-Allow-Headers",
          "Content-Type, Authorization",
      );
      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const authorization = cleanValue(
            request.get("Authorization"),
            "",
        );
        if (!authorization.startsWith("Bearer ")) {
          response.status(401).json({success: false});
          return;
        }
        const idToken = authorization.substring("Bearer ".length).trim();
        const session = await admin.auth().verifyIdToken(idToken);
        if (session.role !== "ANNONCEUR" ||
            !cleanValue(session.advertiserRequestId, "")) {
          response.status(403).json({success: false});
          return;
        }
        const login = cleanValue((request.body || {}).login, "")
            .toLowerCase();
        const newPassword = cleanValue((request.body || {}).newPassword, "");
        if (!login || !newPassword) {
          response.status(400).json({success: false});
          return;
        }
        const reference = admin.firestore()
            .collection("advertiserAccounts")
            .doc(login);
        const changed = await admin.firestore().runTransaction(async (tx) => {
          const snapshot = await tx.get(reference);
          const accountData = snapshot.data() || {};
          const accountRequestId = cleanValue(
              accountData.advertiserRequestId || accountData.requestId, "",
          );
          if (!snapshot.exists || accountData.accountStatus !== "ACTIVE" ||
              accountRequestId !== session.advertiserRequestId) return false;
          if (session.firstAccessHash) {
            const access = accountData.firstAccess || {};
            const expiry = access.expiresAt && access.expiresAt.toMillis ?
              access.expiresAt.toMillis() : 0;
            if (accountData.mustChangePassword !== true ||
                access.tokenHash !== session.firstAccessHash ||
                expiry <= Date.now()) return false;
          }
          tx.set(reference, {
            temporaryPassword: newPassword,
            mustChangePassword: false,
            firstAccess: admin.firestore.FieldValue.delete(),
            passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          return true;
        });
        if (!changed) {
          response.status(403).json({success: false});
          return;
        }
        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur changement mot de passe annonceur:", error);
        response.status(500).json({success: false});
      }
    },
);

/** Suit les demandes de modification des éléments approuvés. */
exports.sendAdvertiserAssetChangeEmail = onDocumentUpdated(
    {
      document: "advertiserRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD", "ADVERTISER_ACCESS_LINK_SECRET"],
      retry: true,
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.data() || {};
      const data = event.data.after.data() || {};
      const previous = (before.assetChangeRequest || {}).status;
      const status = (data.assetChangeRequest || {}).status;
      if (data.status !== "approved" || previous === status) return;
      const messages = {
        pending: "Votre demande de modification du visuel ou de la position " +
          "a été reçue. L'équipe SPHOT va l'examiner.",
        authorized: "L'équipe SPHOT vous autorise à proposer un nouveau " +
          "visuel ou une nouvelle position. Transmettez vos modifications " +
          "pour approbation.",
        submitted: "Votre proposition de modification du visuel ou de la " +
          "position a été reçue. Elle est en attente d'approbation " +
          "par l'équipe SPHOT.",
        approved: "L'équipe SPHOT a approuvé votre modification du visuel " +
          "ou de la position. Les éléments approuvés sont disponibles " +
          "dans votre espace annonceur.",
        rejected: "L'équipe SPHOT n'a pas approuvé votre modification. " +
          "Les éléments précédemment approuvés sont conservés.",
      };
      if (!messages[status]) return;
      const labels = {
        pending: "DEMANDE DE MODIFICATION REÇUE",
        authorized: "MODIFICATION AUTORISÉE",
        submitted: "PROPOSITION À APPROUVER",
        approved: "MODIFICATION APPROUVÉE",
        rejected: "MODIFICATION REFUSÉE",
      };
      const recipient = cleanValue(data.contactEmail || data.email, "");
      // Les décisions détaillées sont déjà envoyées par le circuit existant.
      const existingReview = status === "authorized" ?
        data.changeRequestEmail : status === "rejected" ?
          data.rejectionEmail : null;
      const reviewQueued = existingReview &&
        existingReview.status === "pending";
      const recipients = [{kind: "team", email: SMTP_USER}];
      if (recipient && !reviewQueued) {
        recipients.push({kind: "advertiser", email: recipient});
      }
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {user: SMTP_USER, pass: process.env.GMAIL_APP_PASSWORD},
      });
      for (const target of recipients) {
        const key = crypto.createHash("sha256")
            .update(event.id + ":" + target.kind).digest("hex");
        const ledger = event.data.after.ref
            .collection("assetChangeNotifications").doc(key);
        const claimed = await admin.firestore().runTransaction(async (tx) => {
          const snapshot = await tx.get(ledger);
          const saved = snapshot.data() || {};
          if (saved.status === "sent" || saved.status === "sending") {
            return false;
          }
          tx.set(ledger, {
            status: "sending",
            recipient: target.email,
            decision: status,
            eventId: event.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          return true;
        });
        if (!claimed) continue;
        try {
          let text;
          if (target.kind === "team") {
            text = "Suivi d'une modification annonceur.\n\n" +
              "Dossier : " + event.params.requestId + "\n" +
              "Annonceur : " + cleanValue(data.advertiserName, "") + "\n" +
              "Contact : " + recipient + "\n" +
              "État : " + labels[status] + "\n\n" +
              "Consultez le dossier dans votre espace SPHOT pour " +
              "examiner la demande ou retrouver la décision.";
          } else {
            let url = "https://sphot.app/#/professional-login" +
              "?audience=advertiser";
            if (status === "authorized") {
              url = await advertiserRequestAccessUrl(
                  event.data.after.ref, recipient,
              );
            }
            const reason = cleanValue(
                (data.assetChangeRequest || {}).reason, "",
            );
            text = buildAdvertiserGreeting(data) + "\n\n" +
              messages[status] + (reason ? "\n\nMotif : " + reason : "") +
              "\n\nAccéder à votre espace : " + url +
              "\n\nL'équipe SPHOT";
          }
          const result = await sendSphotMail(transporter, {
            from: MAIL_FROM,
            to: target.email,
            subject: "SPHOT - " + labels[status],
            text: text,

          });
          await ledger.set({
            status: "sent",
            messageId: result.messageId || null,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        } catch (error) {
          await ledger.set({
            status: "failed",
            error: error.message || String(error),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          throw error;
        }
      }
    },
);

Object.assign(exports, require("./admin_workflow"));

