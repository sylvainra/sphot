"use strict";

// Lance la passerelle sécurisée avec les seules variables C3 DEMO.
// La clé Odoo reste dans l'environnement : elle n'est jamais affichée.
const net = require("node:net");
const path = require("node:path");
const {spawn} = require("node:child_process");

const HOST = "127.0.0.1";
const PORT = 8087;

/**
 * @return {Promise<void>} Confirme la présence du port émulateur local.
 */
function verifyLocalEmulator() {
  return new Promise((resolve, reject) => {
    const socket = net.connect({host: HOST, port: PORT});
    socket.setTimeout(2000);
    socket.once("connect", () => {
      socket.end();
      resolve();
    });
    socket.once("error", () => reject(new Error(
        "Démarrez d'abord l'émulateur Firestore local sur 8087.")));
    socket.once("timeout", () => {
      socket.destroy();
      reject(new Error("Émulateur Firestore local inaccessible."));
    });
  });
}

/**
 * @return {Promise<void>} Démarrage local uniquement, jamais Firebase Cloud.
 */
async function main() {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw new Error("Clé Odoo absente dans ce terminal PowerShell.");
  }
  await verifyLocalEmulator();
  const env = {...process.env,
    GCLOUD_PROJECT: "demo-sphot-c2",
    GOOGLE_CLOUD_PROJECT: "demo-sphot-c2",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8087",
    SPHOT_ODOO_SECURE_CHECKOUT_TEST: "true",
    SPHOT_ODOO_TO_FIRESTORE_EMULATOR: "true",
  };
  const script = path.join(__dirname, "odoo_community_bridge_server.js");
  const child = spawn(process.execPath, [script],
      {env, stdio: "inherit", windowsHide: false});
  child.once("error", (error) => {
    console.error("C3 : impossible de lancer la passerelle :", error.message);
    process.exitCode = 1;
  });
  child.once("exit", (code) => {
    process.exitCode = code === null ? 1 : code;
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error("C3 :", error.message);
    process.exitCode = 1;
  });
}

module.exports = {main};
