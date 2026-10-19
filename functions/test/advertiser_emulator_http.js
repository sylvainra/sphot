"use strict";

/**
 * Endpoint HTTP PUBLIC exclusivement pour le test local sur PC.
 * Lit Firestore Emulator et applique la meme projection que la Cloud Function.
 */
const http = require("node:http");
const fs = require("node:fs");
const pathModule = require("node:path");
const admin = require("firebase-admin");
const {projectPublicMapAdvertisement} =
    require("../public_map_advertising");

const host = process.env.FIRESTORE_EMULATOR_HOST || "";
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
  throw new Error("FIRESTORE_EMULATOR_HOST local requis. " +
      "Refus de demarrer contre une base reelle.");
}

const port = 8099;
const projectId = "demo-sphot-publicitaire";
const localCreativeFile = process.env.SPHOT_TEST_BANNER_FILE || "";
if (localCreativeFile && !fs.existsSync(localCreativeFile)) {
  throw new Error("Visuel local introuvable : " + localCreativeFile);
}
const creativeExt = pathModule.extname(localCreativeFile).toLowerCase();
const creativeTypes = {".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".png": "image/png", ".webp": "image/webp"};
if (localCreativeFile && !creativeTypes[creativeExt]) {
  throw new Error("Utiliser un visuel JPG, PNG ou WEBP.");
}
if (admin.apps.length === 0) admin.initializeApp({projectId});
const db = admin.firestore();

http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (req.method !== "GET") {
    res.writeHead(405);
    res.end(JSON.stringify({success: false, advertisements: []}));
    return;
  }

  const path = new URL(req.url, "http://localhost:" + port);
  if (path.pathname === "/creative" && localCreativeFile) {
    res.setHeader("Content-Type", creativeTypes[creativeExt]);
    res.writeHead(200);
    fs.createReadStream(localCreativeFile).pipe(res);
    return;
  }
  if (path.pathname === "/health") {
    res.writeHead(200);
    res.end(JSON.stringify({ok: true, firebase: "emulator-only"}));
    return;
  }
  if (path.pathname !== "/advertisements") {
    res.writeHead(404);
    res.end(JSON.stringify({success: false, advertisements: []}));
    return;
  }

  try {
    const mode = path.searchParams.get("mode") || "pack";
    if (!["map", "premium", "pack", "all"].includes(mode)) {
      res.writeHead(400);
      res.end(JSON.stringify({success: false, advertisements: []}));
      return;
    }
    const snapshot = await db.collection("adRequests")
        .where("status", "==", "active").limit(100).get();
    const advertisements = snapshot.docs.map((doc) =>
      projectPublicMapAdvertisement(doc.id, doc.data()))
        .filter((ad) => ad && (mode === "all" ||
          ad.visibilityType === mode))
        .map((ad) => localCreativeFile ? {
          ...ad,
          // Remplacement LOCAL du visuel pour le navigateur de test.
          // Le service public a d'abord valide l'URL HTTPS d'origine.
          bannerUrl: "http://127.0.0.1:" + port + "/creative",
        } : ad);
    res.writeHead(200);
    res.end(JSON.stringify({success: true, advertisements}));
  } catch (error) {
    console.error("Erreur API locale :", error);
    res.writeHead(500);
    res.end(JSON.stringify({success: false, advertisements: []}));
  }
}).listen(port, "127.0.0.1", () => {
  console.log("SPHOT TEST ADS API: http://127.0.0.1:" + port +
      "/advertisements?mode=pack");
  console.log("Aucune connexion a la production Firebase.");
  if (localCreativeFile) console.log("Visuel local : " + localCreativeFile);
});
