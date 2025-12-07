# Contributing to Marketplace Leak Detector

First off, thanks for taking the time to contribute! 🎉

## How Can I Contribute?

### Reporting Bugs

**Before submitting a bug report:**
- Check if the bug has already been reported in [Issues](https://github.com/Etherlabs-dev/marketplace-leak-detector/issues)
- Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

**How to submit a bug report:**
1. Use the bug report template
2. Include n8n execution logs
3. Provide sample data (sanitized)
4. Describe expected vs actual behavior

### Suggesting Features

**Before suggesting a feature:**
- Check [Discussions](https://github.com/Etherlabs-dev/marketplace-leak-detector/discussions) for similar ideas
- Consider if it fits the project scope (revenue leakage detection)

**How to suggest a feature:**
1. Open a discussion in the "Ideas" category
2. Explain the problem it solves
3. Describe your proposed solution
4. Consider implementation complexity

### Pull Requests

**Good first issues:**
- Documentation improvements
- New test cases
- Bug fixes
- Code comments

**Before submitting a PR:**
1. Fork the repo
2. Create a new branch (`feature/your-feature-name`)
3. Test your changes thoroughly
4. Update documentation if needed
5. Write clear commit messages

**PR Guidelines:**
- One feature/fix per PR
- Include tests for new features
- Update CHANGELOG.md
- Follow existing code style (Python code in n8n nodes)

## Development Setup

1. **Clone the repo**
```bash
   git clone https://github.com/Etherlabs-dev/marketplace-leak-detector.git
   cd marketplace-leak-detector
```

2. **Set up Supabase test database**
```bash
   # Run sql/01_create_tables.sql in your test Supabase instance
```

3. **Import workflows to n8n**
   - Import all workflows from `workflows/` folder
   - Configure test Supabase credentials

4. **Run tests**
```bash
   # Follow docs/TESTING.md
```

## Code Style

### Python (n8n code nodes)
- Use meaningful variable names
- Add comments for complex logic
- Handle errors gracefully
- Return data in correct format: `[{'json': {...}}]`

### SQL
- Use lowercase for keywords
- Indent for readability
- Add comments for complex queries

### Markdown
- Use headings hierarchically (h1 → h2 → h3)
- Add code blocks with language tags
- Include examples where helpful

## Community

- **Questions:** [GitHub Discussions](https://github.com/Etherlabs-dev/marketplace-leak-detector/discussions)
- **Twitter:** [@ChukwuAugustus](https://twitter.com/ChukwuAugustus)

## Recognition

Contributors will be:
- Listed in CHANGELOG.md
- Mentioned in release notes
- Added to README contributors section

Thank you for contributing! 🙌
