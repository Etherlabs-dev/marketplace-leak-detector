-- Marketplace Leak Detector - Database Schema
-- Version: 1.0.0
-- Compatible with: PostgreSQL 12+

-- ============================================
-- PRICING RULES TABLE
-- ============================================
-- Stores category-based commission rates and minimum prices

CREATE TABLE IF NOT EXISTS pricing_rules (
    id BIGSERIAL PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    product_type VARCHAR(50) NOT NULL,
    base_take_rate DECIMAL(5,2) NOT NULL CHECK (base_take_rate >= 0 AND base_take_rate <= 100),
    minimum_price DECIMAL(10,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_category_product UNIQUE (category, product_type)
);

COMMENT ON TABLE pricing_rules IS 'Defines expected commission rates and minimum prices by category';
COMMENT ON COLUMN pricing_rules.base_take_rate IS 'Expected commission percentage (0-100)';
COMMENT ON COLUMN pricing_rules.minimum_price IS 'Minimum allowed transaction amount';

-- Index for fast category lookups
CREATE INDEX idx_pricing_rules_category ON pricing_rules(category) WHERE is_active = true;

-- ============================================
-- DISCOUNT RULES TABLE
-- ============================================
-- Stores promotional discount codes and their rules

CREATE TABLE IF NOT EXISTS discount_rules (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount')),
    discount_value DECIMAL(10,2) NOT NULL,
    minimum_purchase DECIMAL(10,2) DEFAULT 0.00,
    max_uses INTEGER,
    current_uses INTEGER DEFAULT 0,
    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_discount_value CHECK (
        (discount_type = 'percentage' AND discount_value >= 0 AND discount_value <= 100) OR
        (discount_type = 'fixed_amount' AND discount_value >= 0)
    )
);

COMMENT ON TABLE discount_rules IS 'Promotional discount codes and validation rules';
COMMENT ON COLUMN discount_rules.discount_type IS 'Either "percentage" (e.g., 10%) or "fixed_amount" (e.g., $10)';
COMMENT ON COLUMN discount_rules.current_uses IS 'Incremented each time code is used';

-- Index for fast code lookups
CREATE INDEX idx_discount_rules_code ON discount_rules(code) WHERE is_active = true;

-- ============================================
-- TRANSACTIONS TABLE
-- ============================================
-- Stores all marketplace transactions

CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR(100) PRIMARY KEY,
    seller_id VARCHAR(100) NOT NULL,
    buyer_id VARCHAR(100) NOT NULL,
    category VARCHAR(100) NOT NULL,
    product_type VARCHAR(50) NOT NULL,
    gross_amount DECIMAL(10,2) NOT NULL CHECK (gross_amount >= 0),
    commission_amount DECIMAL(10,2) NOT NULL CHECK (commission_amount >= 0),
    commission_rate DECIMAL(5,2) CHECK (commission_rate >= 0 AND commission_rate <= 100),
    net_to_seller DECIMAL(10,2) NOT NULL CHECK (net_to_seller >= 0),
    discount_code VARCHAR(50),
    is_free_trial BOOLEAN DEFAULT false,
    has_leakage BOOLEAN DEFAULT false,
    leakage_amount DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    
    CONSTRAINT valid_amounts CHECK (gross_amount >= commission_amount + net_to_seller - 1)
);

COMMENT ON TABLE transactions IS 'All marketplace transactions with commission details';
COMMENT ON COLUMN transactions.has_leakage IS 'Set to true if any leakage detected';
COMMENT ON COLUMN transactions.leakage_amount IS 'Total amount of revenue leakage';
COMMENT ON COLUMN transactions.processed_at IS 'When leakage detection completed';

-- Indexes for common queries
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE INDEX idx_transactions_seller ON transactions(seller_id);
CREATE INDEX idx_transactions_leakage ON transactions(has_leakage) WHERE has_leakage = true;

-- ============================================
-- LEAKAGE FINDINGS TABLE
-- ============================================
-- Stores detected revenue leakage instances

CREATE TABLE IF NOT EXISTS leakage_findings (
    id BIGSERIAL PRIMARY KEY,
    transaction_id VARCHAR(100) NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    leakage_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    leakage_amount DECIMAL(10,2) NOT NULL,
    expected_amount DECIMAL(10,2),
    actual_amount DECIMAL(10,2),
    description TEXT,
    status VARCHAR(20) DEFAULT 'detected' CHECK (status IN ('detected', 'investigating', 'recovering', 'recovered', 'written_off')),
    assigned_to VARCHAR(100),
    assigned_at TIMESTAMP,
    resolved_at TIMESTAMP,
    resolution_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE leakage_findings IS 'Individual revenue leakage incidents';
COMMENT ON COLUMN leakage_findings.leakage_type IS 'Type of leakage: missing_commission, wrong_rate, underpriced, etc.';
COMMENT ON COLUMN leakage_findings.severity IS 'Priority level based on amount and type';
COMMENT ON COLUMN leakage_findings.status IS 'Recovery workflow status';

-- Indexes for common queries
CREATE INDEX idx_findings_transaction ON leakage_findings(transaction_id);
CREATE INDEX idx_findings_status ON leakage_findings(status) WHERE status IN ('detected', 'investigating');
CREATE INDEX idx_findings_severity ON leakage_findings(severity, created_at DESC);
CREATE INDEX idx_findings_assigned ON leakage_findings(assigned_to) WHERE assigned_to IS NOT NULL;

-- ============================================
-- DAILY LEAKAGE SUMMARY TABLE
-- ============================================
-- Stores aggregated daily statistics

CREATE TABLE IF NOT EXISTS daily_leakage_summary (
    id BIGSERIAL PRIMARY KEY,
    report_date DATE NOT NULL UNIQUE,
    total_transactions INTEGER NOT NULL DEFAULT 0,
    transactions_with_leakage INTEGER NOT NULL DEFAULT 0,
    leakage_percentage DECIMAL(5,2) DEFAULT 0.00,
    total_leakage_amount DECIMAL(12,2) DEFAULT 0.00,
    total_findings INTEGER NOT NULL DEFAULT 0,
    critical_findings INTEGER DEFAULT 0,
    high_findings INTEGER DEFAULT 0,
    medium_findings INTEGER DEFAULT 0,
    low_findings INTEGER DEFAULT 0,
    top_leakage_category VARCHAR(100),
    top_leakage_seller VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE daily_leakage_summary IS 'Daily aggregated leakage statistics';
COMMENT ON COLUMN daily_leakage_summary.leakage_percentage IS 'Percentage of transactions with leakage';

-- Index for date-based queries
CREATE INDEX idx_summary_date ON daily_leakage_summary(report_date DESC);

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-update updated_at timestamp on pricing_rules
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_pricing_rules_updated_at
    BEFORE UPDATE ON pricing_rules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VIEWS (Optional - for easier querying)
-- ============================================

-- View: Active high-value findings
CREATE OR REPLACE VIEW active_high_value_findings AS
SELECT 
    f.id,
    f.transaction_id,
    t.seller_id,
    t.category,
    f.leakage_type,
    f.severity,
    f.leakage_amount,
    f.status,
    f.assigned_to,
    f.created_at
FROM leakage_findings f
JOIN transactions t ON f.transaction_id = t.id
WHERE f.status IN ('detected', 'investigating')
  AND f.severity IN ('critical', 'high')
ORDER BY f.leakage_amount DESC;

-- View: Daily stats (last 30 days)
CREATE OR REPLACE VIEW recent_daily_stats AS
SELECT 
    report_date,
    total_transactions,
    transactions_with_leakage,
    leakage_percentage,
    total_leakage_amount,
    total_findings
FROM daily_leakage_summary
WHERE report_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY report_date DESC;

-- ============================================
-- GRANT PERMISSIONS (Adjust as needed)
-- ============================================

-- For n8n service role (full access)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- For read-only analytics user (optional)
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_user;

-- ============================================
-- VERIFICATION
-- ============================================

-- Verify all tables created
DO $$
DECLARE
    table_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('pricing_rules', 'discount_rules', 'transactions', 'leakage_findings', 'daily_leakage_summary');
    
    IF table_count = 5 THEN
        RAISE NOTICE 'SUCCESS: All 5 tables created successfully';
    ELSE
        RAISE WARNING 'WARNING: Only % of 5 tables created', table_count;
    END IF;
END $$;

-- Show table sizes (should all be 0 rows initially)
SELECT 
    'pricing_rules' as table_name, COUNT(*) as row_count FROM pricing_rules
UNION ALL SELECT 'discount_rules', COUNT(*) FROM discount_rules
UNION ALL SELECT 'transactions', COUNT(*) FROM transactions
UNION ALL SELECT 'leakage_findings', COUNT(*) FROM leakage_findings
UNION ALL SELECT 'daily_leakage_summary', COUNT(*) FROM daily_leakage_summary;
