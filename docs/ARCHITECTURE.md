# Architecture Overview

Understanding how the Marketplace Leak Detector works.

---

## System Components
```
┌─────────────────────────────────────────────────────────────┐
│                     Marketplace Platform                     │
│              (Stripe, Custom, Shopify, etc.)                 │
└────────────────────┬────────────────────────────────────────┘
                     │ Transaction webhook
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    n8n Workflow Engine                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Workflow 1  │→ │  Workflow 2  │→ │  Workflow 3  │      │
│  │ Transaction  │  │  Validation  │  │   Discount   │      │
│  │   Monitor    │  │              │  │  Validation  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         ↓                   ↓                  ↓             │
└─────────┼───────────────────┼──────────────────┼────────────┘
          │                   │                  │
          ↓                   ↓                  ↓
┌─────────────────────────────────────────────────────────────┐
│                      Supabase Database                       │
│   • transactions          • leakage_findings                 │
│   • pricing_rules         • daily_leakage_summary            │
│   • discount_rules                                           │
└─────────────────────────────────────────────────────────────┘
          │
          ↓
┌─────────────────────────────────────────────────────────────┐
│                    Reporting & Alerts                        │
│   • Slack notifications    • Daily summaries                 │
│   • Team assignments       • Recovery workflows              │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. Transaction Capture
```
Marketplace → Webhook → Workflow 1 → Supabase (transactions table)
```

**What happens:**
1. Marketplace sends transaction webhook
2. Workflow 1 receives and validates basic structure
3. Transaction saved to Supabase
4. Triggers Workflow 2 via HTTP request

### 2. Leakage Detection
```
Workflow 2 → Fetch Pricing Rules → Calculate Expected → Compare Actual → Detect Leakage
```

**What happens:**
1. Get transaction from database
2. Fetch pricing rules for transaction's category
3. Calculate expected commission
4. Compare with actual commission
5. If leakage > $0.01:
   - Calculate severity
   - Build evidence object
   - Create finding in `leakage_findings`
   - Update transaction with leakage info
   - Send Slack alert (if critical/high)

### 3. Discount Validation
```
Workflow 3 → Check Discount Code → Validate Rules → Calculate Correct Amount → Flag Issues
```

**What happens:**
1. Get transaction with discount code
2. Fetch discount rule from database
3. Validate:
   - Code exists and is active
   - Within valid dates
   - Not exceeded max uses
   - Meets minimum purchase
   - Discount amount is correct
4. Create finding for each issue detected

### 4. Daily Reporting
```
Workflow 4 (9 AM daily) → Aggregate Yesterday's Data → Calculate Metrics → Save Summary → Slack Report
```

**What happens:**
1. Calculate date range (yesterday)
2. Fetch all transactions from yesterday
3. Fetch all findings from yesterday
4. Aggregate:
   - Total transactions vs. transactions with leakage
   - Leakage by type (JSONB breakdown)
   - Severity counts
   - Top 5 sellers with leakage
5. Save to `daily_leakage_summary`
6. Send formatted Slack report

### 5. Recovery Management
```
Workflow 5 (every 4 hours) → Get Unassigned Findings → Assign to Team → Update Status → Email Notification
```

**What happens:**
1. Fetch findings with `status='detected'`
2. Sort by priority (amount × severity)
3. Assign to team members (round-robin)
4. Update status to `investigating`
5. Send email with:
   - Finding details
   - Evidence
   - Recovery instructions

---

## Database Schema

### Table: `pricing_rules`

**Purpose:** Define expected take rates for each category/product type

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| category | text | Product category (e.g., "photography") |
| product_type | text | Type (e.g., "service", "product") |
| base_take_rate | decimal | Expected commission % (e.g., 15.0) |
| minimum_price | decimal | Category minimum price |
| maximum_price | decimal | Category maximum price |
| is_active | boolean | Rule enabled? |

**Used by:** Workflow 2 (Transaction Validator)

---

### Table: `discount_rules`

**Purpose:** Define valid discount codes and their rules

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| code | text | Discount code (e.g., "SAVE10") |
| discount_type | text | "percentage" or "fixed" |
| discount_value | decimal | Amount/percentage off |
| minimum_purchase_amount | decimal | Minimum order value |
| valid_from | timestamp | Start date |
| valid_until | timestamp | End date |
| max_uses | integer | Maximum redemptions |
| current_uses | integer | Times used so far |
| is_active | boolean | Code enabled? |

**Used by:** Workflow 3 (Discount Validator)

---

### Table: `transactions`

**Purpose:** Store all marketplace transactions

| Column | Type | Description |
|--------|------|-------------|
| id | text | Transaction ID (from marketplace) |
| seller_id | text | Seller identifier |
| buyer_id | text | Buyer identifier |
| category | text | Product category |
| product_type | text | Product type |
| gross_amount | decimal | Total transaction amount |
| commission_amount | decimal | Actual commission charged |
| commission_rate | decimal | Actual rate used |
| net_to_seller | decimal | Amount paid to seller |
| discount_code | text | Applied discount (nullable) |
| is_free_trial | boolean | Free trial transaction? |
| has_leakage | boolean | Leakage detected? |
| leakage_amount | decimal | Amount of leakage |
| expected_commission | decimal | What commission should have been |
| expected_rate | decimal | What rate should have been |
| validated_at | timestamp | When validation completed |
| created_at | timestamp | Transaction creation time |

**Used by:** All workflows

---

### Table: `leakage_findings`

**Purpose:** Store detected leakage instances

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| transaction_id | text | FK to transactions |
| leakage_type | text | Type (e.g., "missing_commission") |
| severity | text | critical/high/medium/low |
| leakage_amount | decimal | Dollar amount of leakage |
| description | text | Human-readable description |
| evidence | jsonb | Complete evidence object |
| status | text | detected/investigating/recovering/recovered/written_off |
| assigned_to | text | Team member email |
| created_at | timestamp | Detection time |
| updated_at | timestamp | Last status change |

**Used by:** Workflows 2, 3, 5

---

### Table: `daily_leakage_summary`

**Purpose:** Daily aggregate metrics

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| report_date | date | Summary date |
| total_transactions | integer | Total txns that day |
| transactions_with_leakage | integer | Txns with leakage |
| leakage_percentage | decimal | % with leakage |
| total_leakage_amount | decimal | Total $ leaked |
| leakage_by_type | jsonb | Breakdown by type |
| critical_findings | integer | Critical count |
| high_findings | integer | High count |
| medium_findings | integer | Medium count |
| low_findings | integer | Low count |
| total_findings | integer | Total count |
| top_sellers | jsonb | Top 5 sellers with leakage |
| created_at | timestamp | Summary creation time |

**Used by:** Workflow 4 (Daily Reporter)

---

## Leakage Detection Logic

### Types of Leakage

**1. Missing Commission (Critical)**
```python
if actual_commission == 0:
    leakage_type = 'missing_commission'
    severity = 'critical'
    leakage_amount = expected_commission
```

**2. Wrong Commission Rate (High/Medium)**
```python
if actual_rate < expected_rate:
    leakage_type = 'wrong_rate'
    leakage_amount = expected_commission - actual_commission
    severity = 'high' if leakage_amount > 50 else 'medium'
```

**3. Underpriced Transaction (Medium)**
```python
if gross_amount < minimum_price:
    leakage_type = 'underpriced'
    severity = 'medium'
    # No direct leakage, but violates policy
```

### Severity Levels

| Severity | Criteria | Example |
|----------|----------|---------|
| Critical | No commission collected | $100 sale, $0 commission |
| High | Leakage > $50 OR wrong rate | $100 sale, $10 instead of $15 |
| Medium | Leakage $10-$50 OR policy violation | $30 sale (min is $50) |
| Low | Leakage < $10 | $100 sale, $14.50 instead of $15 |

### Rounding Tolerance
```python
tolerance = 0.01  # 1 cent

if leakage_amount > tolerance:
    # Leakage detected
else:
    # Within acceptable rounding error
```

**Why:** Prevents false positives from floating-point math.

---

## Recovery Workflow

### Status Progression
```
detected → investigating → recovering → recovered
                                     ↓
                              written_off (if unrecoverable)
```

### Assignment Logic

**Round-robin distribution:**
```python
team = ['alice@co.com', 'bob@co.com', 'carol@co.com']

for index, finding in enumerate(findings):
    assignee = team[index % len(team)]
```

**Priority scoring:**
```python
severity_multiplier = {
    'critical': 10,
    'high': 5,
    'medium': 2,
    'low': 1
}

priority = leakage_amount * severity_multiplier[severity]
```

Findings are fetched sorted by priority (highest first).

---

## Performance Considerations

### Scalability

| Volume | Performance | Notes |
|--------|-------------|-------|
| < 1K txns/day | Instant | No optimization needed |
| 1K-10K txns/day | < 1s per txn | Supabase free tier sufficient |
| 10K-100K txns/day | < 2s per txn | Consider Supabase Pro |
| 100K+ txns/day | Batch processing | May need custom optimizations |

### Optimization Tips

**For high volume:**
1. Batch validation instead of real-time
2. Use Supabase indexes on `category`, `created_at`
3. Archive old findings (>90 days)
4. Consider read replicas for reporting

**For low latency:**
1. Use webhook queues (Redis)
2. Async validation (current design)
3. Cache pricing rules in n8n

---

## Security Considerations

### API Keys
- Never commit Supabase keys to Git
- Use service_role key (not anon key) for n8n
- Rotate keys quarterly

### Webhook Security
- Consider adding webhook signature verification
- Use HTTPS only
- Rate limit webhook endpoints

### Data Privacy
- PII is stored in Supabase (consider encryption)
- Evidence objects contain transaction details
- Comply with data retention policies

---

## Extending the System

### Add New Leakage Types

1. **Update Python validation logic** (Workflow 2):
```python
   elif some_new_condition:
       leakage_type = 'new_type'
       severity = 'high'
       description = "New type of leakage detected"
```

2. **Document the new type** in README

### Add New Data Sources

1. **Create new webhook workflow** (similar to Workflow 1)
2. **Map data to transactions table schema**
3. **Trigger existing validation workflows**

### Integrate with Other Platforms

**Shopify example:**
1. Create Shopify webhook in Shopify admin
2. Point to new n8n workflow
3. Transform Shopify data format to match schema
4. Trigger existing validators

---

**Questions about the architecture?** [Open a discussion](https://github.com/Etherlabs-dev/marketplace-leak-detector/discussions)
