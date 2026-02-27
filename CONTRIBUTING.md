# Using Cost Sentinel

This is a portfolio/demonstration project and is **not accepting contributions**. However, you're welcome to fork it and customize it for your own use!

## Getting Started with Your Fork

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/cost-sentinel.git`
3. Install development dependencies: `pip install -r requirements-dev.txt`
4. Install pre-commit hooks: `pre-commit install`
5. Follow the setup instructions in the README

## Development Workflow

### Before Committing

Pre-commit hooks will automatically run:
- Terraform formatting and validation
- Python linting (ruff)
- Secrets detection
- YAML linting

### Testing

```bash
# Run all tests
make ci-test

# Run specific Terraform tests
cd infra/modules/sentinel/tests/basic
terraform test

# Test Lambda locally
cd app/ingestor
python -m pytest tests/
```

### Code Style

- **Terraform**: Follow [HashiCorp style guide](https://www.terraform.io/docs/language/syntax/style.html)
- **Python**: PEP 8 compliant, enforced by ruff
- **Commit messages**: Use conventional commits format

## Customization Ideas

- Add Slack/Teams notifications
- Integrate with AWS Cost Anomaly Detection
- Add multi-account support via AWS Organizations
- Create custom dashboard visualizations
- Add cost forecasting features
- Implement automated cost optimization recommendations

## Questions or Issues?

If you find a bug or have questions about the implementation, feel free to open an issue. While I won't be accepting PRs, I'm happy to discuss the architecture and design decisions.

## Building Your Own Version

This project is licensed under MIT, so you're free to:
- Use it as-is
- Modify it for your needs
- Use it as a learning resource
- Build upon it for your own projects

Just remember to update the configuration with your own AWS account details and bucket names!
