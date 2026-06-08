# Contributing to CodexBar

Thank you for your interest in contributing to CodexBar! This document provides guidelines and information for contributors.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone git@github.com:YOUR_USERNAME/CodexBar.git`
3. Create a feature branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Run tests: `swift test`
6. Commit your changes: `git commit -m "feat: add your feature"`
7. Push to your fork: `git push origin feature/your-feature`
8. Create a Pull Request

## Development Setup

### Prerequisites

- macOS 14+ (Sonoma)
- Xcode 16+ or Swift 6.2+
- SwiftLint (optional, for linting)
- SwiftFormat (optional, for formatting)

### Building

```bash
# Build the project
swift build

# Build for release
swift build -c release
```

### Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter CodexBarTests
```

### Linting

```bash
# Run SwiftLint
swiftlint lint

# Run SwiftFormat
swiftformat .
```

## Code Style

- Follow the existing code style in the project
- Use Swift 6.2 with strict concurrency
- Keep lines under 120 characters
- Use 4-space indentation
- Add comments for complex logic
- Write tests for new features

## Adding a New Provider

1. Create a new directory in `Sources/CodexBarCore/Providers/YourProvider/`
2. Implement the provider descriptor:
   ```swift
   import CodexBarMacroSupport
   
   @ProviderDescriptorRegistration
   @ProviderDescriptorDefinition
   public enum YourProviderDescriptor {
       static func makeDescriptor() -> ProviderDescriptor {
           ProviderDescriptor(
               id: .yourProvider,
               metadata: ProviderMetadata(...),
               branding: ProviderBranding(...),
               fetchPlan: ProviderFetchPlan(...))
       }
   }
   ```
3. Create a new directory in `Sources/CodexBar/Providers/YourProvider/`
4. Implement the provider:
   ```swift
   import CodexBarCore
   import CodexBarMacroSupport
   
   @ProviderImplementationRegistration
   struct YourProviderImplementation: ProviderImplementation {
       let id: UsageProvider = .yourProvider
       // Implement required methods
   }
   ```
5. Add tests in `Tests/CodexBarTests/YourProviderTests.swift`
6. Update the documentation in `docs/`

## Pull Request Guidelines

- Keep PRs focused on a single change
- Write clear commit messages
- Add tests for new features
- Update documentation as needed
- Ensure all tests pass
- Follow the existing code style

## Reporting Issues

- Use GitHub Issues to report bugs
- Include steps to reproduce the issue
- Include your environment information
- Be respectful and constructive

## License

By contributing to CodexBar, you agree that your contributions will be licensed under the MIT License.
