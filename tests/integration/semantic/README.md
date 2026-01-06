<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

# Semantic Validation Engine Integration Tests

This directory contains integration tests for the Semantic Validation Engine, validating its integration with ASTDB and LSP systems.

## Overview

The integration tests verify that the Semantic Validation Engine properly integrates with:

1. **ASTDB Query System** - Ensuring validated AST nodes are properly stored and queryable
2. **LSP Server** - Providing real-time validation and semantic information delivery
3. **End-to-End Pipeline** - Complete semantic analysis from source to queries

## Test Files

### `test_validation_engine_simple_integration.zig`

**Purpose**: Basic integration tests that verify the fundamental integration architecture.

**Test Cases**:
- `validation engine integration - basic functionality` - Verifies basic validation context creation
- `ASTDB integration - basic query functionality` - Tests ASTDB integration points
- `LSP integration - basic message handling` - Validates LSP message handling architecture
- `end-to-end semantic pipeline - integration architecture` - Tests overall pipeline design
- `validation engine performance characteristics` - Performance validation
- `integration test framework validation` - Meta-test for framework validation

### `test_validation_engine_astdb_integration.zig` (Advanced)

**Purpose**: Comprehensive ASTDB integration tests (currently disabled due to module import complexity).

**Planned Features**:
- Real ASTDB query integration with validated AST
- Error reporting through ASTDB diagnostics
- Incremental validation with ASTDB updates
- Performance testing with large ASTDB instances

### `test_validation_engine_lsp_integration.zig` (Advanced)

**Purpose**: Comprehensive LSP integration tests (currently disabled due to module import complexity).

**Planned Features**:
- LSP document lifecycle with validation
- Hover requests with validation engine integration
- Go-to-definition with symbol resolution
- Real-time diagnostics with validation errors
- Performance testing with concurrent LSP requests

### `test_end_to_end_semantic_pipeline.zig` (Advanced)

**Purpose**: Complete end-to-end pipeline tests (currently disabled due to module import complexity).

**Planned Features**:
- Complete pipeline from source to queries
- Complex programs with error handling
- Performance benchmarking
- Memory efficiency validation
- Profile constraint testing

## Running Integration Tests

### Basic Integration Tests
```bash
zig build test-integration
```

### All Tests (including integration)
```bash
zig build test
```

### Integration Tests with Sanitizers
```bash
zig build test-sanitizers
```

## Integration Architecture

The integration tests validate the following architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                Semantic Validation Engine                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Validation  │  │   Error     │  │    Profile          │  │
│  │ Orchestrator│  │  Recovery   │  │   Manager           │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Symbol    │  │    Type     │  │     Type            │  │
│  │  Resolver   │  │   System    │  │   Inference         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                        ASTDB                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     LSP Server                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Hover     │  │ Go-to-Def   │  │   Diagnostics       │  │
│  │  Requests   │  │  Requests   │  │   Publishing        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Performance Requirements

The integration tests enforce the following performance requirements:

- **Validation Performance**: < 10ms for basic validation operations
- **ASTDB Query Performance**: < 10ms for semantic queries
- **LSP Response Performance**: < 50ms for concurrent requests
- **End-to-End Pipeline**: < 200ms for complex programs

## Error Handling

Integration tests validate error handling at multiple levels:

1. **Validation Errors**: Semantic errors detected by the validation engine
2. **Integration Errors**: Failures in component communication
3. **Performance Errors**: Violations of performance requirements
4. **Memory Errors**: Memory leaks or excessive usage

## Future Enhancements

### Phase 1: Module Import Resolution
- Resolve module import issues for advanced integration tests
- Enable comprehensive ASTDB and LSP integration testing
- Add real component integration validation

### Phase 2: Real-World Scenarios
- Add tests with actual Janus source files
- Validate profile-specific behavior
- Test incremental compilation scenarios

### Phase 3: Stress Testing
- Large codebase validation
- Concurrent LSP request handling
- Memory pressure scenarios
- Long-running validation sessions

## Contributing

When adding new integration tests:

1. **Follow Naming Convention**: `test_validation_engine_[component]_integration.zig`
2. **Add Performance Metrics**: Include timing and memory usage validation
3. **Document Test Purpose**: Clear comments explaining what is being tested
4. **Update Build System**: Add new tests to `build.zig`
5. **Update Documentation**: Update this README with new test descriptions

## Troubleshooting

### Module Import Issues
If you encounter module import errors, ensure:
- The test file uses the correct module imports (`@import("astdb")`, `@import("semantic")`)
- The build.zig configuration includes the necessary module dependencies
- File paths are relative to the workspace root

### Performance Test Failures
If performance tests fail:
- Check system load during test execution
- Verify test environment is consistent
- Consider adjusting performance thresholds for different hardware

### Memory Test Failures
If memory tests fail:
- Run with `std.testing.allocator` for leak detection
- Check for proper cleanup in test teardown
- Verify arena allocator usage patterns
