/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Isolated, versioned commercial price catalog. It does NOT alter the
// legacy advertisingPricing/subscriptionPricing documents or live billing.
const commercialDiscounts = require("./commercial_discounts");
const SESSION_COLLECTION = "superAdminPricingSessions";
const MARKETS = "commercialPricingMarkets";
const SESSION_MS = 2 * 60 * 60 * 1000;
const seedAdmin = [499, 399, 299, 199];
const advertiserTariffs = require("./advertiser_radius_tariffs");
const allowedRadiusKeys = advertiserTariffs.PRICE_KEYS;


function seed(type) {
  if (type === "ADMIN") return seedAdmin.slice();
  if (type === "ADVERTISER_RADIUS") {
    return advertiserTariffs.initialPrices();
  }
  throw err(400, "Marché tarifaire inconnu.");
}
function copyPrices(data, type) {
  return type === "ADMIN" ? data.slice() : {...data};
}
function validate(type, value, personalised) {
  const values = type === "ADMIN" ? seedAdmin :
    advertiserTariffs.initialPrices();
  if (type === "ADMIN") {
    if (!Array.isArray(value) || value.length !== 4) {
      throw err(400, "Les 4 tarifs ADMIN sont requis.");
    }
  } else {
    const keys = allowedRadiusKeys;
    if (!value || Array.isArray(value) || typeof value !== "object" ||
        Object.keys(value).length !== keys.length ||
        Object.keys(value).sort().join("|") !== keys.join("|")) {
      throw err(400, "La grille doit comporter exactement " +
          keys.length + " tarifs valides.");
    }
  }
  const amounts = type === "ADMIN" ? value : Object.values(value);
  for (const n of amounts) {
    if (!Number.isSafeInteger(n) || n <= 0 || n > 10000000) {
      throw err(400, "Les tarifs doivent être des euros entiers positifs.");
    }
  }
  if (!Array.isArray(personalised) ||
      personalised.length > (type === "ADMIN" ? 4 : 108) ||
      personalised.some((key) => typeof key !== "string" ||
          !(key in values) && type !== "ADMIN")) {
    throw err(400, "Liste des tarifs personnalisés invalide.");
  }
  return {prices: copyPrices(value, type), personalised: [...new Set(personalised)]};
}
function marketId(type) {
  if (!["ADMIN", "ADVERTISER_RADIUS"].includes(type)) {
    throw err(400, "Marché tarifaire inconnu.");
  }
  return "FR_" + type;
}
function versionId(n) {
  return "v" + String(n).padStart(6, "0");
}
function err(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}
function defaultState(type) {
  const isNewRadiusMarket = type === "ADVERTISER_RADIUS";
  return {
    country: "FR", currency: "EUR", type: type,
    publishedVersion: isNewRadiusMarket ? 0 : 1,
    latestVersion: isNewRadiusMarket ? 0 : 1, revision: 0,
    publishedPrices: seed(type), publishedPersonalised: [],
    draft: null, scheduled: null, seeded: !isNewRadiusMarket,
  };
}
function timeIso(value) {
  return value && typeof value.toDate === "function" ?
    value.toDate().toISOString() : null;
}

function serializeDraft(draft) {
  if (!draft) return null;
  return {
    ...draft,
    createdAt: timeIso(draft.createdAt),
    updatedAt: timeIso(draft.updatedAt),
  };
}

function externalState(data, type) {
  const state = data || defaultState(type);
  return {
    country: "FR", currency: "EUR", type: type,
    publishedVersion: state.publishedVersion,
    latestVersion: state.latestVersion,
    revision: state.revision,
    publishedPrices: state.publishedPrices,
    publishedPersonalised: state.publishedPersonalised || [],
    draft: serializeDraft(state.draft),
    scheduled: state.scheduled ? {
      ...state.scheduled,
      effectiveAt: timeIso(state.scheduled.effectiveAt),
      scheduledAt: timeIso(state.scheduled.scheduledAt),
    } : null,
    seeded: !data,
  };
}

async function issueSession(admin, crypto, login) {
  const token = crypto.randomBytes(32).toString("hex");
  const hash = crypto.createHash("sha256").update(token).digest("hex");
  await admin.firestore().collection(SESSION_COLLECTION).doc(hash).set({
    login: String(login || "super-admin").slice(0, 128),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + SESSION_MS),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return token;
}
async function checkSession(admin, crypto, token) {
  if (typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token)) {
    throw err(401, "Session Super Admin absente.");
  }
  const hash = crypto.createHash("sha256").update(token).digest("hex");
  const doc = await admin.firestore().collection(SESSION_COLLECTION).doc(hash).get();
  if (!doc.exists || !doc.data().expiresAt ||
      doc.data().expiresAt.toMillis() <= Date.now()) {
    throw err(401, "Session Super Admin expirée. Reconnectez-vous.");
  }
  return String(doc.data().login || "super-admin");
}

async function load(admin, type) {
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  const [snap, histories] = await Promise.all([
    root.get(),
    root.collection("versions").orderBy("version", "desc").limit(100).get(),
  ]);
  return {
    ...externalState(snap.exists ? snap.data() : null, type),
    history: histories.docs.map((doc) => {
      const d = doc.data();
      return {
        version: d.version,
        status: d.status,
        // All instants are recorded in UTC and formatted in local time by Flutter.
        effectiveAt: timeIso(d.effectiveAt),
        createdAt: timeIso(d.createdAt),
        scheduledAt: timeIso(d.scheduledAt),
        publishedAt: timeIso(d.publishedAt),
        archivedAt: timeIso(d.archivedAt),
        cancelledAt: timeIso(d.cancelledAt),
        createdBy: d.createdBy || null,
        publishedBy: d.publishedBy || null,
        archivedBy: d.archivedBy || null,
        cancelledBy: d.cancelledBy || null,
        restoredFromVersion: d.restoredFromVersion || null,
        prices: d.prices,
      };
    }),
  };
}

async function saveDraft(admin, type, body, login) {
  const validated = validate(type, body.prices, body.personalised || []);
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  const initial = defaultState(type);
  const expected = body.revision;
  if (!Number.isSafeInteger(expected) || expected < 0) {
    throw err(400, "Révision absente.");
  }
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(root);
    const current = snap.exists ? snap.data() : initial;
    if (current.revision !== expected) {
      throw err(409, "Grille modifiée dans une autre session. Actualisez.");
    }
    if (current.scheduled) {
      throw err(409, "Annulez la programmation avant de créer un brouillon.");
    }
    const publishedRef = root.collection("versions").doc(versionId(1));
    if (!snap.exists && type !== "ADVERTISER_RADIUS") {
      tx.create(publishedRef, {
        version: 1, status: "published",
        prices: seed(type), personalised: [],
        // Reference snapshot: do not call this the original publication date.
        effectiveAt: admin.firestore.Timestamp.now(), createdBy: "seed",
        createdAt: admin.firestore.Timestamp.now(),
      });
    }
    const draftVersion = current.draft ?
      current.draft.version : current.latestVersion + 1;
    const now = admin.firestore.Timestamp.now();
    const draft = {
      version: draftVersion, prices: validated.prices,
      personalised: validated.personalised,
      createdAt: current.draft && current.draft.createdAt ?
        current.draft.createdAt : now,
      createdBy: current.draft && current.draft.createdBy ?
        current.draft.createdBy : login,
      updatedAt: now,
      updatedBy: login,
      ...(current.draft && current.draft.restoredFromVersion ?
        {restoredFromVersion: current.draft.restoredFromVersion} : {}),
    };
    tx.set(root, {
      country: "FR", currency: "EUR", type,
      publishedVersion: current.publishedVersion,
      latestVersion: current.latestVersion,
      publishedPrices: current.publishedPrices,
      publishedPersonalised: current.publishedPersonalised || [],
      draft, scheduled: null,
      revision: expected + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return load(admin, type);
}

/**
 * Creates a NEW, saved draft from a historical immutable pricing version.
 * This never modifies the source version or the currently published prices.
 * An existing draft/schedule must be explicitly handled first.
 */
async function restoreVersion(admin, type, body, login) {
  const sourceVersion = body.sourceVersion;
  const expectedRevision = body.revision;
  if (!Number.isSafeInteger(sourceVersion) || sourceVersion < 1 ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw err(400, "Version source ou révision invalide.");
  }
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  await db.runTransaction(async (tx) => {
    const sourceRef = root.collection("versions").doc(versionId(sourceVersion));
    const [rootSnap, sourceSnap] = await Promise.all([
      tx.get(root), tx.get(sourceRef),
    ]);
    if (!rootSnap.exists || rootSnap.data().revision !== expectedRevision) {
      throw err(409, "La grille a changé. Fermez et rouvrez l'historique.");
    }
    const current = rootSnap.data();
    if (current.draft) {
      throw err(409, "Un brouillon existe déjà : publiez-le ou annulez-le.");
    }
    if (current.scheduled) {
      throw err(409, "Annulez la programmation avant une reprise historique.");
    }
    if (!sourceSnap.exists) {
      throw err(404, "Cette version historique n'existe pas.");
    }
    const source = sourceSnap.data();
    if (source.version !== sourceVersion ||
        !["published", "archived"].includes(source.status)) {
      throw err(409, "Seules les versions publiées ou archivées sont reprises.");
    }
    const snapshot = validate(type, source.prices, source.personalised || []);
    const now = admin.firestore.Timestamp.now();
    tx.update(root, {
      draft: {
        version: current.latestVersion + 1,
        prices: snapshot.prices,
        personalised: snapshot.personalised,
        restoredFromVersion: sourceVersion,
        createdAt: now,
        createdBy: login,
        updatedAt: now,
        updatedBy: login,
      },
      revision: current.revision + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return load(admin, type);
}

async function discardDraft(admin, type, body) {
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(root);
    if (!snap.exists) return;
    const current = snap.data();
    if (current.revision !== body.revision) {
      throw err(409, "La grille a été modifiée. Actualisez.");
    }
    if (current.scheduled) {
      throw err(409, "Annulez d'abord la publication programmée.");
    }
    tx.update(root, {
      draft: null, revision: current.revision + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return load(admin, type);
}

async function publish(admin, type, body, login) {
  const scheduling = body.action === "schedule";
  const effectiveDate = scheduling ? new Date(body.effectiveAt) : new Date();
  if (scheduling && (!Number.isFinite(effectiveDate.getTime()) ||
      effectiveDate.getTime() <= Date.now() + 60000)) {
    throw err(400, "Date de publication future invalide.");
  }
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(root);
    if (!snap.exists || !snap.data().draft) {
      throw err(409, "Enregistrez un brouillon avant publication.");
    }
    const current = snap.data();
    if (current.revision !== body.revision || current.scheduled) {
      throw err(409, "Conflit de version : actualisez la grille.");
    }
    const draft = current.draft;
    validate(type, draft.prices, draft.personalised);
    const previousRef = root.collection("versions")
        .doc(versionId(current.publishedVersion));
    const nextRef = root.collection("versions").doc(versionId(draft.version));
    const [previous, next] = await Promise.all([
      tx.get(previousRef), tx.get(nextRef),
    ]);
    if (next.exists) {
      throw err(409, "La version existe déjà, actualisez.");
    }
    const now = admin.firestore.Timestamp.now();
    tx.create(nextRef, {
      version: draft.version, status: scheduling ? "scheduled" : "published",
      prices: draft.prices, personalised: draft.personalised,
      effectiveAt: admin.firestore.Timestamp.fromDate(effectiveDate),
      createdAt: now, createdBy: login,
      ...(draft.restoredFromVersion ?
        {restoredFromVersion: draft.restoredFromVersion} : {}),
      ...(scheduling ? {scheduledAt: now} :
        {publishedAt: now, publishedBy: login}),
    });
    if (!scheduling && previous.exists) {
      tx.update(previousRef, {
        status: "archived",
        archivedAt: now,
        archivedBy: login,
      });
    }
    tx.update(root, {
      ...(scheduling ? {
        scheduled: {version: draft.version, prices: draft.prices,
          personalised: draft.personalised,
          scheduledAt: now,
          effectiveAt: admin.firestore.Timestamp.fromDate(effectiveDate)},
      } : {
        publishedVersion: draft.version,
        publishedPrices: draft.prices,
        publishedPersonalised: draft.personalised,
      }),
      latestVersion: draft.version, draft: null,
      revision: current.revision + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return load(admin, type);
}

async function cancelSchedule(admin, type, body, login) {
  const db = admin.firestore();
  const root = db.collection(MARKETS).doc(marketId(type));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(root);
    if (!snap.exists || !snap.data().scheduled) {
      throw err(409, "Aucune programmation à annuler.");
    }
    const current = snap.data();
    if (current.revision !== body.revision) {
      throw err(409, "Version modifiée dans une autre session.");
    }
    const scheduled = current.scheduled;
    if (scheduled.effectiveAt.toMillis() <= Date.now()) {
      throw err(409, "La date de publication est déjà atteinte.");
    }
    const futureRef = root.collection("versions").doc(versionId(scheduled.version));
    const future = await tx.get(futureRef);
    if (future.exists) {
      tx.update(futureRef, {
        status: "cancelled",
        cancelledAt: admin.firestore.Timestamp.now(),
        cancelledBy: login,
      });
    }
    tx.update(root, {
      scheduled: null,
      draft: {version: current.latestVersion + 1,
        prices: scheduled.prices, personalised: scheduled.personalised,
        updatedAt: admin.firestore.Timestamp.now()},
      revision: current.revision + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return load(admin, type);
}

function cors(request, response) {
  const origin = request.headers.origin || "";
  if (origin) {
    let url;
    try {
      url = new URL(origin);
    } catch (_) {
      return false;
    }
    const hostname = url.hostname.toLowerCase();
    const allowed = hostname === "sphot.app" ||
        hostname.endsWith(".sphot.app") ||
        hostname === "localhost" || hostname === "127.0.0.1" ||
        hostname === "sphot-ab80b.web.app" ||
        hostname === "sphot-ab80b.firebaseapp.com" ||
        /^sphot-ab80b--[a-z0-9-]+\.web\.app$/.test(hostname);
    if (!allowed) return false;
    response.set("Access-Control-Allow-Origin", origin);
    response.set("Vary", "Origin");
  }
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  response.set("Cache-Control", "no-store");
  return true;
}

function endpoint({admin, crypto, onRequest}) {
  return onRequest({cpu: 1, memory: "256MiB"},
      async (request, response) => {
        if (!cors(request, response)) {
          response.status(403).json({error: "Origine non autorisée."});
          return;
        }
        if (request.method === "OPTIONS") {
          response.status(204).send(""); return;
        }
        if (request.method !== "POST") {
          response.status(405).json({error: "Méthode non autorisée."}); return;
        }
        try {
          const bearer = String(request.headers.authorization || "");
          if (!bearer.startsWith("Bearer ")) {
            throw err(401, "Session manquante.");
          }
          const login = await checkSession(admin, crypto, bearer.slice(7));
          const body = request.body || {};
          const type = body.market;
          marketId(type);
          let result;
          switch (body.action) {
            case "load":
              result = await load(admin, type); break;
            case "save":
              result = await saveDraft(admin, type, body, login); break;
            case "discard":
              result = await discardDraft(admin, type, body); break;
            case "restoreVersion":
              result = await restoreVersion(admin, type, body, login); break;
            case "publish":
            case "schedule":
              result = await publish(admin, type, body, login); break;
            case "cancelSchedule":
              result = await cancelSchedule(admin, type, body, login); break;
            case "getCustomerDiscount":
              result = await commercialDiscounts.getForSuperAdmin(
                  admin, type, body.customerUid);
              break;
            case "setCustomerDiscount":
              result = await commercialDiscounts.setForSuperAdmin(
                  admin, type, body.customerUid, body.discountPercent, login);
              break;
            default: throw err(400, "Action inconnue.");
          }
          response.status(200).json({success: true, data: result});
        } catch (e) {
          console.error("Commercial pricing API:", e.message);
          response.status(e.status || 500)
              .json({success: false, error: e.message || "Erreur serveur."});
        }
      });
}

// Versions programmées: activation sans modifier les prix historiques.
function scheduler({admin, onSchedule}) {
  return onSchedule({schedule: "every 5 minutes", timeZone: "Etc/UTC"},
      async () => {
        const db = admin.firestore();
        const markets = await db.collection(MARKETS).get();
        for (const market of markets.docs) {
          if (!market.data().scheduled) continue;
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(market.ref);
            if (!snap.exists) return;
            const data = snap.data();
            if (!data.scheduled ||
                data.scheduled.effectiveAt.toMillis() > Date.now()) return;
            const next = data.scheduled;
            const previousRef = market.ref.collection("versions")
                .doc(versionId(data.publishedVersion));
            const nextRef = market.ref.collection("versions")
                .doc(versionId(next.version));
            const [previous, scheduledVersion] = await Promise.all([
              tx.get(previousRef), tx.get(nextRef),
            ]);
            if (!scheduledVersion.exists ||
                scheduledVersion.data().status !== "scheduled") return;
            const now = admin.firestore.Timestamp.now();
            if (previous.exists) {
              tx.update(previousRef, {
                status: "archived",
                archivedAt: now,
                archivedBy: "scheduled-activation",
              });
            }
            tx.update(nextRef, {
              status: "published",
              publishedAt: now,
              publishedBy: "scheduled-activation",
            });
            tx.update(market.ref, {
              publishedVersion: next.version,
              publishedPrices: next.prices,
              publishedPersonalised: next.personalised,
              scheduled: null, revision: data.revision + 1,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          });
        }
      });
}
module.exports = {issueSession, checkSession, endpoint, scheduler, validate, defaultState};
