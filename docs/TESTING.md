# Testing Guide

Complete test suite for Marketplace Leak Detector.

**Time required:** 15-20 minutes

---

## Prerequisites

- ✅ All 5 workflows imported and activated
- ✅ Supabase tables created
- ✅ Sample data inserted (from `sql/02_sample_data.sql`)

---

## Test Suite Overview

| Test # | What It Tests | Expected Outcome |
|--------|---------------|------------------|
| 1-5 | Transaction Validator | 5 leakage types detected |
| 6-10 | Discount Validator | 5 discount issues detected |
| 11 | Daily Reporter | Summary generated |
| 12 | Recovery Manager | Findings assigned |

---

## Workflow 1: Transaction Monitor

### Setup

Get your Workflow 1 webhook URL:
```bash
# In n8n, open Workflow 1 → Click webhook node → Copy Production URL
export WEBHOOK_URL="https://your-n8n.app/webhook/marketplace/transaction"
```

### Test: Basic Transaction Capture
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_basic",
  "seller_id": "seller_001",
  "buyer_id": "buyer_001",
  "category": "photography",
  "product_type": "service",
  "amount": 100.00,
  "commission": 15.00,
  "commission_rate": 15.0,
  "net_to_seller": 85.00,
  "discount_code": null,
  "is_free_trial": false
}'
```

**Expected Result:**
- ✅ Workflow 1 shows green checkmark in n8n
- ✅ Transaction appears in Supabase `transactions` table
- ✅ Workflow 2 automatically triggers
- ✅ No leakage detected (all correct)

**Verify:**
```sql
SELECT * FROM transactions WHERE id = 'test_basic';
-- Should show has_leakage = false

SELECT * FROM leakage_findings WHERE transaction_id = 'test_basic';
-- Should return 0 rows (no leakage)
```

---

## Workflow 2: Transaction Validator

### Test 1: Missing Commission (Critical)
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_missing_commission",
  "seller_id": "seller_002",
  "buyer_id": "buyer_002",
  "category": "photography",
  "product_type": "service",
  "amount": 100.00,
  "commission": 0.00,
  "commission_rate": 0.0,
  "net_to_seller": 100.00,
  "discount_code": null,
  "is_free_trial": false
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, leakage_amount 
FROM leakage_findings 
WHERE transaction_id = 'test_missing_commission';

-- Should return:
-- leakage_type: missing_commission
-- severity: critical
-- leakage_amount: 15.00
```

---

### Test 2: Wrong Commission Rate (High)
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_wrong_rate",
  "seller_id": "seller_003",
  "buyer_id": "buyer_003",
  "category": "photography",
  "product_type": "service",
  "amount": 100.00,
  "commission": 10.00,
  "commission_rate": 10.0,
  "net_to_seller": 90.00,
  "discount_code": null,
  "is_free_trial": false
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, leakage_amount, description
FROM leakage_findings 
WHERE transaction_id = 'test_wrong_rate';

-- Should return:
-- leakage_type: wrong_rate
-- severity: high (leakage > $5)
-- leakage_amount: 5.00
-- description: mentions "10.0% instead of 15.0%"
```

---

### Test 3: Underpriced Transaction (Medium)
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_underpriced",
  "seller_id": "seller_004",
  "buyer_id": "buyer_004",
  "category": "photography",
  "product_type": "service",
  "amount": 30.00,
  "commission": 4.50,
  "commission_rate": 15.0,
  "net_to_seller": 25.50,
  "discount_code": null,
  "is_free_trial": false
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, description
FROM leakage_findings 
WHERE transaction_id = 'test_underpriced';

-- Should return:
-- leakage_type: underpriced
-- severity: medium
-- description: mentions "$30.00 is below minimum $50.00"
```

---

### Test 4: Free Trial (Medium)
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_free_trial",
  "seller_id": "seller_005",
  "buyer_id": "buyer_005",
  "category": "consulting",
  "product_type": "service",
  "amount": 0.00,
  "commission": 0.00,
  "commission_rate": 0.0,
  "net_to_seller": 0.00,
  "discount_code": null,
  "is_free_trial": true
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, description
FROM leakage_findings 
WHERE transaction_id = 'test_free_trial';

-- Should return:
-- leakage_type: free_trial_unpaid
-- severity: medium
-- description: mentions "Free trial completed but no payment collected"
```

---

### Test 5: Incorrect Calculation (High)
```bash
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_incorrect_calc",
  "seller_id": "seller_006",
  "buyer_id": "buyer_006",
  "category": "photography",
  "product_type": "service",
  "amount": 100.00,
  "commission": 12.00,
  "commission_rate": 15.0,
  "net_to_seller": 88.00,
  "discount_code": null,
  "is_free_trial": false
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, leakage_amount, description
FROM leakage_findings 
WHERE transaction_id = 'test_incorrect_calc';

-- Should return:
-- leakage_type: wrong_rate
-- severity: high
-- leakage_amount: 3.00
-- description: mentions "claimed 15.0% but calculated as 12.0%"
```

---

## Workflow 3: Discount Validator

### Setup

Get Workflow 3 webhook URL:
```bash
# In n8n, open Workflow 3 → Click webhook node → Copy Production URL
export DISCOUNT_WEBHOOK="https://your-n8n.app/webhook/validate-discount"
```

Ensure discount test data exists:
```sql
-- Should already exist from sql/02_sample_data.sql
SELECT * FROM discount_rules WHERE code IN ('SAVE10', 'EXPIRED', 'MAXED');
```

---

### Test 6: Valid Discount (No Finding)

**Insert transaction:**
```sql
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, created_at)
VALUES ('test_discount_valid', 'seller_007', 'buyer_007', 'photography', 'service', 100.00, 13.50, 15.0, 76.50, 'SAVE10', false, NOW());
```

**Call webhook:**
```bash
curl -X POST "$DISCOUNT_WEBHOOK" \
-H "Content-Type: application/json" \
-d '{
  "transaction_id": "test_discount_valid",
  "discount_code": "SAVE10",
  "gross_amount": 100.00,
  "commission_amount": 13.50,
  "net_to_seller": 76.50
}'
```

**Expected Result:**
```sql
SELECT * FROM leakage_findings WHERE transaction_id = 'test_discount_valid';
-- Should return 0 rows (valid discount, correctly applied)
```

---

### Test 7: Expired Discount Code (High)

**Insert transaction:**
```sql
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, created_at)
VALUES ('test_discount_expired', 'seller_008', 'buyer_008', 'photography', 'service', 100.00, 13.50, 15.0, 76.50, 'EXPIRED', false, NOW());
```

**Call webhook:**
```bash
curl -X POST "$DISCOUNT_WEBHOOK" \
-H "Content-Type: application/json" \
-d '{
  "transaction_id": "test_discount_expired",
  "discount_code": "EXPIRED",
  "gross_amount": 100.00,
  "commission_amount": 13.50,
  "net_to_seller": 76.50
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, description
FROM leakage_findings 
WHERE transaction_id = 'test_discount_expired';

-- Should return:
-- leakage_type: expired_code
-- severity: high
-- description: mentions "expired on 2023-12-31"
```

---

### Test 8: Exceeded Max Uses (Medium)

**Insert transaction:**
```sql
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, created_at)
VALUES ('test_discount_maxed', 'seller_009', 'buyer_009', 'photography', 'service', 100.00, 13.50, 15.0, 76.50, 'MAXED', false, NOW());
```

**Call webhook:**
```bash
curl -X POST "$DISCOUNT_WEBHOOK" \
-H "Content-Type: application/json" \
-d '{
  "transaction_id": "test_discount_maxed",
  "discount_code": "MAXED",
  "gross_amount": 100.00,
  "commission_amount": 13.50,
  "net_to_seller": 76.50
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, description
FROM leakage_findings 
WHERE transaction_id = 'test_discount_maxed';

-- Should return:
-- leakage_type: exceeded_uses
-- severity: medium
-- description: mentions "10/10 uses"
```

---

### Test 9: Below Minimum Purchase (Medium)

**Insert transaction:**
```sql
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, created_at)
VALUES ('test_discount_minimum', 'seller_010', 'buyer_010', 'photography', 'service', 30.00, 3.82, 15.0, 23.18, 'SAVE10', false, NOW());
```

**Call webhook:**
```bash
curl -X POST "$DISCOUNT_WEBHOOK" \
-H "Content-Type: application/json" \
-d '{
  "transaction_id": "test_discount_minimum",
  "discount_code": "SAVE10",
  "gross_amount": 30.00,
  "commission_amount": 3.82,
  "net_to_seller": 23.18
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, description
FROM leakage_findings 
WHERE transaction_id = 'test_discount_minimum';

-- Should return:
-- leakage_type: below_minimum
-- severity: medium
-- description: mentions "$30.00 below minimum $50.00"
```

---

### Test 10: Incorrect Discount Amount (High)

**Insert transaction:**
```sql
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, discount_code, is_free_trial, created_at)
VALUES ('test_discount_wrong', 'seller_011', 'buyer_011', 'photography', 'service', 100.00, 12.75, 15.0, 72.25, 'SAVE10', false, NOW());
```

**Call webhook:**
```bash
curl -X POST "$DISCOUNT_WEBHOOK" \
-H "Content-Type: application/json" \
-d '{
  "transaction_id": "test_discount_wrong",
  "discount_code": "SAVE10",
  "gross_amount": 100.00,
  "commission_amount": 12.75,
  "net_to_seller": 72.25
}'
```

**Expected Result:**
```sql
SELECT leakage_type, severity, leakage_amount, description
FROM leakage_findings 
WHERE transaction_id = 'test_discount_wrong';

-- Should return:
-- leakage_type: incorrect_discount_amount
-- severity: high
-- leakage_amount: 5.00 (should be $10, was $15)
-- description: mentions "applied $15.00 instead of $10.00"
```

---

## Workflow 4: Daily Reporter

### Test 11: Generate Daily Summary

**Setup:**
Ensure you have transactions from "yesterday" in database:
```sql
-- Insert test transactions dated yesterday
INSERT INTO transactions (id, seller_id, buyer_id, category, product_type, gross_amount, commission_amount, commission_rate, net_to_seller, has_leakage, leakage_amount, created_at)
VALUES 
  ('daily_test_1', 'seller_100', 'buyer_100', 'photography', 'service', 100.00, 15.00, 15.0, 85.00, false, 0, CURRENT_DATE - INTERVAL '1 day'),
  ('daily_test_2', 'seller_101', 'buyer_101', 'photography', 'service', 100.00, 10.00, 10.0, 90.00, true, 5.00, CURRENT_DATE - INTERVAL '1 day');

-- Insert corresponding findings
INSERT INTO leakage_findings (transaction_id, leakage_type, severity, leakage_amount, description, created_at)
VALUES ('daily_test_2', 'wrong_rate', 'high', 5.00, 'Test leakage', CURRENT_DATE - INTERVAL '1 day');
```

**Run Workflow 4:**
1. Open Workflow 4 in n8n
2. Click **Execute Workflow** button (top right)
3. Wait for completion (~5-10 seconds)

**Expected Result:**
```sql
SELECT * FROM daily_leakage_summary 
WHERE report_date = CURRENT_DATE - INTERVAL '1 day'
ORDER BY created_at DESC 
LIMIT 1;

-- Should show:
-- total_transactions: 2
-- transactions_with_leakage: 1
-- leakage_percentage: 50.00
-- total_leakage_amount: 5.00
-- total_findings: 1
-- high_findings: 1
```

**Slack Check:**
- If Slack is configured, check channel for daily report
- Should show summary with metrics

---

## Workflow 5: Recovery Manager

### Test 12: Assign Findings to Team

**Setup:**
Ensure unassigned findings exist:
```sql
-- Create test findings with status='detected'
INSERT INTO leakage_findings (transaction_id, leakage_type, severity, leakage_amount, description, status, created_at)
VALUES 
  ('assign_test_1', 'missing_commission', 'critical', 50.00, 'Test finding 1', 'detected', NOW()),
  ('assign_test_2', 'wrong_rate', 'high', 25.00, 'Test finding 2', 'detected', NOW()),
  ('assign_test_3', 'underpriced', 'medium', 10.00, 'Test finding 3', 'detected', NOW());
```

**Run Workflow 5:**
1. Open Workflow 5 in n8n
2. Click **Execute Workflow** button
3. Wait for completion

**Expected Result:**
```sql
SELECT id, transaction_id, severity, assigned_to, status
FROM leakage_findings 
WHERE transaction_id LIKE 'assign_test_%'
ORDER BY leakage_amount DESC;

-- Should show:
-- All 3 findings now have assigned_to filled
-- Status changed to 'investigating'
-- Assigned round-robin to team members
```

**Email Check:**
- Check team members' emails
- Should receive assignment notifications with finding details

---

## Integration Tests

### Test 13: End-to-End Flow

**Complete flow from transaction → detection → reporting → assignment**
```bash
# 1. Send transaction with leakage
curl -X POST "$WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "e2e_test",
  "seller_id": "seller_e2e",
  "buyer_id": "buyer_e2e",
  "category": "photography",
  "product_type": "service",
  "amount": 100.00,
  "commission": 0.00,
  "commission_rate": 0.0,
  "net_to_seller": 100.00,
  "discount_code": null,
  "is_free_trial": false
}'

# 2. Wait 5 seconds for processing

# 3. Verify transaction created
psql -c "SELECT * FROM transactions WHERE id = 'e2e_test';"

# 4. Verify leakage detected
psql -c "SELECT * FROM leakage_findings WHERE transaction_id = 'e2e_test';"

# 5. Run Daily Reporter (manually or wait until 9 AM)
# Execute Workflow 4 in n8n

# 6. Run Recovery Manager (manually or wait 4 hours)
# Execute Workflow 5 in n8n

# 7. Verify finding assigned
psql -c "SELECT assigned_to, status FROM leakage_findings WHERE transaction_id = 'e2e_test';"
```

**Expected:**
- ✅ Transaction in database
- ✅ Finding created (critical, missing_commission)
- ✅ Daily summary includes this finding
- ✅ Finding assigned to team member
- ✅ Status = 'investigating'

---

## Performance Tests

### Test 14: Bulk Transaction Load

**Test processing speed with volume:**
```python
# save as test_bulk.py
import requests
import time
import random

webhook_url = "YOUR_WORKFLOW_1_WEBHOOK_URL"

# Generate 100 test transactions
for i in range(100):
    payload = {
        "id": f"bulk_test_{i}",
        "seller_id": f"seller_{i}",
        "buyer_id": f"buyer_{i}",
        "category": "photography",
        "product_type": "service",
        "amount": round(random.uniform(50, 500), 2),
        "commission": 0 if i % 10 == 0 else round(random.uniform(5, 75), 2),  # 10% missing commission
        "commission_rate": 15.0,
        "net_to_seller": round(random.uniform(40, 400), 2),
        "discount_code": None,
        "is_free_trial": False
    }
    
    start = time.time()
    response = requests.post(webhook_url, json=payload)
    elapsed = time.time() - start
    
    print(f"Transaction {i}: {response.status_code} in {elapsed:.2f}s")
    time.sleep(0.1)  # Small delay to avoid rate limits
```

**Expected:**
- Average processing time: < 2 seconds per transaction
- All transactions appear in database
- ~10 findings created (10% with missing commission)

---

## Troubleshooting Tests

### Check Workflow Executions

**In n8n UI:**
1. Click **Executions** (sidebar)
2. Filter by workflow
3. Look for any red X (failures)
4. Click failed execution to see error details

### Check Database State
```sql
-- Count transactions by date
SELECT DATE(created_at) as date, COUNT(*) 
FROM transactions 
GROUP BY DATE(created_at) 
ORDER BY date DESC;

-- Count findings by severity
SELECT severity, COUNT(*), SUM(leakage_amount) 
FROM leakage_findings 
GROUP BY severity;

-- Check unassigned findings
SELECT COUNT(*) 
FROM leakage_findings 
WHERE status = 'detected';

-- Recent executions
SELECT transaction_id, leakage_type, created_at 
FROM leakage_findings 
ORDER BY created_at DESC 
LIMIT 10;
```

---

## Test Results Summary

**After running all tests, you should have:**

| Test Category | Pass Criteria |
|---------------|---------------|
| Transaction Capture | 1 transaction, no leakage |
| Transaction Validator | 5 findings (critical, high, medium) |
| Discount Validator | 4 findings (expired, maxed, minimum, wrong amount) |
| Daily Reporter | 1 summary with correct metrics |
| Recovery Manager | 3 findings assigned to team |
| **Total** | **10+ findings created** |

**Final Verification:**
```sql
-- Should show 10+ test findings
SELECT leakage_type, severity, COUNT(*) 
FROM leakage_findings 
WHERE transaction_id LIKE 'test_%' OR transaction_id LIKE 'assign_%'
GROUP BY leakage_type, severity;
```

---

## Cleanup Test Data

**After testing, clean up:**
```sql
-- Remove test transactions
DELETE FROM transactions 
WHERE id LIKE 'test_%' 
   OR id LIKE 'bulk_%' 
   OR id LIKE 'e2e_%'
   OR id LIKE 'assign_%'
   OR id LIKE 'daily_%';

-- Remove test findings
DELETE FROM leakage_findings 
WHERE transaction_id LIKE 'test_%' 
   OR transaction_id LIKE 'bulk_%'
   OR transaction_id LIKE 'e2e_%'
   OR transaction_id LIKE 'assign_%'
   OR transaction_id LIKE 'daily_%';

-- Remove test summaries
DELETE FROM daily_leakage_summary 
WHERE report_date = CURRENT_DATE - INTERVAL '1 day';

-- Verify cleanup
SELECT COUNT(*) FROM transactions WHERE id LIKE '%test%';  -- Should be 0
SELECT COUNT(*) FROM leakage_findings WHERE transaction_id LIKE '%test%';  -- Should be 0
```

---

**All tests passing?** 🎉 Your system is ready for production!

**Found issues?** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
