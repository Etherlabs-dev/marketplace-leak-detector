# Installation Guide

Complete setup guide for Marketplace Take-Rate Leak Detector.

**Time required:** 20-30 minutes

---

## Prerequisites

### Required
- ✅ [n8n account](https://n8n.io) (cloud or self-hosted v1.0+)
- ✅ [Supabase account](https://supabase.com) (free tier sufficient)

### Optional
- Slack workspace (for alerts)
- Postman (for testing)

---

## Step 1: Set Up Supabase Database

### 1.1 Create Supabase Project

1. Go to [Supabase](https://supabase.com)
2. Click "New project"
3. Fill in:
   - **Name:** marketplace-leak-detector
   - **Database Password:** (save this!)
   - **Region:** Closest to your users
4. Wait 2-3 minutes for project creation

### 1.2 Create Database Tables

1. In Supabase, go to **SQL Editor**
2. Click **New query**
3. Copy entire contents of `sql/01_create_tables.sql`
4. Paste and click **Run**
5. Verify: Go to **Table Editor** → Should see 5 tables:
   - `pricing_rules`
   - `discount_rules`
   - `transactions`
   - `leakage_findings`
   - `daily_leakage_summary`

### 1.3 Insert Sample Data (Optional)
```sql
-- Copy from sql/02_sample_data.sql and run in SQL Editor
```

### 1.4 Get API Credentials

1. Go to **Settings** → **API**
2. Copy these values:
   - **Project URL:** `https://xxxxx.supabase.co`
   - **anon public key:** `eyJ...` (long string)
   - **service_role key:** `eyJ...` (even longer string)
3. Save these somewhere safe!

---

## Step 2: Set Up n8n

### 2.1 Create n8n Account (if needed)

**Option A: n8n Cloud (Recommended)**
1. Go to [n8n.cloud](https://n8n.cloud)
2. Sign up for free trial or paid plan
3. Create your first workflow

**Option B: Self-hosted**
```bash
npx n8n
# Or use Docker:
docker run -it --rm \
  --name n8n \
  -p 5678:5678 \
  -v ~/.n8n:/home/node/.n8n \
  n8nio/n8n
```

### 2.2 Configure Supabase Credentials

1. In n8n, go to **Credentials** (sidebar)
2. Click **Add Credential**
3. Search for "Supabase"
4. Fill in:
   - **Host:** Your Project URL (from Step 1.4)
   - **Service Role Secret:** Your service_role key
5. Click **Save**
6. Name it: "Supabase - Marketplace"

---

## Step 3: Import n8n Workflows

Import each workflow in order:

### 3.1 Import Workflow 1: Transaction Monitor

1. In n8n, click **+ Add workflow** (top right)
2. Click **⋮** menu → **Import from File**
3. Select `workflows/01_transaction_monitor.json`
4. Click **Import**

**Configure:**
- Click any **Supabase** node
- Select credential: "Supabase - Marketplace"
- Click **Save**

**Activate:**
- Toggle **Active** switch (top right) to ON
- Copy the webhook URL (click webhook node):
```
  Production URL: https://your-n8n.app/webhook/marketplace/transaction
```
- Save this URL!

### 3.2 Import Workflow 2: Transaction Validator

1. Create new workflow
2. Import `workflows/02_transaction_validator.json`
3. Select Supabase credential on any Supabase node
4. **Activate** the workflow
5. Copy webhook URL:
```
   Production URL: https://your-n8n.app/webhook/validate-transaction
```

**Link to Workflow 1:**
1. Go back to **Workflow 1**
2. Find the **HTTP Request** node (labeled "Trigger Validation")
3. Replace URL with your Workflow 2 webhook URL
4. Save

### 3.3 Import Workflow 3: Discount Validator

1. Create new workflow
2. Import `workflows/03_discount_validator.json`
3. Select Supabase credential
4. **Activate**
5. Copy webhook URL (save for testing)

### 3.4 Import Workflow 4: Daily Reporter

1. Create new workflow
2. Import `workflows/04_daily_reporter.json`
3. Select Supabase credential
4. **(Optional) Configure Slack:**
   - Find **Send Slack Report** node
   - Replace webhook URL with your Slack webhook
   - Or disable this node if not using Slack
5. **Activate**
6. Test by clicking **Execute Workflow** button

### 3.5 Import Workflow 5: Recovery Manager

1. Create new workflow
2. Import `workflows/05_recovery_manager.json`
3. Select Supabase credential
4. **Update team members:**
   - Find **Assign Findings** Python code node
   - Update email addresses to your team:
```python
     team_members = [
         {'email': 'alice@yourcompany.com', 'name': 'Alice'},
         {'email': 'bob@yourcompany.com', 'name': 'Bob'},
         {'email': 'carol@yourcompany.com', 'name': 'Carol'}
     ]
```
5. **Activate**

---

## Step 4: Configure Slack (Optional)

### 4.1 Create Incoming Webhook

1. Go to [Slack API](https://api.slack.com/messaging/webhooks)
2. Click **Create your Slack app**
3. Choose **From scratch**
4. Name: "Marketplace Leak Detector"
5. Select your workspace
6. Go to **Incoming Webhooks** → Activate
7. Click **Add New Webhook to Workspace**
8. Select channel (e.g., #finance-alerts)
9. Copy webhook URL: `https://hooks.slack.com/services/...`

### 4.2 Update Workflows

**In Workflow 2 (Transaction Validator):**
- Find **Send Slack Alert** node
- Replace webhook URL

**In Workflow 4 (Daily Reporter):**
- Find **Send Slack Report** node
- Replace webhook URL

---

## Step 5: Test the System

### 5.1 Quick Test
```bash
curl -X POST "YOUR_WORKFLOW_1_WEBHOOK_URL" \
-H "Content-Type: application/json" \
-d '{
  "id": "test_001",
  "seller_id": "seller_001",
  "buyer_id": "buyer_001",
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

### 5.2 Verify in Supabase
```sql
-- Check transaction was created
SELECT * FROM transactions WHERE id = 'test_001';

-- Check if leakage was detected (underpriced)
SELECT * FROM leakage_findings WHERE transaction_id = 'test_001';
```

**[→ Run full test suite](TESTING.md)**

---

## Step 6: Insert Pricing Rules

Your marketplace needs pricing rules for leakage detection to work:
```sql
-- Example: Photography services
INSERT INTO pricing_rules (
  category,
  product_type,
  base_take_rate,
  minimum_price,
  maximum_price,
  is_active
)
VALUES (
  'photography',
  'service',
  15.0,
  50.00,
  5000.00,
  true
);

-- Add more categories as needed
```

---

## Troubleshooting

**Webhook not receiving data?**
- Check workflow is Active (toggle ON)
- Verify webhook URL is correct
- Test with curl first

**Python errors in n8n?**
- Check n8n version is 1.0+
- Look at execution log for error details
- Verify data structure matches expected format

**Supabase connection failed?**
- Verify credentials are correct
- Check Project URL includes `https://`
- Ensure service_role key is used (not anon key)

**[→ More troubleshooting](TROUBLESHOOTING.md)**

---

## Next Steps

1. ✅ Run the [full test suite](TESTING.md)
2. ✅ Customize pricing rules for your marketplace
3. ✅ Add your team members to Recovery Manager
4. ✅ Set up Slack alerts
5. ✅ Monitor for the first week, then automate

**Need help?** [Open an issue](https://github.com/Etherlabs-dev/marketplace-leak-detector/issues)
