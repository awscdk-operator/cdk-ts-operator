# Contributing to AWS CDK Operator

Thank you for your interest in contributing to the AWS CDK Operator! We welcome contributions from the community and are pleased to have you aboard.

## 🤝 Ways to Contribute

- **Bug Reports**: Report bugs and issues
- **Feature Requests**: Suggest new features or improvements
- **Code Contributions**: Submit pull requests with fixes or enhancements
- **Documentation**: Improve documentation, examples, and tutorials
- **Testing**: Help test the operator in different environments

## 🚀 Getting Started

### Prerequisites

- Docker
- Kubernetes cluster (local or remote)
- AWS CLI configured
- Node.js 18+ and npm

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/awscdk-operator/cdk-ts-operator.git
   cd cdk-ts-operator
   ```

2. **Build the Docker Image**
   ```bash
   docker build . -t awscdk-operator:dev --platform linux/amd64
   ```

3. **Deploy to Test Cluster**
   ```bash
   kubectl apply -f kubernetes/00-crd.yaml
   kubectl apply -f kubernetes/01-operator.yaml
   ```

## 📝 Submitting Changes

### Pull Request Process

1. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Your Changes**
   - Follow the existing code style
   - Add tests for new features
   - Update documentation as needed

3. **Test Your Changes**
   ```bash
   # Test the operator with your changes
   kubectl apply -f test-cdk-resource.yaml
   kubectl get cdktsstacks
   ```

4. **Commit Your Changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

### Commit Message Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `style:` Code style changes
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: add lifecycle hooks support
fix: resolve credential loading issue
docs: update installation instructions
```

## 🧪 Testing

### Manual Testing

1. **Test Basic Functionality**
   ```bash
   # Apply test resource
   kubectl apply -f test-cdk-resource.yaml
   
   # Monitor status
   kubectl get cdktsstacks -w
   
   # Check logs
   kubectl logs -n awscdk-operator-system deployment/awscdk-operator
   ```

2. **Test Different Scenarios**
   - Deploy new stack
   - Update existing stack
   - Delete stack
   - Test drift detection
   - Test lifecycle hooks

### Integration Testing

- Test with different CDK projects
- Test with various AWS regions
- Test error scenarios
- Test with different Kubernetes versions

## 📋 Code Guidelines

### Shell Script Standards

- Use `#!/usr/bin/env bash` shebang
- Set `set -euo pipefail` for error handling
- Use double quotes for variables: `"${VARIABLE}"`
- Add comments for complex logic
- Follow existing naming conventions

### Error Handling

- Always check exit codes
- Provide meaningful error messages
- Log errors with context
- Clean up resources on failure

### Security Best Practices

- Never hardcode credentials
- Validate all inputs
- Use least privilege access
- Sanitize user-provided scripts in lifecycle hooks

## 🐛 Reporting Issues

### Bug Reports

Please include:

1. **Environment Information**
   - Kubernetes version
   - Operator version
   - AWS region
   - CDK version

2. **Steps to Reproduce**
   - Exact commands run
   - YAML manifests used
   - Expected vs actual behavior

3. **Logs and Output**
   ```bash
   kubectl logs -n awscdk-operator-system deployment/awscdk-operator
   kubectl describe cdktsstack <your-stack-name>
   ```

### Feature Requests

Please describe:

- **Use Case**: What problem does this solve?
- **Proposed Solution**: How should it work?
- **Alternatives**: Other ways to achieve this
- **Additional Context**: Any other relevant information

## 🔍 Code Review Process

1. **Automated Checks**: All PRs must pass automated tests
2. **Manual Review**: Core maintainers will review your code
3. **Discussion**: Address any feedback or suggestions
4. **Approval**: Once approved, your PR will be merged

### Review Criteria

- Code quality and style
- Test coverage
- Documentation updates
- Security considerations
- Backward compatibility

## 🏷️ Release Process

Releases follow semantic versioning (SemVer):

- **Major** (1.0.0): Breaking changes
- **Minor** (0.1.0): New features, backward compatible
- **Patch** (0.0.1): Bug fixes, backward compatible

## 📞 Getting Help

- **GitHub Discussions**: For questions and community support
- **GitHub Issues**: For bug reports and feature requests
- **Email**: [belov38@gmail.com](mailto:belov38@gmail.com) for direct contact

## 🙏 Recognition

All contributors will be recognized in our README and release notes. Thank you for helping make this project better!

---

By contributing, you agree that your contributions will be licensed under the project's MIT License. 