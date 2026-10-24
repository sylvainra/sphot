"use strict";

/**
 * Four additional endpoints for a disposable Sauveteur test account.
 * They delegate to the new production handlers without deploying or
 * changing the endpoints used by existing clients.
 *
 * @param {Object} dependencies Firebase and already-defined handlers.
 * @return {Object} Pilot Cloud Function exports.
 */
function registerSauveteurManagementPilot(dependencies) {
  const {
    admin, onRequest, activePasswordPilot,
    verifiedTerritoryAdmin, isSuperAdminAccount, handlers,
  } = dependencies;

  /** @param {Object} response HTTP response. */
  function setCors(response) {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    response.set("Cache-Control", "no-store");
  }

  /**
   * @param {Object} pilot Active pilot configuration.
   * @param {Object} request HTTP request.
   * @return {Promise<boolean>} Only the allowlisted territory Admin qualifies.
   */
  async function validPilotAdmin(pilot, request) {
    if (!pilot.accounts?.ADMIN) return false;
    const caller = await verifiedTerritoryAdmin(request);
    if (!caller) return false;
    const snapshot = await admin.firestore()
        .collection("adminAccounts").doc(pilot.accounts.ADMIN).get();
    const data = snapshot.data() || {};
    const role = (data.role || "").toString().toUpperCase();
    return snapshot.exists && data.accountStatus === "ACTIVE" &&
      !isSuperAdminAccount(data) && (!role || role === "ADMIN") &&
      data.adminUid === caller.adminUid &&
      data.territoireId === caller.territoireId;
  }

  /**
   * @param {string} name Registered operation.
   * @param {boolean} requiresAdmin Whether Admin Firebase Auth is required.
   * @param {boolean} hasMailSecret Whether email may be sent.
   * @return {Function} Registered function.
   */
  function register(name, requiresAdmin, hasMailSecret) {
    const options = {cpu: 1, memory: "256MiB"};
    if (hasMailSecret) options.secrets = ["GMAIL_APP_PASSWORD"];
    return onRequest(options, async (request, response) => {
      setCors(response);
      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }
      if (request.method !== "POST") {
        response.status(405).json({success: false});
        return;
      }

      const pilot = activePasswordPilot();
      const target = ((name === "sendEmail" ? request.body?.identifiant :
        request.body?.login) || "").toString().trim().toLowerCase();
      if (!pilot?.testSauveteurLogin ||
          target !== pilot.testSauveteurLogin) {
        response.status(403).json({success: false});
        return;
      }
      if (requiresAdmin) {
        try {
          if (!await validPilotAdmin(pilot, request)) {
            response.status(403).json({success: false});
            return;
          }
        } catch (error) {
          console.error("Compte Admin pilote indisponible:", error);
          response.status(500).json({success: false});
          return;
        }
      }
      return handlers[name](request, response);
    });
  }

  return {
    upsertSauveteurAccountPilot: register("upsert", true, false),
    sendSauveteurCredentialsEmailPilot: register("sendEmail", true, true),
    deleteSauveteurAccountPilot: register("remove", true, false),
    changeSauveteurPasswordPilot: register("changePassword", false, true),
  };
}

module.exports = {registerSauveteurManagementPilot};
