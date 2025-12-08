---
name: Bug Report
about: Report a bug or issue with Marketplace Leak Detector
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description
<!-- A clear description of what the bug is -->

## Steps to Reproduce
1. 
2. 
3. 

## Expected Behavior
<!-- What you expected to happen -->

## Actual Behavior
<!-- What actually happened -->

## Environment
- **n8n version:** (e.g., 1.15.0)
- **Supabase region:** (e.g., US East)
- **Deployment type:** (Cloud / Self-hosted)
- **Browser (if relevant):** (e.g., Chrome 120)

## Workflow Information
**Which workflow is affected?**
- [ ] Workflow 1: Transaction Monitor
- [ ] Workflow 2: Transaction Validator
- [ ] Workflow 3: Discount Validator
- [ ] Workflow 4: Daily Reporter
- [ ] Workflow 5: Recovery Manager

## Error Messages
<!-- Paste any error messages from n8n execution log -->
```
[Paste error here]
```

## Sample Data
<!-- If relevant, provide sample transaction data (sanitized) -->
```json
{
  "id": "example_transaction",
  "amount": 100.00
}
```

## Screenshots
<!-- If applicable, add screenshots to help explain the problem -->

## Database State
<!-- Run this query and paste results if relevant -->
```sql
SELECT COUNT(*) FROM transactions WHERE created_at >= NOW() - INTERVAL '1 day';
SELECT COUNT(*) FROM leakage_findings WHERE status = 'detected';
```

## Additional Context
<!-- Any other context about the problem -->

## Possible Solution
<!-- If you have suggestions on how to fix this -->
