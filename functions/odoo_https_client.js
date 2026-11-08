"use strict";

// Transport Odoo JSON-2 destiné exclusivement au serveur SPHOT.
// Les identifiants restent dans le backend. Ce module ne crée aucune
// commande, facture, transaction Stripe ou écriture Firestore à lui seul.
const {isIP} = require("node:net");

const ALLOWED_CALLS = Object.freeze({
  "sale.order": new Set(["search_read"]),
  "sale.order.line": new Set(["read"]),
  "account.move": new Set(["read"]),
  "sphot.admin.checkout": new Set([
    "preview_billing_context",
    "create_or_get_draft_order",
    "confirm_and_post_one_invoice",
    "read_stripe_checkout_evidence",
  ]),
  "sphot.advertiser.checkout": new Set([
    "preview_billing_context",
    "create_or_get_draft_order",
    "confirm_and_post_one_invoice",
    "read_stripe_checkout_evidence",
  ]),
});

function invalid(message) {
  const error = new Error(message);
  error.code = "ODOO_GATEWAY_UNAVAILABLE";
  return error;
}

function normalizeOdooBaseUrl(raw) {
  let parsed;
  try {
    parsed = new URL(raw);
  } catch (_) {
    throw invalid("Adresse HTTPS Odoo indisponible.");
  }
  const host = parsed.hostname.toLowerCase();
  if (parsed.protocol !== "https:" || !host || isIP(host) !== 0 ||
      host === "localhost" || host.endsWith(".localhost") ||
      host.endsWith(".local") || host.endsWith(".internal") ||
      parsed.username || parsed.password || parsed.search || parsed.hash ||
      !["", "/"].includes(parsed.pathname)) {
    throw invalid("Seul un serveur Odoo HTTPS identifié est autorisé.");
  }
  return parsed.origin;
}

function createOdooHttpsClient({baseUrl, database, apiKey,
  fetchImpl = globalThis.fetch, timeoutMs = 15000} = {}) {
  const origin = normalizeOdooBaseUrl(baseUrl);
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(database || "") ||
      typeof apiKey !== "string" || !apiKey.trim() ||
      typeof fetchImpl !== "function" ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1000 ||
      timeoutMs > 30000) {
    throw invalid("Configuration serveur Odoo incomplète.");
  }

  async function call(model, method, body) {
    if (!Object.hasOwn(ALLOWED_CALLS, model) ||
        !ALLOWED_CALLS[model].has(method) || !body ||
        typeof body !== "object" || Array.isArray(body)) {
      throw invalid("Opération Odoo non autorisée.");
    }

    let response;
    try {
      response = await fetchImpl(
          `${origin}/json/2/${model}/${method}`,
          {
            method: "POST",
            headers: {
              "Authorization": `bearer ${apiKey}`,
              "X-Odoo-Database": database,
              "Content-Type": "application/json; charset=utf-8",
              "Accept": "application/json",
              "User-Agent": "SPHOT-secure-odoo-gateway",
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(timeoutMs),
            redirect: "error",
          },
      );
    } catch (_) {
      // Ne jamais exposer d'URL interne, de clé ou de traceback Odoo.
      throw invalid("Serveur Odoo momentanément inaccessible.");
    }

    if (!response || !response.ok) {
      throw invalid("Opération Odoo momentanément indisponible.");
    }
    let result;
    try {
      // Évite de lire une réponse démesurée (ou non JSON) sur le backend.
      const contentLength = Number(response.headers?.get?.("content-length"));
      if (Number.isFinite(contentLength) && contentLength > 2097152) {
        throw new Error("size");
      }
      const raw = await response.text();
      if (raw.length > 2097152) throw new Error("size");
      result = JSON.parse(raw);
    } catch (_) {
      throw invalid("Réponse Odoo invalide.");
    }
    if (result == null || typeof result !== "object" ||
        Object.hasOwn(result, "error")) {
      throw invalid("Réponse Odoo non conforme.");
    }
    return result;
  }

  return Object.freeze({call});
}

module.exports = {createOdooHttpsClient, normalizeOdooBaseUrl};
