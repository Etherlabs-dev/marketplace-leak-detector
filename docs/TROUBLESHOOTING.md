# Troubleshooting Guide

Solutions to common issues with Marketplace Leak Detector.

---

## Quick Diagnostics

**Before troubleshooting, check:**
1. ✅ All 5 workflows are **Active** (toggle ON)
2. ✅ Supabase credentials configured correctly in n8n
3. ✅ Pricing rules exist in database for test categories
4. ✅ Webhook URLs are correct (https://, not localhost)

---

## Workflow Issues

### ❌ Workflow Not Triggering

**Symptoms:**
- Send webhook → No execution appears in n8n
- Workflow shows as Active but nothing happens

**Solutions:**

**1. Check Workflow is Active**
- Open workflow in n8n
- Toggle at top right should be ON (blue)
- If gray, click to activate

**2. Verify Webhook URL**
```bash
# Click webhook node → Copy Production URL
# Should start with https:// (NOT http://)
# Should NOT be localhost or 127.0.0.1

# Test with curl:
curl -X POST "YOUR_WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{"test": "data"}'

# Should return: "Workflow executed successfully"
```

**3. Check n8n Execution Log**
- Go to **Executions** (sidebar)
- Look for failed executions (red X)
- Click to see error details

**4. Test Webhook in Browser**
- Paste webhook URL in browser
- Should see: "GET method not allowed" (expected - means webhook is working)

---

### ❌ Python Code Errors

**Symptoms:**
- Workflow shows red X
- Error mentions "Python", "KeyError", "NameError"

**Common Errors:**

**Error: `KeyError: 'amount'`**
```
Cause: Transaction data structure doesn't match expected format

Fix:
1. Check transaction data being sent matches schema
2. In Python node, add error handling:

# Before:
amount = items[0]['json']['amount']

# After:
amount = items[0]['json'].get('amount', 0)
```

**Error: `NameError: name 'math' is not defined`**
```
Cause: Missing import statement

Fix: Add at top of Python code:
import math
from datetime import datetime
```

**Error: `TypeError: '>' not supported between 'str' and 'float'`**
```
Cause: Comparing wrong data types

Fix: Cast to correct type:
amount = float(items[0]['json']['amount'])
```

**Debug Python Code:**
```python
# Add this at top of Python node to see what data you're getting:
print("DEBUG - Input data:", items)

# Check execution log to see printed values
```

---

### ❌ Supabase Connection Failed

**Symptoms:**
- Error: "Connection refused"
- Error: "Invalid API key"
- Error: "404 Not Found"

**Solutions:**

**1. Verify Credentials**
- Go to n8n **Credentials**
- Find "Supabase - Marketplace"
- Click edit
- Check:
  - **Host:** Must be `https://YOUR_PROJECT.supabase.co` (include https://)
  - **Service Role Secret:** Should be long JWT starting with `eyJ...`
  - NOT the `anon` key (different one)

**2. Test Connection**
```bash
# Get these from Supabase dashboard → Settings → API
PROJECT_URL="https://YOUR_PROJECT.supabase.co"
SERVICE_KEY="YOUR_SERVICE_ROLE_KEY"

# Test API:
curl "$PROJECT_URL/rest/v1/transactions?limit=1" \
-H "apikey: $SERVICE_KEY" \
-H "Authorization: Bearer $SERVICE_KEY"

# Should return JSON (even if empty: [])
# If error → credentials are wrong
```

**3. Check Supabase Project Status**
- Go to Supabase dashboard
- Check project is active (not paused)
- Free tier pauses after 1 week inactivity

**4. Verify Table Permissions**
```sql
-- In Supabase SQL Editor, check RLS policies:
SELECT tablename, policyname 
FROM pg_policies 
WHERE schemaname = 'public';

-- If RLS is enabled and blocking:
ALTER TABLE transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE leakage_findings DISABLE ROW LEVEL SECURITY;
-- (Repeat for all tables)
```

---

### ❌ No Leakage Detected (When There Should Be)

**Symptoms:**
- Transaction has obvious errors
- No finding created in `leakage_findings` table
- `has_leakage` stays `false`

**Solutions:**

**1. Check Pricing Rules Exist**
```sql
-- Verify rule exists for transaction category
SELECT * FROM pricing_rules 
WHERE category = 'photography' -- use your category
AND is_active = true;

-- If no results, insert pricing rule:
INSERT INTO pricing_rules (category, product_type, base_take_rate, minimum_price, is_active)
VALUES ('photography', 'service', 15.0, 50.00, true);
```

**2. Check Validation Logic**
- Open Workflow 2
- Find "Calculate Leakage" Python node
- Click **Execute node** to test with sample data
- Check output in n8n

**3. Verify Rounding Tolerance**
```python
# In Python validation code:
tolerance = 0.01  # 1 cent

# If leakage is $0.009, it won't be flagged
# Solution: Lower tolerance or adjust calculation
tolerance = 0.001  # More sensitive
```

**4. Check Workflow Execution Order**
```
Transaction → Workflow 1 (Save) → Workflow 2 (Validate)
                    ↓
           Must trigger Workflow 2!
```

Verify HTTP Request node in Workflow 1 has correct Workflow 2 webhook URL.

---

## Data Issues

### ❌ Transactions Not Appearing in Database

**Solutions:**

**1. Check Transaction ID Uniqueness**
```sql
-- If transaction ID already exists, insert fails silently
SELECT id, created_at FROM transactions 
WHERE id = 'YOUR_TEST_ID';

-- If exists, use different ID or delete old one:
DELETE FROM transactions WHERE id = 'YOUR_TEST_ID';
```

**2. Check Data Types Match**
```sql
-- View table structure:
\d transactions

-- Common type mismatches:
-- amount: Should be numeric/decimal, not string "100.00"
-- created_at: Should be timestamp, not string
```

**3. Check for SQL Constraints**
```sql
-- See if any constraints are blocking inserts:
SELECT conname, contype, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'transactions'::regclass;

-- If NOT NULL constraint on optional field, make it nullable:
ALTER TABLE transactions ALTER COLUMN discount_code DROP NOT NULL;
```

---

### ❌ Findings Created for Valid Transactions

**Symptoms:**
- False positives (flagging correct transactions)
- Too many low-severity findings

**Solutions:**

**1. Adjust Severity Thresholds**
```python
# In Workflow 2 Python code, adjust thresholds:

# Current:
if leakage_amount > 50:
    severity = 'high'
elif leakage_amount > 10:
    severity = 'medium'
else:
    severity = 'low'

# Make less sensitive:
if leakage_amount > 100:  # Increased from 50
    severity = 'high'
elif leakage_amount > 25:  # Increased from 10
    severity = 'medium'
else:
    severity = 'low'
```

**2. Increase Rounding Tolerance**
```python
# Allow more floating-point error
tolerance = 0.05  # 5 cents instead of 1 cent
```

**3. Add Whitelisted Sellers**
```python
# Don't flag certain sellers (test accounts, etc.)
whitelisted_sellers = ['seller_test', 'seller_demo']

if seller_id in whitelisted_sellers:
    return []  # Don't create findings
```

---

## Slack Integration Issues

### ❌ Slack Notifications Not Sending

**Solutions:**

**1. Verify Webhook URL**
```bash
# Test Slack webhook directly:
curl -X POST "YOUR_SLACK_WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{"text": "Test from Marketplace Leak Detector"}'

# Should post to Slack channel immediately
# If error → webhook URL is wrong or expired
```

**2. Check Slack Node Configuration**
- Open workflow with Slack node
- Click Slack node
- Verify:
  - **Webhook URL** is filled
  - URL starts with `https://hooks.slack.com/services/...`
  - No extra spaces in URL

**3. Slack Webhook Expired**
- Slack webhooks can be revoked
- Create new webhook in Slack
- Update all workflows with new URL

**4. Disable Slack (Temporary Fix)**
- If Slack not critical, disable node:
- Click Slack node → Click **Disable** (node turns gray)
- Workflow continues without Slack

---

## Performance Issues

### ❌ Slow Execution (> 5 seconds per transaction)

**Solutions:**

**1. Check Supabase Region**
- Use Supabase region closest to n8n instance
- Free tier only has certain regions
- Paid tier has more regions

**2. Add Database Indexes**
```sql
-- Speed up common queries:
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE INDEX idx_findings_status ON leakage_findings(status);
CREATE INDEX idx_findings_transaction_id ON leakage_findings(transaction_id);
```

**3. Optimize Python Code**
```python
# Avoid unnecessary loops:
# Bad:
for item in items:
    for rule in pricing_rules:
        # ...

# Good:
pricing_rule = next((r for r in pricing_rules if r['category'] == category), None)
```

**4. Use Batch Processing**
- Instead of validating each transaction in real-time
- Queue transactions and validate in batches
- Process batch every 5 minutes

---

### ❌ Running Out of n8n Executions (Free Tier)

**Solutions:**

**1. Reduce Scheduled Workflow Frequency**
```
Daily Reporter: Once per day (keep)
Recovery Manager: Change from every 4 hours → once per day
```

**2. Disable Non-Critical Workflows**
- Disable Workflow 3 (Discount Validator) if not using discounts
- Disable Workflow 5 (Recovery Manager) if manually assigning

**3. Upgrade n8n Plan**
- n8n Cloud: $20/month for 5,000 executions
- Self-hosted: Unlimited executions

---

## Testing Issues

### ❌ Test Transactions Not Detected

**Solutions:**

**1. Ensure Sample Data Loaded**
```sql
-- Check pricing rules exist:
SELECT * FROM pricing_rules;

-- If empty, run:
\i sql/02_sample_data.sql
```

**2. Use Exact Test Data**
```bash
# Don't modify test transaction amounts
# Tests expect specific values to trigger leakage
```

**3. Check Test Transaction IDs**
```sql
-- Don't reuse transaction IDs
-- Each test needs unique ID

-- Clean up old test data:
DELETE FROM transactions WHERE id LIKE 'test_%';
DELETE FROM leakage_findings WHERE transaction_id LIKE 'test_%';
```

---

## n8n-Specific Issues

### ❌ Can't Import Workflow JSON

**Solutions:**

**1. Check n8n Version**
- Workflows require n8n v1.0+
- Update: `npm update -g n8n` (self-hosted)

**2. Fix JSON Format**
```bash
# Validate JSON syntax:
cat workflows/01_transaction_monitor.json | jq .

# If error → JSON is malformed
# Copy from GitHub again
```

**3. Import Step-by-Step**
- Import Workflow 1 first (no dependencies)
- Then 2, 3, 4, 5 in order
- Configure credentials after each import

---

### ❌ Credentials Not Saved

**Solutions:**

**1. Clear Browser Cache**
- n8n credential save issues sometimes due to cache
- Clear cache and reload n8n

**2. Use Different Browser**
- Try Chrome/Firefox if using Safari
- Try incognito mode

**3. Check n8n Logs**
```bash
# Self-hosted:
docker logs n8n

# Look for credential errors
```

---

## Recovery Workflow Issues

### ❌ Findings Not Assigned to Team

**Solutions:**

**1. Check Team Member List**
```python
# In Workflow 5, verify team_members list:
team_members = [
    {'email': 'actual@email.com', 'name': 'Name'},
    # Must have at least one team member
]
```

**2. Check Finding Status**
```sql
-- Only 'detected' findings get assigned
SELECT status, COUNT(*) 
FROM leakage_findings 
GROUP BY status;

-- If all 'investigating', they won't be reassigned
-- Reset for testing:
UPDATE leakage_findings 
SET status = 'detected', assigned_to = NULL 
WHERE transaction_id LIKE 'test_%';
```

**3. Manually Trigger Workflow**
- Open Workflow 5
- Click **Execute Workflow**
- Check execution log for errors

---

## Database Issues

### ❌ "Table does not exist" Error

**Solutions:**

**1. Verify Tables Created**
```sql
-- List all tables:
\dt

-- Should show:
-- pricing_rules
-- discount_rules
-- transactions
-- leakage_findings
-- daily_leakage_summary
```

**2. Re-run Table Creation**
```sql
-- Drop and recreate (WARNING: deletes all data):
DROP TABLE IF EXISTS leakage_findings CASCADE;
DROP TABLE IF EXISTS daily_leakage_summary CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS discount_rules CASCADE;
DROP TABLE IF EXISTS pricing_rules CASCADE;

-- Then run:
\i sql/01_create_tables.sql
```

**3. Check Schema**
```sql
-- Tables should be in 'public' schema:
SELECT schemaname, tablename 
FROM pg_tables 
WHERE schemaname = 'public';
```

---

## Still Having Issues?

**1. Enable Debug Mode**
```python
# Add to Python nodes:
import sys
print("DEBUG:", sys.version, file=sys.stderr)
print("Input:", items, file=sys.stderr)

# Check n8n execution log for debug output
```

**2. Check n8n Community**
- [n8n Community Forum](https://community.n8n.io)
- Search for error messages
- Ask questions with workflow screenshots

**3. Open GitHub Issue**
- [Create issue](https://github.com/Etherlabs-dev/marketplace-leak-detector/issues)
- Include:
  - n8n version
  - Supabase region
  - Error message (full text)
  - Screenshot of failed execution
  - Sample transaction data (sanitized)

**4. Contact Developer**
- [Book consultation](YOUR_CALENDAR_LINK)
- [Email](mailto:ethercess@proton.me)
- [Contra](YOUR_CONTRA_LINK)

---

**Pro Tip:** Most issues are caused by:
1. Inactive workflows (toggle ON!)
2. Wrong Supabase credentials
3. Missing pricing rules
4. Transaction ID conflicts

Check these four things first before deep troubleshooting. ✅
