# Evolution Voucher System Boundary

This repository is the Evolution Voucher system only.

## Runtime ownership

- GitHub Pages: frontend delivery only (HTML/CSS/JavaScript/PWA assets).
- Supabase project `xfivcfwexcxsyiylgryn`: Voucher backend only (Auth, Postgres, RLS, RPCs, Edge Functions, transaction data).
- Browser code may contain only the Supabase publishable key. Never place `service_role` or other server secrets in this repository's frontend assets.

## XiaoE separation

XiaoE AI Core, memory, persona, brain-router logic and AI-specific data are a separate system. They must not be stored in the Evolution Voucher runtime database and must not be required for Voucher login, issuance, verification, redemption or reporting.

Voucher may integrate with XiaoE in the future only through an explicit, versioned API boundary. Such integration must be optional: Voucher core operations must remain functional when XiaoE is unavailable.

## Change rule

Before changing Voucher, classify the change as frontend, backend contract, data migration, security boundary or optional external integration. Keep XiaoE changes out of this repository unless the file is strictly an interface contract needed by Voucher to call an external XiaoE service.
