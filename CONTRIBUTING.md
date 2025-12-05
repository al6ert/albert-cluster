# Contributing to Albert Cluster

Thank you for your interest in contributing to Albert Cluster! This document provides guidelines for contributing to this project.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

- Use the GitHub issue tracker
- Include detailed steps to reproduce the bug
- Include your environment details (OS, Kubernetes version, etc.)
- Include logs and error messages

### Suggesting Enhancements

- Use the GitHub issue tracker
- Describe the enhancement clearly
- Explain why this enhancement would be useful
- Include mockups or examples if applicable

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Ensure all CI checks pass
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Development Setup

1. **Prerequisites**:
   - Docker (for Minikube driver)
   - `kubectl`
   - `minikube`
   - `helm`
   - `helmfile`
   - `kubeseal`
   - `jq` (for script output formatting)

   *Tip: You can source `versions.env` to see the recommended versions.*

2. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd albert-cluster
   ```

3. **Start Minikube**:
   ```bash
   minikube start --driver=docker --kubernetes-version=v1.29.2
   ```

4. **Deploy Locally**:
   ```bash
   # This script handles bootstrap and application deployment
   ./deploy-local.sh
   ```

5. **Verify Deployment**:
   ```bash
   ./tests/smoke.sh
   ```

## Code Style

- Follow the existing code style
- Use meaningful commit messages
- Add comments for complex logic
- Keep functions small and focused
- Write tests for new functionality

## Testing

- Write unit tests for new features
- Ensure integration tests pass
- Test on multiple Kubernetes versions
- Test on different environments (minikube, kind, etc.)

## Documentation

- Update README.md if needed
- Add inline documentation for complex code
- Update API documentation if applicable
- Include examples for new features

## Release Process

1. Create a release branch
2. Update version numbers
3. Update CHANGELOG.md
4. Create a GitHub release
5. Tag the release

## Questions?

If you have questions, please open an issue or contact the maintainers.
