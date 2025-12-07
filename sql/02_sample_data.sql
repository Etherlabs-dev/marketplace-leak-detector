-- Sample Data for Testing Marketplace Leak Detector
-- Safe to run multiple times (uses INSERT ... ON CONFLICT)

-- ============================================
-- PRICING RULES
-- ============================================

INSERT INTO pricing_rules (category, product_type, base_take_rate, minimum_price, is_active)
VALUES 
    ('photography', 'service', 15.0, 50.00, true),
    ('photography', 'digital_product', 20.0, 25.00, true),
    ('consulting', 'service', 12.5, 100.00, true),
    ('design', 'service', 18.0, 75.00, true),
    ('writing', 'service', 10.0, 30.00, true),
    ('video', 'service', 15.0, 150.00, true),
    ('software', 'digital_product', 25.0, 50.00, true)
ON CONFLICT (category, product_type) DO UPDATE
SET 
    base_take_rate = EXCLUDED.base_take_rate,
    minimum_price = EXCLUDED.minimum_price,
    is_active = EXCLUDED.is_active;

-- ============================================
-- DISCOUNT RULES
-- ============================================

INSERT INTO discount_rules (code, discount_type, discount_value, minimum_purchase, max_uses, current_uses, valid_from, valid_until, is_active)
VALUES 
    -- Active, valid discount
    ('SAVE10', 'percentage', 10.0, 50.00, 100, 15, CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE + INTERVAL '60 days', true),
    
    -- Expired discount
    ('EXPIRED', 'percentage', 15.0, 100.00, 50, 20, CURRENT_DATE - INTERVAL '180 days', CURRENT_DATE - INTERVAL '30 days', false),
    
    -- At max usage
    ('MAXED', 'fixed_amount', 10.0, 50.00, 10, 10, CURRENT_DATE - INTERVAL '60 days', CURRENT_DATE + INTERVAL '30 days', true),
    
    -- Valid high-value discount
    ('VIP20', 'percentage', 20.0, 200.00, 20, 5, CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE + INTERVAL '90 days', true),
    
    -- Valid fixed amount
    ('FIXED5', 'fixed_amount', 5.0, 25.00, NULL, 8, CURRENT_DATE - INTERVAL '20 days', CURRENT_DATE + INTERVAL '40 days', true)
ON CONFLICT (code) DO UPDATE
SET 
    discount_type = EXCLUDED.discount_type,
    discount_value = EXCLUDED.discount_value,
    minimum_purchase = EXCLUDED.minimum_purchase,
    max_uses = EXCLUDED.max_uses,
    current_uses = EXCLUDED.current_uses,
    valid_from = EXCLUDED.valid_from,
    valid_until = EXCLUDED.valid_until,
    is_active = EXCLUDED.is_active;

-- ============================================
-- SAMPLE TRANSACTIONS (FOR TESTING)
-- ============================================

-- Clean sample transaction (no leakage)
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_clean_001', 'seller_100', 'buyer_200', 'photography', 'service', 100.00, 15.00, 15.0, 85.00, NULL, false, false, 0.00, CURRENT_TIMESTAMP - INTERVAL '2 days')
ON CONFLICT (id) DO NOTHING;

-- Transaction with missing commission (CRITICAL)
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_leak_001', 'seller_101', 'buyer_201', 'photography', 'service', 100.00, 0.00, 0.0, 100.00, NULL, false, true, 15.00, CURRENT_TIMESTAMP - INTERVAL '1 day')
ON CONFLICT (id) DO NOTHING;

-- Transaction with wrong rate (HIGH)
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_leak_002', 'seller_102', 'buyer_202', 'photography', 'service', 100.00, 10.00, 10.0, 90.00, NULL, false, true, 5.00, CURRENT_TIMESTAMP - INTERVAL '1 day')
ON CONFLICT (id) DO NOTHING;

-- Underpriced transaction (MEDIUM)
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_leak_003', 'seller_103', 'buyer_203', 'photography', 'service', 30.00, 4.50, 15.0, 25.50, NULL, false, true, 0.00, CURRENT_TIMESTAMP - INTERVAL '1 day')
ON CONFLICT (id) DO NOTHING;

-- Free trial not converted (MEDIUM)
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_leak_004', 'seller_104', 'buyer_204', 'consulting', 'service', 0.00, 0.00, 0.0, 0.00, NULL, true, true, 0.00, CURRENT_TIMESTAMP - INTERVAL '8 days')
ON CONFLICT (id) DO NOTHING;

-- Valid discount applied
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, has_leakage, leakage_amount, created_at)
VALUES ('sample_discount_001', 'seller_105', 'buyer_205', 'photography', 'service', 100.00, 13.50, 15.0, 76.50, 'SAVE10', false, false, 0.00, CURRENT_TIMESTAMP - INTERVAL '3 hours')
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- SAMPLE LEAKAGE FINDINGS
-- ============================================

INSERT INTO leakage_findings (transaction_id, leakage_type, severity, leakage_amount, expected_amount, actual_amount, description, status, created_at)
VALUES 
    ('sample_leak_001', 'missing_commission', 'critical', 15.00, 15.00, 0.00, 'No commission charged on $100 photography service (expected 15%)', 'detected', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('sample_leak_002', 'wrong_rate', 'high', 5.00, 15.00, 10.00, 'Wrong commission rate: charged 10.0% instead of 15.0%', 'detected', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('sample_leak_003', 'underpriced', 'medium', 0.00, 50.00, 30.00, 'Transaction $30.00 is below minimum price $50.00 for photography/service', 'investigating', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('sample_leak_004', 'free_trial_unpaid', 'medium', 0.00, NULL, 0.00, 'Free trial completed 8 days ago but no payment collected', 'detected', CURRENT_TIMESTAMP - INTERVAL '6 hours')
ON CONFLICT DO NOTHING;

-- ============================================
-- SAMPLE DAILY SUMMARY
-- ============================================

INSERT INTO daily_leakage_summary (report_date, total_transactions, transactions_with_leakage, leakage_percentage, total_leakage_amount, total_findings, critical_findings, high_findings, medium_findings, low_findings, top_leakage_category, top_leakage_seller)
VALUES 
    (CURRENT_DATE - INTERVAL '1 day', 50, 8, 16.00, 127.50, 8, 2, 3, 3, 0, 'photography', 'seller_101')
ON CONFLICT (report_date) DO UPDATE
SET 
    total_transactions = EXCLUDED.total_transactions,
    transactions_with_leakage = EXCLUDED.transactions_with_leakage,
    leakage_percentage = EXCLUDED.leakage_percentage,
    total_leakage_amount = EXCLUDED.total_leakage_amount,
    total_findings = EXCLUDED.total_findings,
    critical_findings = EXCLUDED.critical_findings,
    high_findings = EXCLUDED.high_findings,
    medium_findings = EXCLUDED.medium_findings,
    low_findings = EXCLUDED.low_findings,
    top_leakage_category = EXCLUDED.top_leakage_category,
    top_leakage_seller = EXCLUDED.top_leakage_seller;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Show pricing rules
SELECT 'PRICING RULES' as type, category, product_type, base_take_rate, minimum_price 
FROM pricing_rules 
WHERE is_active = true;

-- Show discount codes
SELECT 'DISCOUNT CODES' as type, code, discount_type, discount_value, current_uses, max_uses, valid_until 
FROM discount_rules 
WHERE is_active = true;

-- Show sample transactions
SELECT 'TRANSACTIONS' as type, id, category, gross_amount, commission_amount, has_leakage, leakage_amount 
FROM transactions 
WHERE id LIKE 'sample_%';

-- Show sample findings
SELECT 'FINDINGS' as type, transaction_id, leakage_type, severity, leakage_amount, status 
FROM leakage_findings 
WHERE transaction_id LIKE 'sample_%';

-- Summary
SELECT 
    (SELECT COUNT(*) FROM pricing_rules WHERE is_active = true) as active_pricing_rules,
    (SELECT COUNT(*) FROM discount_rules WHERE is_active = true) as active_discounts,
    (SELECT COUNT(*) FROM transactions WHERE id LIKE 'sample_%') as sample_transactions,
    (SELECT COUNT(*) FROM leakage_findings WHERE transaction_id LIKE 'sample_%') as sample_findings;

SELECT 'Sample data loaded successfully!' as status;
