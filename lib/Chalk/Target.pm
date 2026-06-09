# ABOUTME: Bootstrap-tier abstract base class for Chalk code generation targets.
# ABOUTME: Defines the generate()/generate_distribution() contract for Bootstrap-family backends.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# Chalk::Target — the Bootstrap-tier base for code-generation backends.
#
# Interface contract:
#   generate($ir) -> $artifact
#     Accepts a higher-level IR representation (e.g. parsed AST, MOP structure).
#     This is the canonical entry for the Bootstrap-family targets (Perl/C/XS).
#
#   generate_distribution($ir) -> $artifact
#     Accepts a higher-level IR representation and generates a distributable artifact.
#
# Subclasses implement generate() and/or generate_distribution().
# Both entries are stubs here — calling without overriding is a hard error.
#
# Typed-IR backends (e.g. LLVM) use Chalk::IR::Target instead, which provides
# the lower($graph) contract. These two tiers are intentionally separate so
# Bootstrap targets do not inherit alien lower() stubs and typed-IR targets do
# not inherit alien generate() stubs.
#
# Compat: Chalk::Bootstrap::Target is a compat alias for this class.
# The Bootstrap consumers that use Chalk::Bootstrap::Target continue to work
# without change; they reference the alias, which resolves to this class.

class Chalk::Target {
    method generate($ir) {
        die "Subclass must implement generate()";
    }

    method generate_distribution($ir) {
        die "Subclass must implement generate_distribution()";
    }
}
