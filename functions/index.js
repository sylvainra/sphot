const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/v2/https");
const nodemailer = require("nodemailer");

setGlobalOptions({maxInstances: 10});

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
            user: "rabreau.sylvain@gmail.com",
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
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
      try {
        const email = request.query.email;
        const prenom = request.query.prenom || "Sauveteur";
        const identifiant = request.query.identifiant || "";
        const motDePasse = request.query.motdepasse || "";

        if (!email) {
          response.status(400).send("Email manquant.");
          return;
        }

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: "rabreau.sylvain@gmail.com",
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
          to: email,
          subject: "Vos accès SPHOT",
          text:
`Bonjour ${prenom},

Votre compte SPHOT a été créé.

Identifiant : ${identifiant}
Mot de passe provisoire : ${motDePasse}

Nous vous recommandons de modifier votre mot de passe
dès votre première connexion.

Cordialement,
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
