# ABOUTME: Typed-IR-tier abstract base for code generation backends that accept typed SoN graphs.
# ABOUTME: Defines the lower(graph)->artifact contract for IR-lowering backends (e.g. LLVM).
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# Chalk::IR::Target — the base for typed-IR lowering backends.
#
# Interface contract:
#   lower($graph_or_node) -> $artifact
#     Accepts a typed SoN graph entry-point (typically a Return node) and returns
#     the backend-specific lowered artifact (LLVM IR text, object file, etc.).
#     This is the typed-IR-tier entry; backends that accept a higher-level IR
#     (parsed AST, MOP structures) belong under Chalk::Target instead.
#
# Subclasses must override lower(). The stub here is a hard-error die so callers
# that reach this base know immediately that the subclass did not implement it.
#
# Note: Chalk::Target::LLVM uses lower() as a CLASS method (sub lower { my ($class,...) }).
# This base matches that convention by providing a die-stub accessible via the
# class method calling convention.

class Chalk::IR::Target {
    method lower($graph_or_node) {
        die ref($self) . " must implement lower() — typed-IR tier entry point";
    }
}
