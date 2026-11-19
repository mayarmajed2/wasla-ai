-- ============================================================================
-- MIGRATION 001: MULTI-TENANT AI RESTAURANT ORDERING & AUTOMATION PLATFORM
-- Complete 21-Table Schema with PostgreSQL Row-Level Security (RLS)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 1. TENANTS (Multi-Industry Businesses on Wasla AI)
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    industry_vertical VARCHAR(40) NOT NULL DEFAULT 'RESTAURANT_CAFE' CHECK (
        industry_vertical IN ('RESTAURANT_CAFE', 'ECOMMERCE_RETAIL', 'CLINIC_BOOKING', 'LEAD_GEN_SERVICES')
    ),
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('TRIAL', 'ACTIVE', 'PAST_DUE', 'SUSPENDED', 'CANCELLED')),
    default_currency CHAR(3) NOT NULL DEFAULT 'EGP',
    timezone VARCHAR(64) NOT NULL DEFAULT 'Africa/Cairo',
    ai_persona_config JSONB NOT NULL DEFAULT '{"dialect": "EGYPTIAN_ARABIC", "tone": "WARM_PROFESSIONAL", "upsell_enabled": true}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tenants_status ON tenants(status, industry_vertical);

-- 2. RESTAURANTS (Branches)
CREATE TABLE restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    phone_contact VARCHAR(30) NOT NULL,
    address_text TEXT NOT NULL,
    operating_hours JSONB NOT NULL DEFAULT '{}',
    delivery_zones JSONB NOT NULL DEFAULT '[]',
    accepted_payment_methods TEXT[] NOT NULL DEFAULT ARRAY['CASH_ON_DELIVERY'],
    tax_rate_bps INTEGER NOT NULL DEFAULT 1400,
    is_tax_inclusive BOOLEAN NOT NULL DEFAULT TRUE,
    is_accepting_orders BOOLEAN NOT NULL DEFAULT TRUE,
    ai_agent_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    paused_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_restaurants_tenant ON restaurants(tenant_id);

-- 3. USERS
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30),
    password_hash TEXT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    is_super_admin BOOLEAN NOT NULL DEFAULT FALSE,
    mfa_secret_encrypted TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_tenant ON users(tenant_id);

-- 4. ROLES
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    UNIQUE (tenant_id, code)
);

-- 5. PERMISSIONS & JUNCTION TABLES
CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(100) NOT NULL UNIQUE,
    module VARCHAR(50) NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- 6. CUSTOMERS
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    whatsapp_wa_id VARCHAR(50),
    instagram_scoped_id VARCHAR(100),
    full_name VARCHAR(150),
    phone_normalized VARCHAR(30),
    saved_addresses JSONB NOT NULL DEFAULT '[]',
    preferred_language VARCHAR(10) DEFAULT 'ar-EG',
    total_orders_count INTEGER NOT NULL DEFAULT 0,
    total_spent_minor BIGINT NOT NULL DEFAULT 0,
    is_blocked BOOLEAN NOT NULL DEFAULT FALSE,
    last_interaction_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, whatsapp_wa_id),
    UNIQUE (tenant_id, instagram_scoped_id)
);
CREATE INDEX idx_customers_tenant_phone ON customers(tenant_id, phone_normalized);

-- 7. CONVERSATIONS
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    channel VARCHAR(20) NOT NULL CHECK (channel IN ('WHATSAPP', 'INSTAGRAM')),
    fsm_state VARCHAR(40) NOT NULL DEFAULT 'GREETING_AND_BROWSING' CHECK (
        fsm_state IN (
            'GREETING_AND_BROWSING', 'BUILDING_CART', 'RESOLVING_MODIFIERS',
            'COLLECTING_CUSTOMER_INFO', 'AWAITING_FINAL_CONFIRMATION',
            'ORDER_FINALIZED', 'HUMAN_HANDOVER', 'CLOSED'
        )
    ),
    is_ai_active BOOLEAN NOT NULL DEFAULT TRUE,
    assigned_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    draft_cart JSONB NOT NULL DEFAULT '{"items": [], "customer_info": {}, "cart_version_hash": null, "summary_sent_at": null}',
    window_expires_at TIMESTAMPTZ NOT NULL,
    failure_turn_count INTEGER NOT NULL DEFAULT 0,
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_conversations_active ON conversations(tenant_id, restaurant_id, fsm_state, last_message_at DESC);

-- 8. MESSAGES
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    external_message_id VARCHAR(150) NOT NULL,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('INBOUND', 'OUTBOUND')),
    sender_type VARCHAR(20) NOT NULL CHECK (sender_type IN ('CUSTOMER', 'AI_AGENT', 'HUMAN_STAFF', 'SYSTEM')),
    message_type VARCHAR(20) NOT NULL CHECK (message_type IN ('TEXT', 'AUDIO', 'IMAGE', 'INTERACTIVE', 'LOCATION', 'TEMPLATE')),
    content_text TEXT,
    media_url TEXT,
    audio_transcript TEXT,
    tool_calls_payload JSONB,
    llm_model_used VARCHAR(60),
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    latency_ms INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, external_message_id)
);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at ASC);

-- 9. MENU CATEGORIES
CREATE TABLE menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name_ar VARCHAR(120) NOT NULL,
    name_en VARCHAR(120) NOT NULL,
    description_ar TEXT,
    description_en TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_menu_categories_branch ON menu_categories(tenant_id, restaurant_id, is_active, display_order);

-- 10. MENU ITEMS
CREATE TABLE menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES menu_categories(id) ON DELETE CASCADE,
    sku VARCHAR(64),
    name_ar VARCHAR(150) NOT NULL,
    name_en VARCHAR(150) NOT NULL,
    normalized_search_text TEXT NOT NULL,
    description_ar TEXT,
    description_en TEXT,
    base_price_minor INTEGER NOT NULL CHECK (base_price_minor >= 0),
    image_url TEXT,
    prep_time_mins INTEGER NOT NULL DEFAULT 20,
    max_qty_per_order INTEGER NOT NULL DEFAULT 20,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_menu_items_branch ON menu_items(tenant_id, restaurant_id, is_active);
CREATE INDEX idx_menu_items_trgm ON menu_items USING GIN (normalized_search_text gin_trgm_ops);

-- 11. ITEM VARIATIONS (Modifiers)
CREATE TABLE item_variations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    group_name_ar VARCHAR(120) NOT NULL,
    group_name_en VARCHAR(120) NOT NULL,
    option_name_ar VARCHAR(120) NOT NULL,
    option_name_en VARCHAR(120) NOT NULL,
    price_delta_minor INTEGER NOT NULL DEFAULT 0,
    min_selections INTEGER NOT NULL DEFAULT 1,
    max_selections INTEGER NOT NULL DEFAULT 1,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_item_variations_item ON item_variations(menu_item_id, is_available);

-- 12. AVAILABILITY
CREATE TABLE availability (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    status VARCHAR(30) NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'TEMP_UNAVAILABLE_86', 'SOLD_OUT_TODAY', 'SCHEDULED_ONLY')),
    track_finite_stock BOOLEAN NOT NULL DEFAULT FALSE,
    available_quantity INTEGER CHECK (available_quantity IS NULL OR available_quantity >= 0),
    unavailable_until TIMESTAMPTZ,
    valid_days_of_week SMALLINT[] NOT NULL DEFAULT ARRAY[0,1,2,3,4,5,6],
    valid_start_time TIME,
    valid_end_time TIME,
    updated_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (restaurant_id, menu_item_id)
);
CREATE INDEX idx_availability_lookup ON availability(tenant_id, restaurant_id, status);

-- 13. ORDERS
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE RESTRICT,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE RESTRICT,
    display_order_number INTEGER NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    source_channel VARCHAR(20) NOT NULL CHECK (source_channel IN ('WHATSAPP', 'INSTAGRAM')),
    order_type VARCHAR(20) NOT NULL CHECK (order_type IN ('DELIVERY', 'PICKUP')),
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_RESTAURANT_ACK' CHECK (
        status IN (
            'PENDING_RESTAURANT_ACK', 'CONFIRMED', 'PREPARING',
            'OUT_FOR_DELIVERY', 'DELIVERED', 'REJECTED_BY_RESTAURANT', 'CANCELLED_BY_CUSTOMER'
        )
    ),
    customer_name_snapshot VARCHAR(150) NOT NULL,
    customer_phone_snapshot VARCHAR(30) NOT NULL,
    delivery_zone_name_snapshot VARCHAR(120),
    delivery_address_snapshot JSONB NOT NULL,
    subtotal_minor INTEGER NOT NULL CHECK (subtotal_minor >= 0),
    delivery_fee_minor INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_minor >= 0),
    discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
    tax_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
    total_minor INTEGER NOT NULL CHECK (total_minor >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'EGP',
    payment_method VARCHAR(30) NOT NULL,
    payment_status VARCHAR(20) NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID', 'PENDING_VERIFICATION', 'PAID', 'REFUNDED')),
    special_instructions TEXT,
    estimated_delivery_mins INTEGER,
    acknowledged_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    acknowledged_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, idempotency_key),
    UNIQUE (restaurant_id, display_order_number)
);
CREATE INDEX idx_orders_branch_status ON orders(tenant_id, restaurant_id, status, created_at DESC);

-- 14. ORDER ITEMS
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
    item_name_ar_snapshot VARCHAR(150) NOT NULL,
    item_name_en_snapshot VARCHAR(150) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_base_price_minor INTEGER NOT NULL CHECK (unit_base_price_minor >= 0),
    selected_modifiers_snapshot JSONB NOT NULL DEFAULT '[]',
    unit_total_price_minor INTEGER NOT NULL CHECK (unit_total_price_minor >= 0),
    line_total_minor INTEGER NOT NULL CHECK (line_total_minor >= 0),
    customization_notes TEXT
);
CREATE INDEX idx_order_items_order ON order_items(order_id);

-- 15. ORDER STATUS HISTORY
CREATE TABLE order_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    previous_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    changed_by_type VARCHAR(20) NOT NULL CHECK (changed_by_type IN ('SYSTEM', 'AI_AGENT', 'STAFF_DASHBOARD', 'STAFF_WHATSAPP', 'STAFF_TELEGRAM')),
    changed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_order_status_history_order ON order_status_history(order_id, created_at ASC);

-- 16. PAYMENTS
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    provider VARCHAR(30) NOT NULL CHECK (provider IN ('CASH', 'POS_ON_DELIVERY', 'INSTAPAY_TRANSFER', 'PAYMOB', 'KASHIER')),
    external_transaction_id VARCHAR(150),
    amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'EGP',
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'REFUNDED')),
    receipt_image_url TEXT,
    raw_webhook_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_payments_order ON payments(order_id);

-- 17. INTEGRATIONS
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    provider VARCHAR(30) NOT NULL CHECK (provider IN ('WHATSAPP_CLOUD', 'INSTAGRAM_DM', 'TELEGRAM_BOT', 'FOODICS_POS')),
    external_account_id VARCHAR(120) NOT NULL,
    waba_id VARCHAR(120),
    access_token_encrypted TEXT NOT NULL,
    webhook_verify_token_hash TEXT,
    staff_notification_targets JSONB NOT NULL DEFAULT '[]',
    status VARCHAR(20) NOT NULL DEFAULT 'CONNECTED' CHECK (status IN ('CONNECTED', 'TOKEN_EXPIRED', 'RATE_LIMITED', 'DISCONNECTED')),
    last_webhook_received_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (provider, external_account_id)
);
CREATE INDEX idx_integrations_lookup ON integrations(provider, external_account_id);

-- 18. NOTIFICATIONS (Transactional Outbox)
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    channel VARCHAR(30) NOT NULL CHECK (channel IN ('WHATSAPP_STAFF', 'WHATSAPP_GROUP_OBA', 'TELEGRAM_GROUP', 'KDS_WEBSOCKET', 'SMS_FALLBACK')),
    recipient_identifier VARCHAR(150) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'SENT', 'DELIVERED', 'READ', 'FAILED')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    external_message_id VARCHAR(150),
    last_error TEXT,
    next_retry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notifications_outbox ON notifications(status, next_retry_at) WHERE status IN ('QUEUED', 'FAILED');

-- 19. SUBSCRIPTIONS
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    plan_code VARCHAR(30) NOT NULL CHECK (plan_code IN ('STARTER', 'PROFESSIONAL', 'ENTERPRISE')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('TRIALING', 'ACTIVE', 'PAST_DUE', 'CANCELLED')),
    billing_cycle VARCHAR(15) NOT NULL DEFAULT 'MONTHLY' CHECK (billing_cycle IN ('MONTHLY', 'ANNUAL')),
    base_price_minor INTEGER NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EGP',
    included_orders_quota INTEGER NOT NULL,
    included_conversations_quota INTEGER NOT NULL,
    overage_wallet_balance_minor INTEGER NOT NULL DEFAULT 0,
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    payment_gateway_customer_id VARCHAR(120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 20. USAGE RECORDS
CREATE TABLE usage_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    usage_date DATE NOT NULL,
    orders_confirmed_count INTEGER NOT NULL DEFAULT 0,
    ai_conversations_count INTEGER NOT NULL DEFAULT 0,
    llm_input_tokens BIGINT NOT NULL DEFAULT 0,
    llm_output_tokens BIGINT NOT NULL DEFAULT 0,
    stt_audio_seconds INTEGER NOT NULL DEFAULT 0,
    whatsapp_service_msgs_count INTEGER NOT NULL DEFAULT 0,
    whatsapp_utility_msgs_count INTEGER NOT NULL DEFAULT 0,
    instagram_msgs_count INTEGER NOT NULL DEFAULT 0,
    estimated_cogs_usd_micros BIGINT NOT NULL DEFAULT 0,
    UNIQUE (tenant_id, usage_date)
);
CREATE INDEX idx_usage_records_tenant_date ON usage_records(tenant_id, usage_date DESC);

-- 21. AUDIT LOGS
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_role VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    before_state JSONB,
    after_state JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_logs_tenant_time ON audit_logs(tenant_id, created_at DESC);

-- ============================================================================
-- MULTI-TENANT ROW-LEVEL SECURITY (RLS) ENFORCEMENT
-- ============================================================================
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_variations ENABLE ROW LEVEL SECURITY;
ALTER TABLE availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_restaurants ON restaurants
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_customers ON customers
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_conversations ON conversations
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_messages ON messages
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_menu_categories ON menu_categories
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_menu_items ON menu_items
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_item_variations ON item_variations
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_availability ON availability
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_orders ON orders
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
CREATE POLICY tenant_isolation_order_items ON order_items
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID);
