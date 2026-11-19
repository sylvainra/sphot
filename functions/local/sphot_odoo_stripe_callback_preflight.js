"use strict";

// SPHOT / Odoo 20 : controle de l'adresse de retour du prestataire Stripe.
// AUDIT LOCAL EN LECTURE SEULE, sans paiement, sans facture, sans Firestore.
// Interroge uniquement ir.config_parameter.get_param("web.base.url")
// sur la copie neutralisee TEST. N'affiche jamais les secrets Odoo/Stripe.
// Ne teste pas l'accessibilite externe et ne change pas les webhooks.

const CLONE = "sphot_checkout_clone_neutral_20261118";

function refuse(message) {
  const e = new Error(message);
  e.code = "SPHOT_ODOO_STRIPE_CALLBACK_PREFLIGHT_REFUSED";
  return e;
}

function analyseBaseUrl(raw) {
  if (typeof raw !== "string" || !raw.trim()) {
    return {status: "BLOQUE", reason: "Adresse Odoo non configuree"};
  }
  let parsed;
  try {
    parsed = new URL(raw.trim());
  } catch (_) {
    return {status: "BLOQUE", reason: "Adresse Odoo invalide"};
  }
  if (parsed.username || parsed.password || parsed.search || parsed.hash ||
      !["http:", "https:"].includes(parsed.protocol)) {
    return {status: "BLOQUE", reason: "Adresse Odoo non securisee"};
  }
  const host = parsed.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  const local = host === "localhost" || host.endsWith(".localhost") ||
      host.endsWith(".local") || host === "127.0.0.1" ||
      host.startsWith("127.") || host === "::1" || host === "0.0.0.0" ||
      host.startsWith("10.") || host.startsWith("192.168.") ||
      /^172\.(1[6-9]|2\d|3[01])\./.test(host) ||
      host === "host.docker.internal";
  if (parsed.protocol !== "https:" || local) {
    return {
      status: "BLOQUE",
      reason: "Odoo utilise une adresse locale ou sans HTTPS : retour Stripe non verifie",
    };
  }
  if (host === "sphot.app" || host.endsWith(".sphot.app")) {
    return {
      status: "BLOQUE",
      reason: "Adresse SPHOT de production interdite dans cet essai",
    };
  }
  // L'adresse HTTPS seule n'est PAS une preuve que les webhooks Stripe
  // atteindront effectivement cette base Odoo, ni que les cles sont TEST.
  return {
    status: "A_VERIFIER",
    reason: "Adresse HTTPS renseignee ; verifier reception webhook et identifiants Stripe TEST",
  };
}

function localReadClient({apiKey, fetchImpl = globalThis.fetch} = {}) {
  if (typeof apiKey !== "string" || apiKey.length < 13) {
    throw refuse("Cle API Odoo TEST absente");
  }
  if (typeof fetchImpl !== "function") {
    throw refuse("Client HTTP indisponible");
  }
  return Object.freeze({
    async readBaseUrl() {
      const response = await fetchImpl(
          "http://127.0.0.1:8069/json/2/ir.config_parameter/get_param", {
            method: "POST",
            headers: {
              Authorization: "bearer " + apiKey,
              "X-Odoo-Database": CLONE,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({key: "web.base.url"}),
            redirect: "error",
            signal: AbortSignal.timeout(15000),
          });
      if (!response?.ok) {
        throw refuse("Lecture de web.base.url refusee dans Odoo TEST");
      }
      const value = await response.json();
      if (value && typeof value === "object" &&
          !Array.isArray(value) && Object.hasOwn(value, "error")) {
        throw refuse("Lecture de web.base.url indisponible");
      }
      return value;
    },
  });
}

async function verifierRetourStripe({client} = {}) {
  if (!client || typeof client.readBaseUrl !== "function") {
    throw refuse("Client de lecture Odoo manquant");
  }
  return analyseBaseUrl(await client.readBaseUrl());
}

async function main() {
  if (process.argv.length !== 3 || process.argv[2] !== "--lecture") {
    throw refuse("Seul le mode --lecture est accepte");
  }
  console.log("=== SPHOT / STRIPE TEST : PRECONTROLE RETOUR ODOO ===");
  console.log("Base Odoo : " + CLONE);
  const result = await verifierRetourStripe({
    client: localReadClient({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    }),
  });
  console.log("Etat : " + result.status);
  console.log("Motif : " + result.reason);
  console.log("AUCUN PAIEMENT, AUCUNE ECRITURE, AUCUN WEBHOOK MODIFIE");
}
if (require.main === module) {
  main().catch(error => {
    console.error("STOP : " +
        String(error?.message || "Precontrole impossible").slice(0, 160));
    console.error("Ne pas lancer de paiement Stripe TEST");
    process.exitCode = 1;
  });
}

module.exports = {CLONE, analyseBaseUrl, localReadClient,
  verifierRetourStripe};
