# 🍔 AI Restaurant Ordering & Automation Platform (`AGENT-COMPANY`)

Production-ready, multi-tenant B2B SaaS platform that equips restaurants with an autonomous, bilingual (**Egyptian Arabic, Franco-Arabic, and English**), voice-capable AI Ordering Employee across **WhatsApp Cloud API** and **Instagram Direct Messages**.

---

## 🏗️ Monorepo Structure

```text
AGENT-COMPANY/
├── apps/
│   ├── api/                        # Modular Monolith Backend (API Server + BullMQ Queue Workers)
│   │   └── src/
│   │       └── main.ts             # Entrypoint (Webhooks, AI FSM, Order Engine, Outbox Dispatcher)
│   └── web/                        # Next.js 15 RTL Arabic/English Portal (Dashboard, Live KDS, Super Admin)
├── packages/
│   └── shared-types/               # Deterministic OrderReadinessValidator, Arabic Normalizer & FSM Contracts
│       └── src/
│           └── index.ts
├── database/
│   └── migrations/
│       └── 001_initial_multi_tenant_schema.sql  # Complete 21-Table PostgreSQL 16 Schema + RLS Policies
├── docker-compose.yml              # Local PostgreSQL 16 + Redis 7 Infrastructure
├── .env.example                    # Documented Environment Variables Template
└── package.json                    # NPM Workspaces Monorepo Configuration
```

---

## 🚀 Quick Start (Local Development)

1. **Copy Environment Variables:**
   ```bash
   cp .env.example .env
   ```
2. **Start PostgreSQL 16 & Redis 7 Containers (Auto-runs `001_initial_multi_tenant_schema.sql`):**
   ```bash
   npm run infra:up
   ```
3. **Install Dependencies & Run Workspaces:**
   ```bash
   npm install
   npm run dev
   ```

---

## 🛡️ Non-Negotiable Architectural Guardrails

1. **The AI Never Approves Orders Alone:** `packages/shared-types/src/index.ts` enforces `validateOrderReadiness()`—verifying items, mandatory modifiers, full name, Egyptian/E.164 phone regex, serviced delivery zone, street/building, floor/apartment, payment method, and a cryptographic `cartVersionHash` before checkout can execute.
2. **Real-Time Menu & Stock Locking:** 1-click Cashier "86 / Out-of-Stock" toggles purge Redis snapshots in `<50ms`, and finite-stock items use PostgreSQL `SELECT ... FOR UPDATE` pessimistic locking inside an ACID transaction.
3. **100% Meta-Compliant Multi-Channel Staff Dispatch:** Simultaneous order dispatch to **Live Cashier KDS (with audio alarm & thermal auto-print)**, **Official Staff WhatsApp (with 24h Shift Check-In interactive buttons)**, and **Official Telegram Kitchen Group Bot**, guarded by a **2-minute & 4-minute Unacknowledged Order SLA Watchdog**.
4. **Database-Enforced Multi-Tenancy:** Every tenant table enforces PostgreSQL **Row-Level Security (`RLS`)** scoped to `app.current_tenant_id`.
