"""Read-only, invoice-scoped Stripe evidence for the SPHOT API gateway.

This Odoo 20 extension belongs to the existing sphot_advertiser_checkout
addon. It does not grant model-wide read access to payment providers or
transactions, initiate payments, or write accounting/campaign records.
"""

from odoo import api, models, _
from odoo.exceptions import UserError

from .checkout import _assert_reference, _positive_integer


STRIPE_EVIDENCE_CONTRACT = "sphot_advertiser_stripe_evidence_v1"


class SphotAdvertiserCheckoutStripeEvidence(models.Model):
    _inherit = "sphot.advertiser.checkout"

    @api.model
    def read_stripe_checkout_evidence(self, sphot_reference,
                                      sphot_fingerprint, invoice_id):
        """Return only payment facts for one authenticated SPHOT invoice.

        The caller must belong to the existing SPHOT gateway group. Normal
        sale and accounting ACLs apply to the order/invoice; sudo is limited
        to reading the providers and transactions after that link is checked.
        No provider credentials, tokens, or webhook secrets are returned.
        """
        self._require_gateway()
        _assert_reference(sphot_reference, sphot_fingerprint)
        if not _positive_integer(invoice_id):
            raise UserError(_("Identifiant de facture SPHOT invalide."))

        orders = self.env["sale.order"].search([
            ("x_sphot_reference", "=", sphot_reference),
        ], limit=2)
        if len(orders) != 1:
            raise UserError(_("Commande SPHOT introuvable ou ambiguë."))
        order = orders
        invoices = order.invoice_ids
        if len(invoices) != 1 or invoices.id != invoice_id:
            raise UserError(_("Facture SPHOT absente ou ambiguë."))
        invoice = invoices
        if not (
            order.state == "sale"
            and order.x_sphot_fingerprint == sphot_fingerprint
            and order.client_order_ref == sphot_reference
            and invoice.x_sphot_reference == sphot_reference
            and invoice.x_sphot_fingerprint == sphot_fingerprint
            and invoice.x_sphot_sale_order_id == order
            and invoice.invoice_origin == order.name
            and invoice.partner_id == order.partner_id
            and invoice.company_id == order.company_id
            and invoice.currency_id == order.currency_id
            and invoice.move_type == "out_invoice"
            and invoice.state == "posted"
        ):
            raise UserError(_("Lien commande/facture SPHOT incohérent."))

        company_id = invoice.company_id.id
        providers = self.env["payment.provider"].sudo()
        stripe = providers.search([
            ("code", "=", "stripe"),
            ("is_live", "=", False),
            ("company_id", "=", company_id),
        ], limit=2)
        demo = providers.search([
            ("code", "=", "demo"),
            ("company_id", "=", company_id),
        ], limit=2)
        transactions = self.env["payment.transaction"].sudo().search([
            ("invoice_ids", "in", [invoice_id]),
        ], order="id desc", limit=20)
        if len(transactions) == 20:
            raise UserError(_("Historique Stripe SPHOT ambigu."))

        return {
            "contract": STRIPE_EVIDENCE_CONTRACT,
            "reference": sphot_reference,
            "fingerprint": sphot_fingerprint,
            "invoice_id": invoice_id,
            "stripe_providers": [{
                "id": provider.id,
                "code": provider.code,
                "is_live": provider.is_live,
                "is_published": provider.is_published,
            } for provider in stripe],
            "demo_providers": [{
                "id": provider.id,
                "code": provider.code,
                "is_published": provider.is_published,
            } for provider in demo],
            "transactions": [{
                "id": transaction.id,
                "reference": transaction.reference,
                "state": transaction.state,
                "provider_code": transaction.provider_code,
                "provider_id": transaction.provider_id.id,
                "amount": transaction.amount,
                "currency_id": transaction.currency_id.id,
                "invoice_ids": transaction.invoice_ids.ids,
            } for transaction in transactions],
        }
