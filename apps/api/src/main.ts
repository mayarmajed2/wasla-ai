/**
 * Core Application Entrypoint - Event-Driven Modular Monolith
 *
 * Domain Modules:
 * 1. WebhookGatewayModule      - Meta HMAC-SHA256 verification, Redis SETNX deduplication & 3.5s burst debouncer
 * 2. AiOrchestratorModule      - Finite State Machine (FSM), Whisper STT voice pipeline, OpenAI <-> Gemini circuit breaker
 * 3. DeterministicOrderModule  - OrderReadinessValidator gate, SELECT FOR UPDATE stock lock, ACID checkout transaction
 * 4. MenuAvailabilityModule    - Instant 1-Click 86 toggle, Redis snapshot invalidation & pg_trgm Arabic fuzzy search
 * 5. OperationalDispatchModule - Transactional Outbox to Cashier Live KDS, Official Staff WhatsApp & Telegram Kitchen Bot
 * 6. MultiTenantRlsModule      - PostgreSQL Row-Level Security (app.current_tenant_id) & 5-Role RBAC guards
 */

import { validateOrderReadiness, normalizeArabicText } from '@agent-company/shared-types';

export function bootstrapApiInfo() {
  return {
    service: '@agent-company/api',
    architecture: 'Event-Driven Modular Monolith (Split API & BullMQ Worker Runtime)',
    utilitiesLoaded: {
      validatorReady: typeof validateOrderReadiness === 'function',
      arabicNormalizerSample: normalizeArabicText('عايز ٢ شاورمة فراخ'),
    },
  };
}

if (require.main === module) {
  console.log('[AGENT-COMPANY API] Bootstrapping Modular Monolith...', bootstrapApiInfo());
}
