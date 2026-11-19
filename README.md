# 🔗 Wasla AI (وَصلة AI)
### Multi-Tenant AI Sales, Ordering, Booking & Customer Automation Platform for WhatsApp & Instagram

**Wasla AI** equips businesses across Egypt, MENA, and global markets with an autonomous, bilingual (**Egyptian Arabic, Standard Arabic, Franco-Arabic, and English**), voice-capable AI Employee on **WhatsApp Cloud API** and **Instagram Direct Messages**.

---

## 🎯 Supported Business Verticals (Industry Profiles)

Wasla AI runs a unified **Deterministic Conversational State Machine** under the hood, tailored with 4 specialized industry profiles:

1. **`RESTAURANT_CAFE` (المطاعم والكافيهات):**
   - Full menu & mandatory modifier groups (size, protein, combo, add-ons).
   - Instant 1-Click **"86 / Out-of-Stock"** cashier toggle & neighborhood delivery zones.
   - Live Cashier KDS with audio alarm, thermal receipt auto-print, and staff WhatsApp/Telegram alerts.
2. **`ECOMMERCE_RETAIL` (براندات الإنستجرام، الملابس، السكين كير، المتاجر):**
   - Product catalog with **Size & Color SKU Variants** and per-variant inventory locking.
   - Governorate shipping matrix (Cairo, Giza, Alex, Delta, Upper Egypt) & courier export (Bosta / Mylerz).
   - Comment-to-DM Instagram Reel automation & return/exchange policy handling.
3. **`CLINIC_BOOKING` (العيادات، مراكز التجميل، الصالونات، الحجوزات):**
   - Services & examination fee catalog with doctor/specialist schedules.
   - Deterministic appointment validation (`FullName + ValidPhone + Service + Date + TimeSlot`).
4. **`LEAD_GEN_SERVICES` (العقارات، الشركات، المعارض، الخدمات):**
   - Instant 24/7 FAQ response, budget/requirement qualification, and warm lead routing to human sales reps.

---

## 🏗️ Monorepo Structure

```text
AGENT-COMPANY/ (Wasla AI)
├── apps/
│   ├── api/                        # Modular Monolith Backend (Webhooks, AI FSM, Transaction Engine, Outbox)
│   │   └── src/
│   │       └── main.ts
│   └── web/                        # Next.js 15 RTL Arabic/English Portal (Dashboard, Live Board, Inbox, Super Admin)
├── packages/
│   └── shared-types/               # Multi-Industry validateTransactionReadiness(), Arabic Normalizer & FSM Contracts
│       └── src/
│           └── index.ts
├── database/
│   └── migrations/
│       └── 001_initial_multi_tenant_schema.sql  # 21-Table PostgreSQL 16 Schema + Row-Level Security (RLS)
├── docker-compose.yml              # Local PostgreSQL 16 + Redis 7 Infrastructure
├── .env.example                    # Environment Variables Template
└── package.json                    # NPM Workspaces Configuration
```

---

## 🚀 Quick Start

```bash
cp .env.example .env
npm run infra:up
npm install
npm run dev
```
