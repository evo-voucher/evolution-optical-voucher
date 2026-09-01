# Public Voucher Card CSP fix

The public Voucher page CSP allows `data:` images but not `blob:` images. The restored Voucher Card renderer returns both a canvas and a blob URL. Using the blob URL in `<img src>` therefore produces a blank/blocked card under the current CSP.

The public Voucher UI should use the rendered canvas as a `data:image/png` URL instead. This keeps the existing CSP unchanged, keeps the renderer presentation-only, and does not affect Voucher identity, QR contents, Supabase schema, RLS, RPCs, or redemption behavior.
