# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-08

### Added
- Initial release of Marketplace Take-Rate Leak Detector
- 5 n8n workflows for automated leakage detection
- Complete Supabase database schema
- Real-time transaction validation
- Discount code validation
- Daily leakage reporting
- Recovery team assignment system
- Slack integration for alerts
- Comprehensive documentation
- Test suite with 10+ test cases
- Example data and Postman collection

### Features
- Detects missing commissions
- Validates commission rates against pricing rules
- Catches underpriced transactions
- Identifies invalid/expired discounts
- Tracks discount usage limits
- Monitors minimum purchase requirements
- Validates discount amount calculations
- Generates daily summaries
- Assigns findings to team members (round-robin)
- Prioritizes by severity and amount

### Documentation
- Installation guide
- Architecture overview
- Testing guide
- Troubleshooting guide
- Contributing guidelines

## [Unreleased]

### Planned
- Shopify integration
- Stripe Billing integration
- Machine learning for anomaly detection
- Mobile dashboard
- Multi-currency support
- Docker compose deployment
- Webhook signature verification
```

---

## 📄 File 5: .gitignore
```
# n8n
*.credentials.json
.env
.env.local

# Logs
*.log
npm-debug.log*

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Test data with real credentials
test-data-real.json

# Backup files
*.bak
*.backup
