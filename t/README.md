# Test Directory Structure

This directory contains the test suite for the Chalk parser project, organized into logical subdirectories based on functionality.

## Directory Layout

### `basic/`
Foundational tests that cover basic parsing functionality and core features:
- `01-simple.t` - Basic parser functionality tests
- `simple-arith.t` - Simple arithmetic expression parsing
- `test-empty-args.t` - Empty argument handling
- `zero-token-fix.t` - Zero-token edge case handling

### `parser/`
Core parsing engine tests covering various parsing strategies and algorithms:
- `02-parser-grammars.t` - Parser grammar handling tests
- `test-ambiguous-baseline.t` - Ambiguous grammar resolution baseline tests
- `test-augmented.t` - Augmented parsing functionality
- `test-generalized.t` - Generalized parsing algorithm tests
- `test-sppf-viterbi.t` - SPPF (Shared Packed Parse Forest) and Viterbi algorithm tests

### `grammar/`
Grammar definition and language-specific parsing tests:
- `test-chalk-complete-grammar.t` - Complete Chalk language grammar tests
- `test-guacamole-nullable.t` - Guacamole nullable rule handling
- `test-guacamole-patterns.t` - Guacamole pattern matching tests
- `test-lexeme-support.t` - Lexeme processing and tokenization
- `test-modern-perl-syntax.t` - Modern Perl syntax parsing support
- `test-zero-length-matches.t` - Zero-length pattern matching

### `optimization/`
Performance optimization and advanced parsing technique tests:
- `test-leo-items.t` - Leo optimization for right-recursive patterns (verifies limited Leo implementation works correctly)

**Planned tests** (not yet implemented):
- `test-left-recursion.t` - Left recursion handling
- `test-left-recursion-performance.t` - Left recursion performance benchmarks
- `test-memoization.t` - Parse result memoization
- `test-nullability.t` - Nullable rule detection
- `test-nullability-optimization.t` - Nullable rule optimization
- `test-prediction-memoization.t` - Prediction phase memoization

## Self-Hosting Test

### `self-hosting.t`
The ultimate validation test for the Chalk parser - testing whether Chalk can successfully parse its own source code. This test:

- Loads the complete Chalk grammar definition
- Attempts to parse the entire `chalk` executable source file
- Validates that all major language constructs are recognized (classes, methods, fields, use declarations)
- Serves as a comprehensive integration test ensuring the grammar is complete enough for real-world Chalk code
- Represents the milestone goal of true self-hosting: a language implementation that can parse itself

This test is critical for validating that the Chalk parser has reached production readiness and grammatical completeness.

## Running Tests

Tests can be run individually or by directory:
```bash
# Run all tests
prove -r t/

# Run specific category
prove t/basic/
prove t/parser/
prove t/grammar/
prove t/optimization/

# Run the self-hosting test
prove t/self-hosting.t
```