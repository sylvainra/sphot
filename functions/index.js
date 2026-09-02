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
 * Vérifie qu'au moins un administrateur du territoire a été approuvé
 * par le Super Admin.
 *
 * @param {string} territoireId Identifiant du territoire.
 * @return {Promise<boolean>}
 */
async function isTerritoryPublic(territoireId) {
  const db = admin.firestore();
  const [adminsSnapshot, requestsSnapshot] = await Promise.all([
    db.collection("admins")
        .where("territoireId", "==", territoireId)
        .get(),
    db.collection("adminRequests")
        .where("territoire.territoireId", "==", territoireId)
        .get(),
  ]);
  const approvedAdmin = adminsSnapshot.docs.some((document) => {
    return document.data().accessStatus === "approved";
  });
  const approvedRequest = requestsSnapshot.docs.some((document) => {
    return isApprovedAdminRequest(document.data());
  });
  return approvedAdmin || approvedRequest;
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
    return `Bonjour ${civilite} ${nom},`;
  }

  if (nom) {
    return `Bonjour ${nom},`;
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
    return `Bonjour ${civility} ${lastName},`;
  }

  if (lastName) {
    return `Bonjour ${lastName},`;
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
          top: 34,
          bottom: 34,
          left: 42,
          right: 42,
        },
        info: {
          Title: "Accusé de réception d'une demande d'accès SPHOT",
          Author: "SPHOT",
          Subject: requestNumber,
        },
      });

      const chunks = [];

      doc.on("data", (chunk) => chunks.push(chunk));

      doc.on("end", () => {
        resolve(Buffer.concat(chunks));
      });

      doc.on("error", reject);

      const blue = "#1E3A8A";
      const red = "#DC2626";
      const dark = "#263238";
      const grey = "#607D8B";
      const lightBlue = "#F3F6FB";

      const contentWidth =
          doc.page.width -
          doc.page.margins.left -
          doc.page.margins.right;

      /**
       * Affiche un titre de section compact.
       *
       * @param {string} title Titre à afficher.
       */
      const sectionTitle = (title) => {
        const left = doc.page.margins.left;
        const iconSize = 18;
        const titleY = doc.y + 8;
        const titleX = left + iconSize + 10;

        doc
            .circle(
                left + (iconSize / 2),
                titleY + (iconSize / 2),
                iconSize / 2,
            )
            .lineWidth(1)
            .strokeColor(red)
            .stroke();

        doc
            .font("Helvetica-Bold")
            .fontSize(9)
            .fillColor(red)
            .text(
                "S",
                left,
                titleY + 1,
                {
                  width: iconSize,
                  align: "center",
                },
            );

        doc
            .font("Helvetica-Bold")
            .fontSize(10)
            .fillColor(red)
            .text(
                title.toUpperCase(),
                titleX,
                titleY + 1,
                {
                  width: contentWidth - iconSize - 10,
                  align: "left",
                },
            );

        const lineY = titleY + iconSize + 4;

        doc
            .strokeColor(blue)
            .lineWidth(0.8)
            .moveTo(titleX, lineY)
            .lineTo(
                doc.page.width - doc.page.margins.right,
                lineY,
            )
            .stroke();

        doc.x = left;
        doc.y = lineY + 8;
      };

      /**
       * Affiche une ligne d'information compacte.
       *
       * @param {string} label Libellé du champ.
       * @param {*} value Valeur du champ.
       */
      const informationLine = (label, value) => {
        const labelWidth = 105;
        const startY = doc.y;
        const startX = doc.page.margins.left + 12;

        doc
            .font("Helvetica-Bold")
            .fontSize(8.2)
            .fillColor(blue)
            .text(
                `${label}`,
                startX,
                startY,
                {
                  width: labelWidth,
                  align: "left",
                },
            );

        doc
            .font("Helvetica")
            .fontSize(8.6)
            .fillColor(dark)
            .text(
                cleanValue(value),
                startX + labelWidth + 4,
                startY,
                {
                  width: contentWidth - labelWidth - 8,
                  align: "left",
                },
            );

        doc.y = startY + 13;
      };

      doc
          .font("Helvetica-Bold")
          .fontSize(26)
          .fillColor(red)
          .text("SPHOT", {
            align: "center",
          });

      doc
          .moveDown(0.08)
          .font("Helvetica-Bold")
          .fontSize(12)
          .fillColor(blue)
          .text(
              "ACCUSÉ DE RÉCEPTION D'UNE DEMANDE D'ACCÈS " +
              "ADMINISTRATEUR",
              {
                align: "center",
                lineGap: 0,
              },
          );

      doc.moveDown(0.35);

      const summaryTop = doc.y;

      doc
          .roundedRect(
              doc.page.margins.left,
              summaryTop,
              contentWidth,
              82,
              10,
          )
          .fillAndStroke(lightBlue, blue);

      doc
          .font("Helvetica-Bold")
          .fontSize(7.8)
          .fillColor(blue)
          .text(
              "NUMÉRO DE DEMANDE",
              doc.page.margins.left + 13,
              summaryTop + 18,
          );

      doc
          .font("Helvetica-Bold")
          .fontSize(12)
          .fillColor(red)
          .text(
              requestNumber,
              doc.page.margins.left + 13,
              summaryTop + 42,
          );

      doc
          .font("Helvetica")
          .fontSize(6.8)
          .fillColor(grey)
          .text(
              `Demande transmise le ${formatFrenchDate(createdAt)}`,
              doc.page.margins.left + 13,
              summaryTop + 69,
          );

      doc.y = summaryTop + 100;

      doc
          .font("Helvetica")
          .fontSize(8.5)
          .fillColor(blue)
          .text(
              "Votre demande d'accès au portail d'administration SPHOT " +
        "a bien été enregistrée.",
              {
                align: "center",
                lineGap: 0,
              },
          );

      sectionTitle("Demandeur");

      informationLine("Nom", profile.nomAffiche);
      informationLine("Prénom", profile.prenomAffiche);
      informationLine("Fonction", profile.fonction);
      informationLine("Email", profile.email);
      informationLine("Téléphone", profile.telephone);

      sectionTitle("Identité transmise par ProConnect");

      informationLine("Nom", proConnect.nom);
      informationLine("Prénom", proConnect.prenom);
      informationLine("Email", proConnect.email);
      informationLine("Organisation", proConnect.organisation);
      informationLine("SIRET", proConnect.siret);
      informationLine("SIREN", proConnect.siren);

      sectionTitle("Structure");

      informationLine("Nom", structure.nom);
      informationLine("Type", structure.type);
      informationLine("SIRET", structure.siret);
      informationLine("SIREN", structure.siren);

      sectionTitle("Territoire");

      informationLine("Pays", territoire.pays);
      informationLine("Région", territoire.region);
      informationLine("Département", territoire.departement);
      informationLine("Ville", territoire.ville);

      sectionTitle("Votre essai SPHOT");

      doc
          .font("Helvetica-Bold")
          .fontSize(9.6)
          .fillColor(red)
          .text(
              "Essai gratuit, sans engagement ni facturation.",
              {
                lineGap: 0,
              },
          );

      doc
          .moveDown(0.08)
          .font("Helvetica")
          .fontSize(8.1)
          .fillColor(blue)
          .text(
              "Après validation de votre demande par l'équipe SPHOT, " +
              "vous pourrez accéder au portail d'administration SPHOT " +
              "afin de créer vos SPHOTS, vos sauveteurs et vos périodes " +
              "de surveillance.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.12)
          .text(
              "Vous recevrez prochainement, par courrier électronique, " +
              "une réponse vous informant de la décision prise concernant " +
              "votre demande.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.12)
          .text(
              "La période d'essai gratuite de 8 jours débutera uniquement " +
              "lorsque votre configuration sera complète et que l'essai " +
              "aura été activé.",
              {
                lineGap: 1,
              },
          );

      sectionTitle("Conditions acceptées");

      const acceptedDocuments =
          trialRequest.acceptedDocuments || {};

      informationLine(
          "Habilitation à représenter la structure",
          trialRequest.certifyRepresentative === true ?
            "Oui" :
            "Non",
      );

      informationLine(
          "Conditions Générales d'Utilisation",
          acceptedDocuments.cgu === true ?
            "Acceptées" :
            "Non acceptées",
      );

      informationLine(
          "Politique de confidentialité",
          acceptedDocuments.privacy === true ?
            "Acceptée" :
            "Non acceptée",
      );

      informationLine(
          "Traitement des données personnelles",
          acceptedDocuments.rgpd === true ?
            "Accepté" :
            "Non accepté",
      );

      informationLine(
          "Version des documents",
          acceptedDocuments.version,
      );

      sectionTitle("Information importante");

      doc
          .font("Helvetica")
          .fontSize(8)
          .fillColor(blue)
          .text(
              "Ce document confirme uniquement la bonne réception et " +
              "l'enregistrement de votre demande d'accès au portail " +
              "d'administration SPHOT.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.05)
          .text(
              "Il ne vaut ni acceptation, ni refus de votre demande et " +
              "ne confère, à ce stade, aucun droit d'accès au portail.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.05)
          .text(
              "La période d'essai gratuite n'est pas encore ouverte et " +
              "aucune facturation ne peut intervenir avant la validation " +
              "de votre demande et l'activation effective de votre essai.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.70)
          .font("Helvetica")
          .fontSize(6.8)
          .fillColor(grey)
          .text(
              `Document généré automatiquement par SPHOT — ${requestNumber}`,
              {
                align: "center",
                lineGap: 0,
              },
          );

      doc.end();
    } catch (error) {
      reject(error);
    }
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

      const fileName =
          `SPHOT_Accuse_Reception_${requestNumber}.pdf`;

      const storagePath =
          `adminRequests/${requestId}/documents/${fileName}`;

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

        const greeting = buildAdminGreeting(data);

        const organisation =
            buildOrganisationDisplay(data);

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: recipientEmail,
          subject:
              "SPHOT - Confirmation de votre demande d'accès administrateur",

          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
">
  <div style="
    max-width:620px;
    margin:auto;
    background:#ffffff;
    border-radius:18px;
    overflow:hidden;
    border:1px solid #d9e2ec;
    box-shadow:0 4px 12px rgba(0,0,0,.08);
  ">
    <div style="padding:30px 30px 18px;text-align:center;">
      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;"
        >
      </a>
    </div>

    <div style="
      padding:0 34px 34px;
      color:#263238;
      font-size:16px;
      line-height:1.6;
    ">
      <p>
  ${escapeHtml(greeting)}
</p>

      <p>
        Votre demande d'accès au portail d'administration SPHOT
        pour <strong>${organisation}</strong> a bien été enregistrée.
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
          Numéro de demande
        </div>

        <div style="
          margin-top:5px;
          color:#dc2626;
          font-size:21px;
          font-weight:bold;
        ">
          ${requestNumber}
        </div>
      </div>

      <p style="
        color:#dc2626;
        font-size:18px;
        font-weight:bold;
      ">
        Essai gratuit, sans engagement ni facturation.
      </p>

      <p>
        Après validation de votre demande par l'équipe SPHOT,
vous pourrez accéder au portail d'administration SPHOT
afin de créer vos SPHOTS, vos sauveteurs et vos périodes
de surveillance.

Vous recevrez prochainement, par courrier électronique,
une réponse vous informant de la décision prise concernant
votre demande.
      </p>

      <p>
        La période d'essai gratuite de 8 jours débutera uniquement
lorsque votre configuration sera complète et que l'essai
aura été activé.
      </p>

      <p>
        Votre accusé de réception est joint à ce message.
      </p>

      <p style="
        margin-top:28px;
        padding:16px;
        background:#fff8e1;
        border-left:5px solid #ff9800;
        border-radius:8px;
      ">
        Ce message confirme l'enregistrement de votre demande.
        Aucun essai ni aucune facturation ne sont en cours à ce stade.
      </p>

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
    </div>
  </div>
</div>
`,

          text:
`${greeting}

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} a bien été enregistrée.

Numéro de demande : ${requestNumber}

Essai gratuit, sans engagement ni facturation.

Après validation de votre demande, vous pourrez accéder au portail
afin de créer vos SPHOTS, vos sauveteurs et vos périodes de surveillance.

La période d'essai de 8 jours ne commencera qu'une fois
ces informations renseignées et l'essai activé.

Votre accusé de réception est joint à ce message.

Ce message confirme l'enregistrement de votre demande.
Aucun essai ni aucune facturation ne sont en cours à ce stade.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          attachments: [
            {
              filename: fileName,
              content: pdfBuffer,
              contentType: "application/pdf",
            },
          ],
        });

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
                    "Accusé de réception généré et envoyé",
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
            "Accusé de réception généré et envoyé:",
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
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject:
              "SPHOT - Votre demande d'accès administrateur a été acceptée",

          text:
`${greeting}

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} a été acceptée.

Référence administrative : ${requestNumber}

VOS IDENTIFIANTS DE CONNEXION

Identifiant :
${login}

Mot de passe provisoire :
${temporaryPassword}

Lors de votre première connexion, vous devrez obligatoirement
choisir un nouveau mot de passe.

Accéder à la page de connexion :
${loginUrl}

Vous pourrez ensuite renseigner vos SPHOTS, vos sauveteurs
et vos périodes de surveillance.

Essai gratuit, sans engagement ni facturation.

La période d'essai de 8 jours ne commencera qu'une fois la
configuration complète et l'essai activé.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
  color:#172033;
">
  <div style="
    max-width:640px;
    margin:0 auto;
    background:#ffffff;
    border-radius:18px;
    padding:34px;
    box-shadow:0 8px 26px rgba(30,58,138,0.12);
  ">
    <div style="padding:0 0 18px;text-align:center;">
      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;"
        >
      </a>

      <div style="
        margin-top:18px;
        color:#1e3a8a;
        font-size:18px;
        font-weight:900;
        line-height:1.35;
        text-transform:uppercase;
      ">
        DEMANDE D’ACCÈS AU PORTAIL SPHOT
      </div>
    </div>

    <p style="font-size:16px;line-height:1.6;">
      ${escapeHtml(greeting)}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Votre demande d'accès au portail d'administration SPHOT
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
        SE CONNECTER À SPHOT
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
  </div>
</div>
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
        const mailResult = await transporter.sendMail({
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
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
  color:#172033;
">
  <div style="
    max-width:640px;
    margin:0 auto;
    background:#ffffff;
    border-radius:18px;
    padding:34px;
    box-shadow:0 8px 26px rgba(30,58,138,0.12);
  ">
    <div style="
      text-align:center;
      color:#1e3a8a;
      font-size:32px;
      font-weight:900;
      letter-spacing:8px;
      margin-bottom:28px;
    ">
      SPHOT
    </div>

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
      ${rejectionReason}
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
  </div>
</div>
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

      await transporter.sendMail({
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

        await transporter.sendMail({
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

        await transporter.sendMail({
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

        await transporter.sendMail({
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

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: isReset ?
    "Vos nouveaux accès SPHOT" :
    "Vos accès SPHOT",
          html: `
<div style="margin:0;padding:40px 20px;
background:#eef3f8 url('https://sphot.app/assets/data/images/map_background.jpg')
center center / cover no-repeat;
font-family:Arial,Helvetica,sans-serif;">

    <div style="max-width:620px;margin:auto;
background:rgba(255,255,255,0.94);
border-radius:18px;overflow:hidden;border:1px solid #d9e2ec;
box-shadow:0 4px 12px rgba(0,0,0,.08);">

    <div style="padding:30px 30px 20px 30px;text-align:center;">

      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;">
      </a>
      
    </div>

    <div style="padding:0 34px 30px 34px;color:#263238;
font-size:16px;line-height:1.6;">

      <p style="font-weight:400 !important;">
  Bonjour ${destinataireHtml},
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

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
            background:#d91c1c;
            color:#ffffff;
            text-decoration:none;
            padding:16px 30px;
            border-radius:10px;
            display:inline-block;
            font-size:17px;
            font-weight:bold;">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p style="margin-top:40px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>

    </div>

  </div>

</div>
`,
          text: isReset ?
`Bonjour ${destinataire},

Votre administrateur SPHOT a réinitialisé votre mot de passe.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Utilisez le mot de passe temporaire ci-dessus.

À votre prochaine connexion, vous devrez le modifier.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT` :
`Bonjour ${destinataire},

Votre compte SPHOT a été créé par votre administrateur.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Lors de votre première connexion, vous devrez modifier votre mot de passe.

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

        const data = accountDoc.data();

        if (data.accountStatus !== "ACTIVE") {
          response.status(401).json({success: false});
          return;
        }

        if (data.temporaryPassword !== password) {
          response.status(401).json({success: false});
          return;
        }

        const doc = accountDoc;

        let userRole = "Sauveteur";

        if (Array.isArray(data.fonctions) && data.fonctions.length > 0) {
          userRole = data.fonctions[0].toString();
        } else if ((data.role || "").toString().trim() !== "") {
          userRole = data.role.toString();
        }

        await doc.ref.set(
            {
              lastLoginAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        response.status(200).json({
          success: true,
          sauveteurId: doc.id,
          territoireId: (data.territoireId || "").toString(),
          userRole: userRole,
          mustChangePassword: data.mustChangePassword === true,
        });
      } catch (error) {
        console.error("Erreur login sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.loginAdmin = onRequest(
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

            await transporter.sendMail({
              from: MAIL_FROM,
              to: email,
              replyTo: "contact@sphot.app",
              subject: "Mise à jour de votre compte SPHOT",
              html: `
<div style="margin:0;padding:40px 20px;
background:#eef3f8 url('https://sphot.app/assets/data/images/map_background.jpg')
center center / cover no-repeat;
font-family:Arial,Helvetica,sans-serif;">

  <div style="max-width:620px;margin:auto;
background:rgba(255,255,255,0.94);
border-radius:18px;
overflow:hidden;
border:1px solid #d9e2ec;
box-shadow:0 4px 12px rgba(0,0,0,.08);">

    <div style="padding:30px 30px 20px;text-align:center;">

      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;">
      </a>

    </div>

    <div
      style="padding:0 34px 30px;color:#263238;
      font-size:16px;line-height:1.6;">

      <p style="font-weight:400 !important;">
        Bonjour ${destinataireHtml},
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
            background:#d91c1c;
            color:#ffffff;
            text-decoration:none;
            padding:16px 30px;
            border-radius:10px;
            display:inline-block;
            font-size:17px;
            font-weight:bold;">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p>
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>

    </div>

  </div>

</div>
`,
              text: `Bonjour ${destinataire},

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

            await transporter.sendMail({
              from: MAIL_FROM,
              to: email,
              replyTo: "contact@sphot.app",
              subject:
                  "Mise à jour de votre compte administrateur SPHOT",

              text:
`${greeting}

Nous vous confirmons que le mot de passe de votre compte
administrateur SPHOT pour ${organisation} a été modifié avec succès.

Vous pouvez désormais accéder au portail d'administration SPHOT
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
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
  color:#172033;
">
  <div style="
    max-width:640px;
    margin:0 auto;
    background:#ffffff;
    border-radius:18px;
    padding:34px;
    box-shadow:0 8px 26px rgba(30,58,138,0.12);
  ">
    <div style="padding:0 0 18px;text-align:center;">
      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="
            max-width:320px;
            width:100%;
            height:auto;
            border:0;
          "
        >
      </a>

      <div style="
        margin-top:18px;
        color:#1e3a8a;
        font-size:18px;
        font-weight:900;
        line-height:1.35;
        text-transform:uppercase;
      ">
        MOT DE PASSE MODIFIÉ
      </div>
    </div>

    <p style="font-size:16px;line-height:1.6;">
      ${escapeHtml(greeting)}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Nous vous confirmons que le mot de passe de votre compte
      administrateur SPHOT pour
      <strong>${escapeHtml(organisation)}</strong>
      a été modifié avec succès.
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Vous pouvez désormais accéder au portail d'administration
      SPHOT afin de renseigner vos SPHOTS, vos sauveteurs et vos
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
        SE CONNECTER À SPHOT
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
  </div>
</div>
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

/** Envoie l'accusé de réception d'une candidature annonceur. */
exports.sendAdvertiserRequestAcknowledgement = onDocumentUpdated(
    {
      document: "advertiserRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
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
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: recipient,
          subject:
              "SPHOT - Votre demande annonceur est en cours de traitement",
          text: `${greeting}

Votre demande d'accès annonceur SPHOT pour ${company} a bien été reçue.

Elle est maintenant en cours de vérification par l'équipe SPHOT.
Votre dossier reste consultable, mais ne peut plus être modifié
pendant ce contrôle.

Vous recevrez un nouveau message dès qu'une décision aura été prise.

À bientôt sur SPHOT,

L'équipe SPHOT`,
          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
">
  <div style="
    max-width:620px;
    margin:auto;
    background:#ffffff;
    border-radius:18px;
    overflow:hidden;
    border:1px solid #d9e2ec;
    box-shadow:0 4px 12px rgba(0,0,0,.08);
  ">
    <div style="padding:30px 30px 18px;text-align:center;">
      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;"
        >
      </a>
    </div>

    <div style="
      padding:0 34px 34px;
      color:#263238;
      font-size:16px;
      line-height:1.6;
    ">
      <p>${escapeHtml(greeting)}</p>

      <p>
        Votre demande d'accès annonceur SPHOT pour
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
        Ce message confirme le bon enregistrement de votre demande
        annonceur SPHOT.
      </p>

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
    </div>
  </div>
</div>
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

      const loginUrl = `${SPHOT_LOGIN_URL}/#/professional-login`;
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {user: SMTP_USER, pass: process.env.GMAIL_APP_PASSWORD},
      });

      try {
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: recipient,
          subject: "SPHOT - Votre accès annonceur est validé",
          text: `Bonjour ${firstName || ""},

Votre demande annonceur pour ${company} a été validée.

Identifiant : ${login}
Mot de passe provisoire : ${temporaryPassword}

Vous devrez choisir un nouveau mot de passe lors de votre
première connexion.

Connexion : ${loginUrl}

À bientôt sur SPHOT,

L'équipe SPHOT`,
          html: `<div
style="font-family:Arial,sans-serif;color:#172033;line-height:1.6">
<h2 style="color:#1e3a8a">VOTRE ACCÈS ANNONCEUR EST VALIDÉ</h2>
<p>Bonjour ${escapeHtml(firstName)},</p>
<p>Votre demande pour
<strong>${escapeHtml(company)}</strong> a été validée.</p>
<div
style="padding:18px;border:2px solid #1e3a8a;
border-radius:12px;background:#f5f7fc">
<p><strong>Identifiant :</strong><br>${escapeHtml(login)}</p>
<p><strong>Mot de passe provisoire :</strong><br>
${escapeHtml(temporaryPassword)}</p>
</div>
<p>Vous devrez obligatoirement choisir un nouveau mot de passe lors de
votre première connexion.</p>
<p><a href="${loginUrl}"
style="color:#dc2626;font-weight:bold">SE CONNECTER À SPHOT</a></p>
<p>À bientôt sur SPHOT,<br><strong>L'équipe SPHOT</strong></p>
</div>`,
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
      secrets: ["GMAIL_APP_PASSWORD"],
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
      try {
        const isCorrection = status === "changes_requested" ||
          assetChangeStatus === "authorized";
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: recipient,
          subject: isCorrection ?
            "SPHOT - Une modification de votre demande est nécessaire" :
            "SPHOT - Décision concernant votre demande annonceur",
          text: `${isCorrection ?
            "Une modification est nécessaire avant validation." :
            "Votre demande annonceur n'a pas été retenue."}

Motif : ${reason}

${isCorrection ?
  "Connectez-vous à votre espace pour corriger puis renvoyer le dossier." :
  "Vous pouvez contacter l'équipe SPHOT pour toute précision."}

L'équipe SPHOT`,
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
        const snapshot = await reference.get();
        if (!snapshot.exists) {
          response.status(404).json({success: false});
          return;
        }
        const accountData = snapshot.data() || {};
        const accountRequestId = cleanValue(
            accountData.advertiserRequestId || accountData.requestId,
            "",
        );
        if (accountRequestId !== session.advertiserRequestId) {
          response.status(403).json({success: false});
          return;
        }
        await reference.set({
          temporaryPassword: newPassword,
          mustChangePassword: false,
          passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur changement mot de passe annonceur:", error);
        response.status(500).json({success: false});
      }
    },
);
