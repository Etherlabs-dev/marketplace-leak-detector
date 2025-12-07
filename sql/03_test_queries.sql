-- Test Queries for Marketplace Leak Detector
-- Use these to verify system is working correctly

-- ============================================
-- BASIC HEALTH CHECKS
-- ============================================

-- 1. Verify all tables exist
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('pricing_rules', 'discount_rules', 'transactions', 'leakage_findings', 'daily_leakage_summary')
ORDER BY tablename;

-- 2. Check row counts
SELECT 'pricing_rules' as table_name, COUNT(*) as rows FROM pricing_rules
UNION ALL SELECT 'discount_rules', COUNT(*) FROM discount_rules
UNION ALL SELECT 'transactions', COUNT(*) FROM transactions
UNION ALL SELECT 'leakage_findings', COUNT(*) FROM leakage_findings
UNION ALL SELECT 'daily_leakage_summary', COUNT(*) FROM daily_leakage_summary;

-- ============================================
-- LEAKAGE DETECTION VERIFICATION
-- ============================================

-- 3. Show all transactions with leakage
SELECT 
    t.id,
    t.category,
    t.gross_amount,
    t.commission_amount,
    t.commission_rate,
    t.leakage_amount,
    COUNT(f.id) as finding_count
FROM transactions t
LEFT JOIN leakage_findings f ON t.id = f.transaction_id
WHERE t.has_leakage = true
GROUP BY t.id, t.category, t.gross_amount, t.commission_amount, t.commission_rate, t.leakage_amount
ORDER BY t.leakage_amount DESC;

-- 4. Show findings by severity
SELECT 
    severity,
    COUNT(*) as count,
    SUM(leakage_amount) as total_leakage,
    AVG(leakage_amount) as avg_leakage,
    MIN(leakage_amount) as min_leakage,
    MAX(leakage_amount) as max_leakage
FROM leakage_findings
GROUP BY severity
ORDER BY 
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
    END;

-- 5. Show findings by type
SELECT 
    leakage_type,
    COUNT(*) as occurrences,
    SUM(leakage_amount) as total_amount,
    AVG(leakage_amount) as avg_amount
FROM leakage_findings
GROUP BY leakage_type
ORDER BY total_amount DESC;

-- ============================================
-- TRANSACTION ANALYSIS
-- ============================================

-- 6. Show transaction leakage rate by category
SELECT 
    category,
    COUNT(*) as total_transactions,
    SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) as transactions_with_leakage,
    ROUND(100.0 * SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) / COUNT(*), 2) as leakage_percentage,
    SUM(leakage_amount) as total_leakage_amount
FROM transactions
GROUP BY category
ORDER BY leakage_percentage DESC;

-- 7. Recent transactions (last 24 hours)
SELECT 
    id,
    seller_id,
    category,
    gross_amount,
    commission_amount,
    has_leakage,
    created_at
FROM transactions
WHERE created_at >= NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 20;

-- 8. Transactions missing commission
SELECT 
    t.id,
    t.seller_id,
    t.category,
    t.gross_amount,
    t.commission_amount,
    pr.base_take_rate as expected_rate,
    (t.gross_amount * pr.base_take_rate / 100) as expected_commission
FROM transactions t
JOIN pricing_rules pr ON t.category = pr.category AND t.product_type = pr.product_type
WHERE t.commission_amount < (t.gross_amount * pr.base_take_rate / 100) - 0.01
ORDER BY (t.gross_amount * pr.base_take_rate / 100) - t.commission_amount DESC;

-- ============================================
-- DISCOUNT ANALYSIS
-- ============================================

-- 9. Discount usage summary
SELECT 
    dr.code,
    dr.discount_type,
    dr.discount_value,
    dr.current_uses,
    dr.max_uses,
    CASE 
        WHEN dr.max_uses IS NOT NULL THEN ROUND(100.0 * dr.current_uses / dr.max_uses, 1)
        ELSE NULL
    END as usage_percentage,
    dr.valid_until,
    CASE 
        WHEN dr.valid_until < NOW() THEN 'Expired'
        WHEN dr.max_uses IS NOT NULL AND dr.current_uses >= dr.max_uses THEN 'Maxed Out'
        ELSE 'Active'
    END as status
FROM discount_rules dr
ORDER BY dr.current_uses DESC;

-- 10. Transactions with invalid discounts
SELECT 
    t.id,
    t.discount_code,
    t.gross_amount,
    f.leakage_type,
    f.description
FROM transactions t
JOIN leakage_findings f ON t.id = f.transaction_id
WHERE t.discount_code IS NOT NULL
  AND f.leakage_type IN ('expired_code', 'exceeded_uses', 'below_minimum', 'incorrect_discount_amount')
ORDER BY t.created_at DESC;

-- ============================================
-- RECOVERY WORKFLOW TRACKING
-- ============================================

-- 11. Show findings by status
SELECT 
    status,
    COUNT(*) as count,
    SUM(leakage_amount) as total_amount,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - created_at))/3600), 1) as avg_age_hours
FROM leakage_findings
GROUP BY status
ORDER BY 
    CASE status
        WHEN 'detected' THEN 1
        WHEN 'investigating' THEN 2
        WHEN 'recovering' THEN 3
        WHEN 'recovered' THEN 4
        WHEN 'written_off' THEN 5
    END;

-- 12. Assigned findings by team member
SELECT 
    assigned_to,
    COUNT(*) as assigned_findings,
    SUM(leakage_amount) as total_leakage_value,
    AVG(EXTRACT(EPOCH FROM (NOW() - assigned_at))/3600) as avg_assignment_age_hours
FROM leakage_findings
WHERE assigned_to IS NOT NULL
GROUP BY assigned_to
ORDER BY total_leakage_value DESC;

-- 13. Unassigned critical/high findings
SELECT 
    id,
    transaction_id,
    leakage_type,
    severity,
    leakage_amount,
    description,
    created_at,
    EXTRACT(EPOCH FROM (NOW() - created_at))/3600 as hours_unassigned
FROM leakage_findings
WHERE status = 'detected'
  AND severity IN ('critical', 'high')
ORDER BY leakage_amount DESC;

-- ============================================
-- DAILY SUMMARIES
-- ============================================

-- 14. Show last 7 days of daily summaries
SELECT 
    report_date,
    total_transactions,
    transactions_with_leakage,
    leakage_percentage || '%' as leakage_pct,
    '$' || total_leakage_amount as total_leakage,
    total_findings,
    critical_findings,
    high_findings,
    top_leakage_category
FROM daily_leakage_summary
WHERE report_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY report_date DESC;

-- 15. Leakage trend (last 30 days)
SELECT 
    report_date,
    total_transactions,
    transactions_with_leakage,
    leakage_percentage,
    total_leakage_amount
FROM daily_leakage_summary
WHERE report_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY report_date;

-- ============================================
-- PERFORMANCE METRICS
-- ============================================

-- 16. Processing speed (transactions per hour today)
SELECT 
    DATE_TRUNC('hour', created_at) as hour,
    COUNT(*) as transactions_processed,
    SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) as with_leakage,
    ROUND(AVG(EXTRACT(EPOCH FROM (processed_at - created_at))), 2) as avg_processing_seconds
FROM transactions
WHERE created_at >= CURRENT_DATE
  AND processed_at IS NOT NULL
GROUP BY DATE_TRUNC('hour', created_at)
ORDER BY hour DESC;

-- 17. Top sellers by leakage
SELECT 
    seller_id,
    COUNT(*) as total_transactions,
    SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) as transactions_with_leakage,
    ROUND(100.0 * SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) / COUNT(*), 1) as leakage_rate,
    SUM(leakage_amount) as total_leakage
FROM transactions
GROUP BY seller_id
HAVING SUM(CASE WHEN has_leakage THEN 1 ELSE 0 END) > 0
ORDER BY total_leakage DESC
LIMIT 10;

-- ============================================
-- DATA QUALITY CHECKS
-- ============================================

-- 18. Check for orphaned findings (transaction deleted but finding remains)
SELECT 
    f.id,
    f.transaction_id,
    f.leakage_type,
    f.created_at
FROM leakage_findings f
LEFT JOIN transactions t ON f.transaction_id = t.id
WHERE t.id IS NULL;

-- 19. Check for transactions marked with leakage but no findings
SELECT 
    t.id,
    t.category,
    t.gross_amount,
    t.leakage_amount,
    COUNT(f.id) as finding_count
FROM transactions t
LEFT JOIN leakage_findings f ON t.id = f.transaction_id
WHERE t.has_leakage = true
GROUP BY t.id, t.category, t.gross_amount, t.leakage_amount
HAVING COUNT(f.id) = 0;

-- 20. Check for inactive pricing rules that might break validation
SELECT 
    pr.category,
    pr.product_type,
    pr.is_active,
    COUNT(t.id) as recent_transactions_using_this_rule
FROM pricing_rules pr
LEFT JOIN transactions t ON pr.category = t.category 
    AND pr.product_type = t.product_type
    AND t.created_at >= NOW() - INTERVAL '7 days'
WHERE pr.is_active = false
GROUP BY pr.category, pr.product_type, pr.is_active
HAVING COUNT(t.id) > 0;

-- ============================================
-- FINANCIAL IMPACT SUMMARY
-- ============================================

-- 21. Total financial impact
SELECT 
    COUNT(DISTINCT t.id) as total_transactions_analyzed,
    COUNT(DISTINCT CASE WHEN t.has_leakage THEN t.id END) as transactions_with_issues,
    SUM(t.gross_amount) as total_gross_revenue,
    SUM(t.commission_amount) as total_commission_collected,
    SUM(t.leakage_amount) as total_leakage_identified,
    ROUND(100.0 * SUM(t.leakage_amount) / NULLIF(SUM(t.gross_amount), 0), 2) as leakage_as_percent_of_revenue,
    COUNT(DISTINCT f.id) as total_findings_created,
    COUNT(DISTINCT CASE WHEN f.status = 'recovered' THEN f.id END) as findings_recovered,
    SUM(CASE WHEN f.status = 'recovered' THEN f.leakage_amount ELSE 0 END) as amount_recovered
FROM transactions t
LEFT JOIN leakage_findings f ON t.id = f.transaction_id;

-- ============================================
-- CLEANUP QUERIES (Use with caution!)
-- ============================================

-- 22. Delete test transactions (uncomment to use)
-- DELETE FROM transactions WHERE id LIKE 'test_%' OR id LIKE 'sample_%';
-- DELETE FROM leakage_findings WHERE transaction_id LIKE 'test_%' OR transaction_id LIKE 'sample_%';

-- 23. Reset discount usage counters (uncomment to use)
-- UPDATE discount_rules SET current_uses = 0 WHERE code LIKE 'TEST%';

-- 24. Clear old data (older than 90 days) - uncomment to use
-- DELETE FROM leakage_findings WHERE created_at < NOW() - INTERVAL '90 days' AND status IN ('recovered', 'written_off');
-- DELETE FROM daily_leakage_summary WHERE report_date < CURRENT_DATE - INTERVAL '90 days';
