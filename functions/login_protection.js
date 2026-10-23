"use strict";

const crypto = require("crypto");

const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 8;

/**
 * Limit repeated password guesses per login and source IP. A successful login
 * clears its counter. This does not reveal whether an account exists.
 *
 * @param {Object} admin Firebase Admin SDK.
 * @param {Object} request Firebase HTTP request.
 * @param {string} audience Login endpoint audience.
 * @param {string} login Normalized identifier.
 * @return {Promise<Object>} allowed and clear functions.
 */
async function checkLoginRateLimit(admin, request, audience, login) {
  const source = (request.ip || request.socket?.remoteAddress || "unknown")
      .toString().slice(0, 128);
  const key = crypto.createHash("sha256")
      .update(`${audience}\u0000${login}\u0000${source}`)
      .digest("hex");
  const db = admin.firestore();
  const ref = db.collection("sphotLoginAttempts").doc(key);
  const now = Date.now();
  const allowed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data() || {};
    const started = data.windowStart?.toMillis ?
      data.windowStart.toMillis() : 0;
    const inWindow = now - started < WINDOW_MS;
    const count = inWindow ? data.attempts || 0 : 0;
    if (count >= MAX_ATTEMPTS) return false;
    tx.set(ref, {
      attempts: count + 1,
      windowStart: admin.firestore.Timestamp.fromMillis(
          inWindow ? started : now),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + WINDOW_MS),
    });
    return true;
  });
  return {
    allowed,
    clear: async () => {
      try {
        await ref.delete();
      } catch (error) {
        // Authentication has succeeded; a throttle cleanup failure must
        // never prevent the user from receiving their valid session.
        console.error("Nettoyage compteur de connexion:", error);
      }
    },
  };
}

module.exports = {checkLoginRateLimit};
