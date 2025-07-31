# Contributing

We welcome contributions to the AWS CDK Operator! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally
3. Create a feature branch for your changes
4. Make your changes and test them
5. Submit a pull request

## Development Setup

### Prerequisites

- Kubernetes cluster (local or remote)
- Docker for building images
- Helm 3.x for testing charts
- AWS CLI configured with test credentials
- Git for version control

### Local Development

```bash
# Clone the repository
git clone https://github.com/awscdk-operator/cdk-ts-operator.git
cd cdk-ts-operator

# Build operator image
docker build -t awscdk-operator:dev .

# Deploy to test cluster
helm install awscdk-operator-dev ./charts/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --create-namespace \
  --set image.tag=dev \
  --set operator.env.debugMode=true
```

## Contributing Guidelines

### Code Style

- Follow shell scripting best practices
- Use meaningful variable names
- Add comments for complex logic
- Include error handling and validation

### Testing

Before submitting a pull request:

1. Test your changes with real CDK stacks
2. Verify operator logs don't show errors
3. Test both success and failure scenarios
4. Update documentation if needed

### Documentation

- Update relevant documentation files
- Add examples for new features
- Update the changelog
- Ensure all public APIs are documented

## Types of Contributions

### Bug Fixes

- Include reproduction steps
- Add test cases if applicable
- Update documentation if the bug was in documented behavior

### New Features

- Discuss major features in an issue first
- Include comprehensive tests
- Update documentation and examples
- Ensure backward compatibility

### Documentation

- Fix typos and improve clarity
- Add missing documentation
- Update outdated information
- Add new examples

### Examples

- Add real-world use cases
- Include complete, working examples
- Document any prerequisites
- Test examples before submitting

## Pull Request Process

1. **Create an Issue**: For significant changes, create an issue first to discuss the approach
2. **Fork and Branch**: Fork the repository and create a feature branch
3. **Make Changes**: Implement your changes with appropriate tests
4. **Test Thoroughly**: Test your changes in a real Kubernetes environment
5. **Update Documentation**: Update docs and examples as needed
6. **Submit PR**: Create a pull request with a clear description

### PR Requirements

- [ ] Clear description of changes
- [ ] Tests pass (if applicable)
- [ ] Documentation updated
- [ ] Examples tested (if applicable)
- [ ] No breaking changes (or clearly documented)

## Development Workflow

### Branch Naming

Use descriptive branch names:
- `feature/add-health-checks`
- `bugfix/fix-drift-detection`
- `docs/update-examples`

### Commit Messages

Use clear, descriptive commit messages:
```
Add health check endpoints

- Implement liveness and readiness probes
- Add health check configuration to Helm chart
- Update documentation with health check examples
```

### Testing Changes

```bash
# Apply your changes to a test cluster
kubectl apply -f your-test-manifest.yaml

# Monitor operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f

# Test different scenarios
kubectl delete cdktsstack test-stack
kubectl apply -f test-stack.yaml
```

## Code Organization

### Project Structure

```
awscdk-operator/
├── operator/
│   ├── Dockerfile
│   └── hooks/
│       ├── 00-cdkstack-events.sh    # Main operator logic
│       ├── 10-drift-checker.sh      # Drift detection
│       └── lib/                     # Shared libraries
├── charts/
│   └── aws-cdk-operator/            # Helm chart
├── examples/                        # Example configurations
└── docs/                           # Documentation
```

### Adding New Features

1. **Hook Scripts**: Add new functionality in `operator/hooks/`
2. **Configuration**: Update Helm chart values and templates
3. **Examples**: Add working examples in `examples/`
4. **Documentation**: Update relevant documentation

## Release Process

### Versioning

We use semantic versioning (semver):
- `MAJOR.MINOR.PATCH`
- Major: Breaking changes
- Minor: New features, backward compatible
- Patch: Bug fixes, backward compatible

### Release Checklist

- [ ] Update version in Chart.yaml
- [ ] Update CHANGELOG.md
- [ ] Test with example configurations
- [ ] Create GitHub release
- [ ] Update documentation

## Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Help others learn and contribute
- Focus on the technical merit of contributions

### Communication

- Use GitHub issues for bug reports and feature requests
- Use GitHub discussions for questions and general discussion
- Be patient and helpful with new contributors
- Provide clear, actionable feedback in PR reviews

## Getting Help

If you need help contributing:

1. Check existing issues and documentation
2. Create a GitHub issue with your question
3. Join our community discussions
4. Ask for help in your pull request

## Recognition

Contributors are recognized in:
- GitHub contributors list
- Release notes for significant contributions
- Documentation acknowledgments

Thank you for contributing to the AWS CDK Operator! 