# ABOUTME: Abstract base class for Chalk code generation targets.
# ABOUTME: Defines the lower(graph)->artifact contract; Bootstrap::Target is a compat alias.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# Chalk::Target — the common base for all code-generation backends.
#
# Interface contract (F2-iface decision, 2026-06-09):
#   lower($graph_or_node) -> $artifact
#     Accepts a graph entry-point (typically a Return node or IR graph object)
#     and returns the backend-specific lowered artifact (text, object, etc.).
#     This is the canonical entry for typed-IR backends (e.g. LLVM).
#
#   generate($ir) -> $artifact
#     Accepts a higher-level IR representation (e.g. parsed AST, MOP structure).
#     This is the canonical entry for the Bootstrap-family targets (Perl/C/XS).
#     generate() is provided here as a stub so both families share a common base.
#
# Subclasses implement whichever entry applies to their tier.
# Both entries are stubs here — calling without overriding is a hard error.
#
# Compat: Chalk::Bootstrap::Target is a compat alias for this class.
# The ~153 Bootstrap consumers that use Chalk::Bootstrap::Target continue to
# work without change; they reference the alias, which resolves to this class.
# The full Bootstrap-target family migration is tracked separately.

class Chalk::Target {
    method lower($graph_or_node) {
        die ref($self) . " must implement lower()";
    }

    method generate($ir) {
        die "Subclass must implement generate()";
    }

    method generate_distribution($ir) {
        die "Subclass must implement generate_distribution()";
    }
}
