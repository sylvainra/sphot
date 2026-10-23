"use strict";

const crypto = require("crypto");
const nodemailer = require("nodemailer");
const {
  hashPassword,
  isSuperAdminAccount,
  isValidNewPassword,
} = require("./password_security");

const COLLECTIONS = Object.freeze({
  ADMIN: "adminAccounts",
  ANNONCEUR: "advertiserAccounts",
  SAUVETEUR: "sauveteurAccounts",
});
const TOKEN_TTL_MS = 15 * 60 * 1000;
const REQUEST_INTERVAL_MS = 2 * 60 * 1000;
const HOURLY_LIMIT = 5;

/**
 * @param {string} value Value to hash.
 * @return {string} SHA256 digest.
 */
function digest(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

/**
 * Register the two public, single-purpose password recovery operations.
 * A successful request response never reveals whether an account exists.
 *
 * @param {Object} dependencies Firebase and email dependencies.
 * @return {Object} Functions to export from index.js.
 */
function registerPasswordRecovery(dependencies) {
  const {admin, onRequest, sendSphotMail, mailFrom, smtpUser, baseUrl} =
    dependencies;
  const db = admin.firestore();
  // Pilot endpoints use their own tokens and throttle counters. They can
  // affect only the explicitly configured Sauveteur account.
  const pilotConfig = dependencies.pilotConfig || null;
  const tokenCollection = pilotConfig ?
    "passwordRecoveryPilotTokens" : "passwordRecoveryTokens";
  const throttleCollection = pilotConfig ?
    "passwordRecoveryPilotThrottles" : "passwordRecoveryThrottles";

  /** @param {Object} response HTTP response. */
  function setCors(response) {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Content-Type");
    response.set("Cache-Control", "no-store");
  }

  /**
   * @param {string} to Destination.
   * @param {string} subject Subject.
   * @param {string} text Plain text body.
   * @param {string} html HTML body.
   * @return {Promise<Object>} Result of the mail send operation.
   */
  async function mail(to, subject, text, html) {
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {user: smtpUser, pass: process.env.GMAIL_APP_PASSWORD},
    });
    return sendSphotMail(transporter, {
      from: mailFrom,
      to,
      replyTo: "contact@sphot.app",
      subject,
      text,
      html,
    });
  }

  /**
   * Limit requests by identifier even when the account does not exist.
   * This keeps the confirmation identical for registered and unknown users.
   * @param {string} audience Account type.
   * @param {string} login Account identifier.
   * @return {Promise<boolean>} Whether the request may proceed.
   */
  async function allowRequest(audience, login) {
    const key = digest(`${audience}\u0000${login}`);
    const ref = db.collection(throttleCollection).doc(key);
    const now = Date.now();
    return db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const data = snapshot.data() || {};
      const first = data.windowStart && data.windowStart.toMillis ?
        data.windowStart.toMillis() : 0;
      const last = data.lastRequestedAt && data.lastRequestedAt.toMillis ?
        data.lastRequestedAt.toMillis() : 0;
      const sameWindow = now - first < 60 * 60 * 1000;
      const count = sameWindow ? (data.count || 0) : 0;
      if (count >= HOURLY_LIMIT ||
          (last && now - last < REQUEST_INTERVAL_MS)) return false;
      tx.set(ref, {
        count: count + 1,
        windowStart: admin.firestore.Timestamp.fromMillis(
            sameWindow ? first : now),
        lastRequestedAt: admin.firestore.Timestamp.fromMillis(now),
        expiresAt: admin.firestore.Timestamp.fromMillis(
            now + 2 * 60 * 60 * 1000),
      });
      return true;
    });
  }

  const requestSphotPasswordRecovery = onRequest({
    secrets: ["GMAIL_APP_PASSWORD"],
    cpu: 1,
    memory: "256MiB",
  }, async (request, response) => {
    setCors(response);
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    if (request.method !== "POST") {
      response.status(405).json({success: false});
      return;
    }

    const audience = (request.body?.audience || "").toString().toUpperCase();
    const login = (request.body?.login || "").toString().trim().toLowerCase();
    if (!COLLECTIONS[audience] || !login || login.length > 200 ||
        login.includes("/")) {
      response.status(400).json({success: false, error: "invalid_request"});
      return;
    }

    // Always return this answer for a well-formed request, even if the
    // account is unknown, inactive, unverified or a Super Admin.
    const accepted = {success: true};
    try {
      const pilot = pilotConfig ? pilotConfig() : null;
      if (pilotConfig && (!pilot || audience !== "SAUVETEUR" ||
          login !== pilot.login)) {
        response.status(200).json(accepted);
        return;
      }
      if (!await allowRequest(audience, login)) {
        response.status(200).json(accepted);
        return;
      }

      const account = await db.collection(COLLECTIONS[audience])
          .doc(login).get();
      const data = account.data() || {};
      const email = (data.email || "").toString().trim().toLowerCase();
      if (!account.exists || data.accountStatus !== "ACTIVE" ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
          (audience === "SAUVETEUR" && isSuperAdminAccount(data))) {
        response.status(200).json(accepted);
        return;
      }

      const token = crypto.randomBytes(32).toString("hex");
      const ref = db.collection(tokenCollection).doc(digest(token));
      await ref.set({
        audience,
        login,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + TOKEN_TTL_MS),
        usedAt: null,
      });

      const link = `${pilot ? pilot.baseUrl : baseUrl}` +
        `/#/reset-password?token=${token}`;
      const subject = "SPHOT - Réinitialisation de votre mot de passe";
      await mail(email, subject,
          `Bonjour,\n\nVous avez demandé à réinitialiser votre mot de ` +
          `passe SPHOT. Ce lien personnel est valable 15 minutes et une ` +
          `seule fois :\n\n${link}\n\nSi vous n'êtes pas à l'origine ` +
          `de cette demande, ignorez ce message.\n\nL'équipe SPHOT`,
          `<p>Bonjour,</p><p>Vous avez demandé la réinitialisation ` +
          `de votre mot de passe SPHOT.</p><p><a href="${link}">` +
          `Choisir un nouveau mot de passe</a></p><p>Ce lien personnel ` +
          `expire dans 15 minutes et ne peut être utilisé qu'une seule fois.` +
          `</p><p>Si vous n'êtes pas à l'origine de cette demande, ` +
          `ignorez ce message.</p><p>L'équipe SPHOT</p>`);
    } catch (error) {
      console.error("Échec demande de récupération de mot de passe:", error);
      // Do not disclose account existence or mail-delivery failures.
    }
    response.status(200).json(accepted);
  });

  const completeSphotPasswordRecovery = onRequest({
    secrets: ["GMAIL_APP_PASSWORD"],
    cpu: 1,
    memory: "256MiB",
  }, async (request, response) => {
    setCors(response);
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    if (request.method !== "POST") {
      response.status(405).json({success: false});
      return;
    }
    const token = (request.body?.token || "").toString().trim().toLowerCase();
    const password = typeof request.body?.newPassword === "string" ?
      request.body.newPassword.trim() : null;
    if (!/^[a-f0-9]{64}$/.test(token) ||
        !isValidNewPassword(password)) {
      response.status(400).json({success: false, error: "invalid_request"});
      return;
    }

    try {
      const pilot = pilotConfig ? pilotConfig() : null;
      if (pilotConfig && !pilot) {
        response.status(400).json({success: false, error: "expired_link"});
        return;
      }
      const nextHash = hashPassword(password);
      const ref = db.collection(tokenCollection).doc(digest(token));
      const result = await db.runTransaction(async (tx) => {
        const tokenSnapshot = await tx.get(ref);
        const info = tokenSnapshot.data() || {};
        const expiry = info.expiresAt && info.expiresAt.toMillis ?
          info.expiresAt.toMillis() : 0;
        if (!tokenSnapshot.exists || info.usedAt || expiry <= Date.now() ||
            !COLLECTIONS[info.audience] || !info.login) return null;
        if (pilot && (info.audience !== "SAUVETEUR" ||
            info.login !== pilot.login)) return null;

        const accountRef = db.collection(COLLECTIONS[info.audience])
            .doc(info.login);
        const accountSnapshot = await tx.get(accountRef);
        const account = accountSnapshot.data() || {};
        if (!accountSnapshot.exists || account.accountStatus !== "ACTIVE" ||
            (info.audience === "SAUVETEUR" &&
              isSuperAdminAccount(account))) return null;

        tx.update(accountRef, {
          passwordHash: nextHash,
          temporaryPassword: admin.firestore.FieldValue.delete(),
          mustChangePassword: false,
          passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(info.audience === "ADMIN" ? {
            mainCouranteSessionHash:
              admin.firestore.FieldValue.delete(),
          } : {}),
        });
        // An Admin's additional read-only main courante token is independent
        // of Firebase Auth and must also be invalidated after recovery.
        const mainCouranteHash =
          (account.mainCouranteSessionHash || "").toString().trim();
        if (info.audience === "ADMIN" &&
            /^[a-f0-9]{64}$/.test(mainCouranteHash)) {
          tx.set(db.collection("institutionalMainCouranteAccess")
              .doc(mainCouranteHash), {
            enabled: false,
            disabledAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }
        tx.update(ref, {
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          audience: info.audience,
          email: (account.email || "").toString().trim().toLowerCase(),
          uid: info.audience === "ADMIN" ? account.adminUid :
            account.firebaseUid,
          territoireId: (account.territoireId || "").toString(),
          sauveteurId: (account.sauveteurId || "").toString(),
        };
      });

      if (!result) {
        response.status(400).json({success: false, error: "expired_link"});
        return;
      }
      if (result.audience !== "SAUVETEUR" && result.uid) {
        try {
          await admin.auth().revokeRefreshTokens(result.uid);
        } catch (error) {
          console.error("Révocation des anciennes sessions impossible:", error);
        }
      }
      if (result.audience === "SAUVETEUR" && result.territoireId &&
          result.sauveteurId) {
        try {
          await db.collection("territoires").doc(result.territoireId)
              .collection("sauveteurs").doc(result.sauveteurId)
              .update({
                temporaryPassword: admin.firestore.FieldValue.delete(),
                mustChangePassword: false,
              });
        } catch (cleanupError) {
          console.error("Nettoyage ancien mot de passe sauveteur:",
              cleanupError);
        }
      }
      if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) {
        try {
          await mail(result.email,
              "SPHOT - Votre mot de passe a été modifié",
              "Bonjour,\n\nLe mot de passe de votre compte SPHOT vient " +
              "d'être modifié. Si vous n'êtes pas à l'origine de cette " +
              "action, contactez immédiatement contact@sphot.app.\n\n" +
              "L'équipe SPHOT",
              "<p>Bonjour,</p><p>Le mot de passe de votre compte SPHOT " +
              "vient d'être modifié.</p><p>Si vous n'êtes pas à l'origine " +
              "de cette action, contactez immédiatement " +
              "contact@sphot.app.</p><p>L'équipe SPHOT</p>");
        } catch (error) {
          console.error("Confirmation de récupération non envoyée:", error);
        }
      }
      response.status(200).json({success: true});
    } catch (error) {
      console.error("Échec réinitialisation de mot de passe:", error);
      if (!response.headersSent) {
        response.status(500).json({success: false, error: "server_error"});
      }
    }
  });

  return {requestSphotPasswordRecovery, completeSphotPasswordRecovery};
}

module.exports = {registerPasswordRecovery, digest};
