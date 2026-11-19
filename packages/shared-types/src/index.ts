import { createHash } from 'crypto';

/**
 * Deterministic Conversation Finite State Machine (FSM) States
 */
export type ConversationFsmState =
  | 'GREETING_AND_BROWSING'
  | 'BUILDING_CART'
  | 'RESOLVING_MODIFIERS'
  | 'COLLECTING_CUSTOMER_INFO'
  | 'AWAITING_FINAL_CONFIRMATION'
  | 'ORDER_FINALIZED'
  | 'HUMAN_HANDOVER'
  | 'CLOSED';

export type OrderChannel = 'WHATSAPP' | 'INSTAGRAM';
export type OrderType = 'DELIVERY' | 'PICKUP';
export type PaymentMethod =
  | 'CASH_ON_DELIVERY'
  | 'CARD_ON_DELIVERY'
  | 'INSTAPAY_TRANSFER'
  | 'ONLINE_PAYMENT_LINK';

export interface SelectedModifier {
  variationId: string;
  groupNameAr: string;
  optionNameAr: string;
  priceDeltaMinor: number;
}

export interface DraftCartItem {
  cartLineId: string;
  menuItemId: string;
  nameAr: string;
  nameEn: string;
  quantity: number;
  unitBasePriceMinor: number;
  selectedModifiers: SelectedModifier[];
  missingMandatoryModifierGroups: string[];
  customizationNotes?: string;
  lineTotalMinor: number;
}

export interface CustomerDeliveryInfo {
  fullName?: string;
  phone?: string;
  orderType?: OrderType;
  deliveryZoneId?: string;
  deliveryZoneName?: string;
  deliveryFeeMinor?: number;
  streetAndBuilding?: string;
  floorAndApartment?: string;
  landmark?: string;
  paymentMethod?: PaymentMethod;
  specialInstructions?: string;
}

export interface DraftCartState {
  items: DraftCartItem[];
  customerInfo: CustomerDeliveryInfo;
  subtotalMinor: number;
  deliveryFeeMinor: number;
  discountMinor: number;
  totalMinor: number;
  cartVersionHash: string | null;
  summarySentAt: string | null;
}

export interface OrderReadinessValidationResult {
  isReadyForSummary: boolean;
  missingOrInvalidFields: {
    field: string;
    reasonCode: string;
    promptHintAr: string;
  }[];
  computedCartVersionHash: string | null;
}

/**
 * Egyptian Mobile Number Regex (+2010/010, +2011/011, +2012/012, +2015/015)
 * and general international E.164 fallback.
 */
const EGYPT_MOBILE_REGEX = /^(?:\+?20|0)?1[0125]\d{8}$/;

/**
 * Normalizes Eastern Arabic numerals (٠١٢٣٤٥٦٧٨٩) and orthographic variants
 * (أ/إ/آ -> ا, ة -> ه, ى -> ي) for deterministic matching.
 */
export function normalizeArabicText(input: string): string {
  const easternDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  let result = input.trim();

  easternDigits.forEach((digit, idx) => {
    result = result.replace(new RegExp(digit, 'g'), idx.toString());
  });

  return result
    .replace(/[\u064B-\u065F\u0640]/g, '') // Strip tashkeel & tatweel
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/\s+/g, ' ');
}

export function validateEgyptianPhone(rawPhone?: string): {
  valid: boolean;
  normalized?: string;
} {
  if (!rawPhone) return { valid: false };
  const cleaned = normalizeArabicText(rawPhone).replace(/[\s\-()]/g, '');
  if (!EGYPT_MOBILE_REGEX.test(cleaned)) {
    return { valid: false };
  }
  const lastTenDigits = cleaned.slice(-10);
  return {
    valid: true,
    normalized: `+20${lastTenDigits}`,
  };
}

/**
 * DETERMINISTIC ORDER READINESS VALIDATOR
 * The AI Agent can NEVER decide on its own that an order is complete.
 * This pure deterministic function verifies every mandatory business requirement.
 */
export function validateOrderReadiness(
  cart: DraftCartState
): OrderReadinessValidationResult {
  const issues: OrderReadinessValidationResult['missingOrInvalidFields'] = [];

  // 1. Must contain at least 1 valid item
  if (!cart.items || cart.items.length === 0) {
    issues.push({
      field: 'items',
      reasonCode: 'EMPTY_CART',
      promptHintAr: 'السلة فاضية، اسأل العميل تحب تطلب إيه من المنيو؟',
    });
  } else {
    // Check mandatory modifiers on every item
    for (const item of cart.items) {
      if (
        item.missingMandatoryModifierGroups &&
        item.missingMandatoryModifierGroups.length > 0
      ) {
        issues.push({
          field: `item_modifiers:${item.cartLineId}`,
          reasonCode: 'MISSING_MANDATORY_MODIFIERS',
          promptHintAr: `الصنف (${item.nameAr}) ناقصه تحديد: ${item.missingMandatoryModifierGroups.join('، ')}`,
        });
      }
    }
  }

  // 2. Full Customer Name
  const name = cart.customerInfo.fullName?.trim() || '';
  if (name.length < 2) {
    issues.push({
      field: 'customerInfo.fullName',
      reasonCode: 'MISSING_CUSTOMER_NAME',
      promptHintAr: 'اسأل العميل عن اسمه بالكامل لتسجيل الطلب.',
    });
  }

  // 3. Validated Phone Number
  const phoneCheck = validateEgyptianPhone(cart.customerInfo.phone);
  if (!phoneCheck.valid) {
    issues.push({
      field: 'customerInfo.phone',
      reasonCode: 'INVALID_OR_MISSING_PHONE',
      promptHintAr:
        'اطلب رقم موبايل صحيح مكون من 11 رقم (يبدأ بـ 010 أو 011 أو 012 أو 015) عشان الدليفري يتواصل معاه.',
    });
  }

  // 4. Order Type & Complete Delivery Address
  const orderType = cart.customerInfo.orderType || 'DELIVERY';
  if (orderType === 'DELIVERY') {
    if (!cart.customerInfo.deliveryZoneId) {
      issues.push({
        field: 'customerInfo.deliveryZoneId',
        reasonCode: 'MISSING_OR_UNCOVERED_DELIVERY_ZONE',
        promptHintAr: 'اسأل العميل عن منطقة التوصيل للتأكد من التغطية وحساب مصاريف الشحن.',
      });
    }
    if (
      !cart.customerInfo.streetAndBuilding ||
      cart.customerInfo.streetAndBuilding.trim().length < 4
    ) {
      issues.push({
        field: 'customerInfo.streetAndBuilding',
        reasonCode: 'MISSING_STREET_AND_BUILDING',
        promptHintAr: 'اسأل العميل عن اسم الشارع ورقم أو اسم العمارة.',
      });
    }
    if (
      !cart.customerInfo.floorAndApartment ||
      cart.customerInfo.floorAndApartment.trim().length < 1
    ) {
      issues.push({
        field: 'customerInfo.floorAndApartment',
        reasonCode: 'MISSING_FLOOR_AND_APARTMENT',
        promptHintAr: 'اسأل العميل عن رقم الدور ورقم الشقة (أو لو فيلا/علامة مميزة).',
      });
    }
  }

  // 5. Payment Method
  if (!cart.customerInfo.paymentMethod) {
    issues.push({
      field: 'customerInfo.paymentMethod',
      reasonCode: 'MISSING_PAYMENT_METHOD',
      promptHintAr: 'اسأل العميل يفضل الدفع كاش عند الاستلام ولا إنستا باي/فيزا؟',
    });
  }

  if (issues.length > 0) {
    return {
      isReadyForSummary: false,
      missingOrInvalidFields: issues,
      computedCartVersionHash: null,
    };
  }

  // Deterministic SHA-256 hash of cart contents, prices, and delivery info
  const canonicalPayload = JSON.stringify({
    items: cart.items.map((i) => ({
      id: i.menuItemId,
      q: i.quantity,
      m: i.selectedModifiers.map((m) => m.variationId).sort(),
      p: i.lineTotalMinor,
      n: i.customizationNotes || '',
    })),
    phone: phoneCheck.normalized,
    zone: cart.customerInfo.deliveryZoneId,
    street: cart.customerInfo.streetAndBuilding?.trim(),
    apt: cart.customerInfo.floorAndApartment?.trim(),
    payment: cart.customerInfo.paymentMethod,
    total: cart.totalMinor,
  });

  const computedCartVersionHash = createHash('sha256')
    .update(canonicalPayload)
    .digest('hex')
    .slice(0, 16);

  return {
    isReadyForSummary: true,
    missingOrInvalidFields: [],
    computedCartVersionHash,
  };
}
