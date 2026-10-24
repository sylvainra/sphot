/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// PASSERELLE DE DÉVELOPPEMENT UNIQUEMENT.
// Démarrage manuel : node functions/local/odoo_commercial_simulation_server.js
// Aucun import dans functions/index.js, aucune Cloud Function, aucun Odoo,
// Stripe, Firebase, stockage, preuve de paiement ou activation de campagne.

const http = require("node:http");
const {createOdooCommercialSimulator} =
    require("../odoo_commercial_simulator");
const {advertiserQuote} = require("../commercial_quote_pricing");
const {initialPrices, LEVELS, OFFERS, DURATIONS} =
    require("../advertiser_radius_tariffs");

const LOOPBACK = "127.0.0.1";
const PORT = 8765;
const MAX_BODY_BYTES = 4096;
const LOCAL_WEB_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1):[0-9]{2,5}$/;

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function send(res, status, payload) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(
      String(req.headers["content-type"] || ""))) {
    throw fail(415, "JSON requis pour cette simulation locale.");
  }
  let length = 0;
  const buffers = [];
  for await (const chunk of req) {
    length += chunk.length;
    if (length > MAX_BODY_BYTES) {
      throw fail(413, "Requête de simulation trop volumineuse.");
    }
    buffers.push(chunk);
  }
  try {
    const data = JSON.parse(Buffer.concat(buffers).toString("utf8"));
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error("Not an object");
    }
    return data;
  } catch (_) {
    throw fail(400, "Corps JSON invalide.");
  }
}

function assertFields(body, permitted) {
  const allowed = new Set(permitted);
  if (Object.keys(body).some((key) => !allowed.has(key))) {
    throw fail(400, "Paramètre de simulation non autorisé.");
  }
}

function validateSession(sessionKey) {
  if (typeof sessionKey !== "string" ||
      !/^[A-Za-z0-9_-]{6,60}$/.test(sessionKey)) {
    throw fail(400, "Session de simulation invalide.");
  }
  return "SPHOT-DEMO-" + sessionKey;
}

function createSimulationServer() {
  // 20 % UNIQUEMENT comme scénario fictif déjà testé le 24/10/2026.
  // L'intégration réelle délèguera entièrement la fiscalité à Odoo.
  const simulator = createOdooCommercialSimulator({taxRateBasisPoints: 2000});
  const scenarios = new Map();
  const demoTariffs = {
    type: "ADVERTISER_RADIUS",
    publishedVersion: 1,
    country: "FR",
    currency: "EUR",
    publishedPrices: initialPrices(),
  };

  return http.createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && !LOCAL_WEB_ORIGIN.test(origin)) {
      send(res, 403, {ok: false, error: "ORIGINE_NON_LOCALE"});
      return;
    }
    if (origin) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    }
    if (req.method === "OPTIONS") {
      res.writeHead(204, {"Cache-Control": "no-store"});
      res.end();
      return;
    }
    if (req.url === "/health" && req.method === "GET") {
      send(res, 200, {ok: true, mode: "SIMULATION_ONLY", persisted: false});
      return;
    }
    if (req.url !== "/purchase" || req.method !== "POST") {
      send(res, 404, {ok: false, error: "ROUTE_DE_TEST_INTROUVABLE"});
      return;
    }

    try {
      const body = await readJson(req);
      const action = body.action;
      const reference = validateSession(body.sessionKey);
      let snapshot;

      if (action === "create") {
        assertFields(body, ["action", "sessionKey", "territory", "offer", "duration"]);
        if (!LEVELS.includes(body.territory) ||
            !OFFERS.includes(body.offer) ||
            !DURATIONS.includes(body.duration)) {
          throw fail(400, "Sélection tarifaire de simulation inconnue.");
        }
        // Seules les trois options sont transmises depuis Flutter : jamais
        // le prix, le taux de remise, le numéro de client ou une taxe.
        const quote = advertiserQuote(demoTariffs,
            body.territory, body.offer, body.duration);
        const preparedQuote = {
          ...quote,
          discountPercent: 0,
          payableExclTaxCents: quote.amountExclTax * 100,
        };
        snapshot = simulator.createDraftOrder({
          quote: preparedQuote,
          partnerId: 12, // identifiant fictif, jamais envoyé à Odoo
          productIds: {advertiser: 42}, // identifiant fictif
          sphotReference: reference,
        });
        scenarios.set(reference, {
          territory: body.territory,
          offer: body.offer,
          duration: body.duration,
          pricingReference: quote.pricingReference,
          demoTariffOnly: true,
          simulatedVatBasisPoints: 2000,
        });
      } else {
        assertFields(body, ["action", "sessionKey", "outcome", "attemptKey"]);
        if (!scenarios.has(reference)) {
          throw fail(404, "Dossier de simulation inexistant.");
        }
        if (action === "confirm_order") {
          snapshot = simulator.confirmOrder(reference);
        } else if (action === "invoice_draft") {
          snapshot = simulator.createInvoiceDraft(reference);
        } else if (action === "confirm_invoice") {
          snapshot = simulator.confirmInvoice(reference);
        } else if (action === "status") {
          // Lecture seule, utile si le navigateur a perdu une réponse.
          snapshot = simulator.getPurchase(reference);
        } else if (action === "payment") {
          if (typeof body.attemptKey !== "string" ||
              !/^[A-Za-z0-9_-]{6,96}$/.test(body.attemptKey)) {
            throw fail(400, "Tentative de paiement fictif invalide.");
          }
          snapshot = simulator.simulatePayment({
            sphotReference: reference,
            attemptKey: body.attemptKey,
            outcome: body.outcome,
          });
        } else {
          throw fail(400, "Action de simulation inconnue.");
        }
      }
      send(res, 200, {
        ok: true,
        mode: "SIMULATION_ONLY",
        scenario: scenarios.get(reference),
        simulation: snapshot,
      });
    } catch (error) {
      const status = [400, 404, 409, 413, 415].includes(error.status) ?
        error.status : 500;
      if (status === 500) console.error("Simulation Odoo locale :", error);
      send(res, status, {
        ok: false,
        mode: "SIMULATION_ONLY",
        error: status === 500 ? "ERREUR_SIMULATION_LOCALE" : error.message,
      });
    }
  });
}

if (require.main === module) {
  const server = createSimulationServer();
  server.listen(PORT, LOOPBACK, () => {
    console.log("Simulation SPHOT/Odoo locale disponible sur http://" +
        LOOPBACK + ":" + PORT + " (AUCUN PAIEMENT REEL)");
  });
}

module.exports = {createSimulationServer};
