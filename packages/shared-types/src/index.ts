import { createHash } from 'crypto';

/**
 * Wasla AI (وصلة AI) - Multi-Industry Vertical Profiles
 * Supports Restaurants, Instagram/E-Commerce Brands, Clinics/Bookings & Lead-Gen Businesses
 */
export type BusinessIndustryVertical =
  | 'RESTAURANT_CAFE'      // مطاعم وكافيهات (إضافات أكل، توصيل سريع، شاشة كاشير KDS)
  | 'ECOMMERCE_RETAIL'     // براندات ملابس، سكين كير، متاجر (مقاسات، ألوان، شحن محافظات)
  | 'CLINIC_BOOKING'       // عيادات، مراكز تجميل، صالونات (حجز مواعيد وخدمات)
  | 'LEAD_GEN_SERVICES';   // عقارات، شركات، معارض، خدمات (تأهيل عملاء وحجز مكالمات مبيعات)

/**
 * Deterministic Conversation Finite State Machine (FSM) States
 */
export type ConversationFsmState =
  | 'GREETING_AND_BROWSING'
  | 'BUILDING_CART_OR_BOOKING'
  | 'RESOLVING_VARIANTS_OR_MODIFIERS'
  | 'COLLECTING_CUSTOMER_INFO'
  | 'AWAITING_FINAL_CONFIRMATION'
  | 'TRANSACTION_FINALIZED'
  | 'HUMAN_HANDOVER'
  | 'CLOSED';

export type MessagingChannel = 'WHATSAPP' | 'INSTAGRAM';
export type FulfillmentType =
  | 'FAST_DELIVERY'        // توصيل سريع (مطاعم / صيدليات)
  | 'COURIER_SHIPPING'     // شحن محافظات (براندات ملابس ومتاجر)
  | 'BRANCH_PICKUP'        // استلام من الفرع
  | 'APPOINTMENT_BOOKING'  // حجز ميعاد (عيادات وخدمات)
  | 'SALES_CALLBACK';      // طلب تواصل مبيعات (عقارات وشركات)

export type PaymentMethod =
  | 'CASH_ON_DELIVERY'
  | 'CARD_ON_DELIVERY'
  | 'INSTAPAY_TRANSFER'
  | 'ONLINE_PAYMENT_LINK'
  | 'PAY_AT_BRANCH';

export interface SelectedVariantOrModifier {
  variationId: string;
  groupNameAr: string;  // e.g. 'المقاس' / 'اللون' / 'حجم الساندوتش'
  optionNameAr: string; // e.g. 'XL' / 'أسود' / 'دابل كومبو'
  priceDeltaMinor: number;
}

export interface DraftLineItem {
  cartLineId: string;
  catalogItemId: string;
  nameAr: string;
  nameEn: string;
  quantity: number;
  unitBasePriceMinor: number;
  selectedOptions: SelectedVariantOrModifier[];
  missingMandatoryGroups: string[]; // e.g. ['المقاس', 'اللون'] or ['نوع المشروب']
  customizationNotes?: string;
  lineTotalMinor: number;
}

export interface CustomerFulfillmentInfo {
  fullName?: string;
  phone?: string;
  fulfillmentType?: FulfillmentType;
  // For Delivery & E-Commerce Shipping
  deliveryZoneOrGovernorateId?: string;
  deliveryZoneOrGovernorateName?: string;
  shippingFeeMinor?: number;
  streetAndBuilding?: string;
  floorAndApartment?: string;
  landmark?: string;
  // For Clinic / Service Appointment Bookings
  appointmentDate?: string;     // YYYY-MM-DD
  appointmentSlotId?: string;   // e.g. '19:30'
  specialistOrBranchName?: string;
  // For Lead Generation (Real Estate / High-Ticket Services)
  inquiryTopicOrBudget?: string;
  paymentMethod?: PaymentMethod;
  specialInstructions?: string;
}

export interface DraftSessionState {
  industryVertical: BusinessIndustryVertical;
  items: DraftLineItem[];
  customerInfo: CustomerFulfillmentInfo;
  subtotalMinor: number;
  shippingFeeMinor: number;
  discountMinor: number;
  totalMinor: number;
  stateVersionHash: string | null;
  summarySentAt: string | null;
}

export interface ReadinessValidationResult {
  isReadyForConfirmation: boolean;
  missingOrInvalidFields: {
    field: string;
    reasonCode: string;
    promptHintAr: string;
  }[];
  computedVersionHash: string | null;
}

const EGYPT_MOBILE_REGEX = /^(?:\+?20|0)?1[0125]\d{8}$/;

/**
 * Normalizes Eastern Arabic numerals (٠١٢٣٤٥٦٧٨٩) and orthographic variants
 */
export function normalizeArabicText(input: string): string {
  const easternDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  let result = input.trim();

  easternDigits.forEach((digit, idx) => {
    result = result.replace(new RegExp(digit, 'g'), idx.toString());
  });

  return result
    .replace(/[\u064B-\u065F\u0640]/g, '')
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
 * WASLA AI DETERMINISTIC MULTI-INDUSTRY VALIDATION ENGINE
 * Dynamically validates mandatory customer & order/booking fields
 * based on the business vertical (Restaurant, E-Commerce Brand, Clinic, or Service Lead).
 */
export function validateTransactionReadiness(
  session: DraftSessionState
): ReadinessValidationResult {
  const issues: ReadinessValidationResult['missingOrInvalidFields'] = [];

  // 1. Validate Items / Services Selected (Except pure Lead-Gen callback inquiries)
  if (session.industryVertical !== 'LEAD_GEN_SERVICES') {
    if (!session.items || session.items.length === 0) {
      issues.push({
        field: 'items',
        reasonCode: 'EMPTY_SELECTION',
        promptHintAr:
          session.industryVertical === 'CLINIC_BOOKING'
            ? 'اسأل العميل عن نوع الخدمة أو الكشف المطلوب حجزه.'
            : 'السلة فاضية، اسأل العميل عن المنتج أو الصنف اللي حابب يطلبه.',
      });
    } else {
      for (const item of session.items) {
        if (item.missingMandatoryGroups && item.missingMandatoryGroups.length > 0) {
          issues.push({
            field: `item_options:${item.cartLineId}`,
            reasonCode: 'MISSING_MANDATORY_VARIANTS_OR_MODIFIERS',
            promptHintAr: `المنتج (${item.nameAr}) لازم العميل يحدد فيه: ${item.missingMandatoryGroups.join('، ')}`,
          });
        }
      }
    }
  }

  // 2. Full Customer Name (Mandatory across ALL businesses)
  const name = session.customerInfo.fullName?.trim() || '';
  if (name.length < 2) {
    issues.push({
      field: 'customerInfo.fullName',
      reasonCode: 'MISSING_CUSTOMER_NAME',
      promptHintAr: 'اسأل العميل عن اسمه بالكامل لتسجيل الطلب أو الحجز.',
    });
  }

  // 3. Validated Phone Number (Mandatory across ALL businesses)
  const phoneCheck = validateEgyptianPhone(session.customerInfo.phone);
  if (!phoneCheck.valid) {
    issues.push({
      field: 'customerInfo.phone',
      reasonCode: 'INVALID_OR_MISSING_PHONE',
      promptHintAr:
        'اطلب رقم موبايل صحيح مكون من 11 رقم (010 / 011 / 012 / 015) للتواصل والتأكيد.',
    });
  }

  // 4. Industry-Specific Fulfillment Validation
  if (
    session.industryVertical === 'RESTAURANT_CAFE' ||
    session.industryVertical === 'ECOMMERCE_RETAIL'
  ) {
    const fulfillment =
      session.customerInfo.fulfillmentType ||
      (session.industryVertical === 'RESTAURANT_CAFE'
        ? 'FAST_DELIVERY'
        : 'COURIER_SHIPPING');

    if (fulfillment === 'FAST_DELIVERY' || fulfillment === 'COURIER_SHIPPING') {
      if (!session.customerInfo.deliveryZoneOrGovernorateId) {
        issues.push({
          field: 'customerInfo.deliveryZoneOrGovernorateId',
          reasonCode: 'MISSING_ZONE_OR_GOVERNORATE',
          promptHintAr:
            session.industryVertical === 'ECOMMERCE_RETAIL'
              ? 'اسأل العميل عن المحافظة والمنطقة لحساب مصاريف الشحن.'
              : 'اسأل العميل عن منطقة التوصيل للتأكد من التغطية وحساب الدليفري.',
        });
      }
      if (
        !session.customerInfo.streetAndBuilding ||
        session.customerInfo.streetAndBuilding.trim().length < 4
      ) {
        issues.push({
          field: 'customerInfo.streetAndBuilding',
          reasonCode: 'MISSING_STREET_AND_BUILDING',
          promptHintAr: 'اسأل العميل عن اسم الشارع ورقم العمارة بالتفصيل.',
        });
      }
      if (
        !session.customerInfo.floorAndApartment ||
        session.customerInfo.floorAndApartment.trim().length < 1
      ) {
        issues.push({
          field: 'customerInfo.floorAndApartment',
          reasonCode: 'MISSING_FLOOR_AND_APARTMENT',
          promptHintAr: 'اسأل العميل عن رقم الدور ورقم الشقة (أو علامة مميزة).',
        });
      }
    }

    if (!session.customerInfo.paymentMethod) {
      issues.push({
        field: 'customerInfo.paymentMethod',
        reasonCode: 'MISSING_PAYMENT_METHOD',
        promptHintAr: 'اسأل العميل يفضل الدفع كاش عند الاستلام ولا إنستا باي/فيزا؟',
      });
    }
  } else if (session.industryVertical === 'CLINIC_BOOKING') {
    if (!session.customerInfo.appointmentDate || !session.customerInfo.appointmentSlotId) {
      issues.push({
        field: 'customerInfo.appointmentSlot',
        reasonCode: 'MISSING_APPOINTMENT_DATE_OR_TIME',
        promptHintAr: 'اعرض المواعيد المتاحة واسأل العميل يختار اليوم والساعة المناسبة للحجز.',
      });
    }
  } else if (session.industryVertical === 'LEAD_GEN_SERVICES') {
    if (!session.customerInfo.inquiryTopicOrBudget) {
      issues.push({
        field: 'customerInfo.inquiryTopicOrBudget',
        reasonCode: 'MISSING_LEAD_QUALIFICATION_DETAILS',
        promptHintAr: 'اسأل العميل عن تفاصيل طلبه أو الفئة المطلوبة عشان فريق المبيعات يكلمه بعرض مناسب.',
      });
    }
  }

  if (issues.length > 0) {
    return {
      isReadyForConfirmation: false,
      missingOrInvalidFields: issues,
      computedVersionHash: null,
    };
  }

  const canonicalPayload = JSON.stringify({
    vertical: session.industryVertical,
    items: session.items.map((i) => ({
      id: i.catalogItemId,
      q: i.quantity,
      o: i.selectedOptions.map((m) => m.variationId).sort(),
      p: i.lineTotalMinor,
    })),
    phone: phoneCheck.normalized,
    zone: session.customerInfo.deliveryZoneOrGovernorateId,
    street: session.customerInfo.streetAndBuilding?.trim(),
    apt: session.customerInfo.floorAndApartment?.trim(),
    slot: session.customerInfo.appointmentSlotId,
    payment: session.customerInfo.paymentMethod,
    total: session.totalMinor,
  });

  const computedVersionHash = createHash('sha256')
    .update(canonicalPayload)
    .digest('hex')
    .slice(0, 16);

  return {
    isReadyForConfirmation: true,
    missingOrInvalidFields: [],
    computedVersionHash,
  };
}
