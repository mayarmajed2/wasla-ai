/**
 * Wasla AI (وصلة AI) - Multi-Industry Conversational AI Platform
 *
 * Supported Business Verticals:
 * 1. RESTAURANT_CAFE    - Food ordering, modifiers, 1-click 86 toggle, fast delivery zones, Live KDS
 * 2. ECOMMERCE_RETAIL   - Instagram/WhatsApp Brands, Size/Color SKU variants, Governorate courier shipping
 * 3. CLINIC_BOOKING     - Medical clinics, salons & service appointments (time-slot booking validation)
 * 4. LEAD_GEN_SERVICES  - Real estate, B2B & high-ticket sales qualification and instant team routing
 */

import { validateTransactionReadiness, normalizeArabicText } from '@wasla-ai/shared-types';

export function bootstrapWaslaApiInfo() {
  return {
    platform: 'Wasla AI (وصلة AI)',
    service: '@wasla-ai/api',
    supportedVerticals: [
      'RESTAURANT_CAFE',
      'ECOMMERCE_RETAIL',
      'CLINIC_BOOKING',
      'LEAD_GEN_SERVICES',
    ],
    utilitiesLoaded: {
      validatorReady: typeof validateTransactionReadiness === 'function',
      arabicNormalizerSample: normalizeArabicText('عايز ٢ هودي أسود مقاس لارج'),
    },
  };
}

if (require.main === module) {
  console.log('[WASLA AI API] Bootstrapping Multi-Industry Platform...', bootstrapWaslaApiInfo());
}
