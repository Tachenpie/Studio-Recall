# GitHub Configuration

This directory contains configuration files for GitHub features and tooling.

## GitHub Copilot Instructions

This repository includes custom instructions for GitHub Copilot coding agent to provide better code suggestions and assistance.

### Structure

```
.github/
├── README.md                                    ← You are here
├── copilot-instructions.md                      ← Repository-wide instructions
└── instructions/
    ├── managers.instructions.md                 ← Managers & Handlers specific
    ├── models.instructions.md                   ← Data Models specific
    ├── tests.instructions.md                    ← Test files specific
    ├── utilities.instructions.md                ← Utilities & Extensions specific
    └── views.instructions.md                    ← SwiftUI Views specific
```

### Files

#### Repository-Wide Instructions
**File**: `copilot-instructions.md`

Contains general guidelines that apply to all code in the repository:
- Project overview and core technologies
- Build and test procedures
- Code style guidelines
- Architecture patterns
- Data models overview
- JSON persistence
- Platform-specific code
- Security and best practices
- Common pitfalls to avoid

This file is consulted for every Copilot request in the repository.

#### Path-Specific Instructions
**Directory**: `instructions/`

Contains specialized guidelines that apply to specific parts of the codebase. Each file uses the `applyTo:` frontmatter to specify which paths it applies to.

##### `models.instructions.md`
- **Applies to**: `Studio Recall/Models/**`
- **Topics**: 
  - Codable conformance requirements
  - UUID-based identity patterns
  - Enum and control state management
  - Rack grid logic
  - Coordinate systems
  - Visual mappings

##### `views.instructions.md`
- **Applies to**: `Studio Recall/Views/**`
- **Topics**:
  - SwiftUI view architecture
  - State management with property wrappers
  - Platform-specific views (#if os(macOS))
  - Control rendering (photoreal vs representative modes)
  - Hit testing and drag-and-drop
  - Canvas and coordinate systems
  - Metal rendering

##### `tests.instructions.md`
- **Applies to**: `Studio RecallTests/**` and `Studio RecallUITests/**`
- **Topics**:
  - Unit test structure and naming
  - Codable conformance tests
  - Backward compatibility tests
  - State management tests
  - Edge case tests
  - Test fixtures and mocking
  - Performance tests

##### `managers.instructions.md`
- **Applies to**: `Studio Recall/Managers/**` and `Studio Recall/Handlers/**`
- **Topics**:
  - Manager architecture (@MainActor, ObservableObject)
  - SessionManager and DeviceLibrary patterns
  - Unowned references to avoid retain cycles
  - JSON persistence (load/save)
  - Device placement logic (2D racks, 1D chassis)
  - Control value updates
  - Device reconciliation
  - Error handling

##### `utilities.instructions.md`
- **Applies to**: `Studio Recall/Utilities/**` and `Studio Recall/Extensions/**`
- **Topics**:
  - Extension organization and best practices
  - Utility file structure
  - Image, geometry, and color utilities
  - Coordinate system helpers
  - Mask generation
  - File management
  - Platform-specific utilities
  - Value mapping and interpolation
  - Validation utilities

### How It Works

When GitHub Copilot coding agent works on code in this repository:

1. It always reads `copilot-instructions.md` for general context
2. Based on the file path being edited, it automatically reads relevant path-specific instruction files
3. It uses both sets of instructions to provide better, more contextually appropriate suggestions

For example, when editing `Studio Recall/Models/Device.swift`:
- Reads `copilot-instructions.md` (general guidelines)
- Reads `instructions/models.instructions.md` (model-specific guidelines)
- Provides suggestions that follow both sets of rules

### Benefits

✅ **Consistent Code Style**: All Copilot suggestions follow established patterns
✅ **Better Context**: Path-specific instructions provide deep domain knowledge
✅ **Fewer Mistakes**: Guidelines prevent common pitfalls and anti-patterns
✅ **Faster Development**: Less time explaining requirements to Copilot
✅ **Maintainability**: New contributors get automatic guidance via Copilot

### Maintaining Instructions

When making significant changes to the codebase:

1. **Update Relevant Instructions**: Keep instructions in sync with actual code patterns
2. **Add New Sections**: Add guidance for new features or patterns
3. **Remove Outdated Info**: Clean up instructions for removed features
4. **Test Changes**: Verify Copilot provides helpful suggestions after updates

### Related Documentation

- **[CLAUDE.md](../CLAUDE.md)**: Detailed architecture documentation for Claude AI assistant
- **[Documentation/](../Documentation/)**: User guides and technical documentation
- **[README.md](../README.md)**: Project overview and getting started guide

### References

- [GitHub Copilot Custom Instructions Documentation](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions)
- [Best Practices for GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/tutorials/coding-agent/get-the-best-results)

---

**Note**: These instruction files are for GitHub Copilot coding agent only. For detailed architecture documentation and working with Claude AI assistant, see [CLAUDE.md](../CLAUDE.md).
