# ABOUTME: Backwards-compatible alias for Chalk::Target::LLVM::Context.
# ABOUTME: The if/else lowering it used to hold now lives on Context itself.
# ---------------------------------------------------------------------------
# ElaboratedContext WAS a Context subclass whose only job was lowering if/else
# merges, with the base class's _process_if_node a `die "use
# ElaboratedContext"`. That was not a design decision. Two primary sources:
#
#   - commit 3a103d21 (2026-06-07) DELETED the base implementation --
#     "Remove the old Context::_process_if_node implementation (which used the
#      var_table snapshot/restore + union-SSA phi loop) now that all
#      control-flow routes through ElaboratedContext. The base class method is
#      replaced with a guard that dies loudly if called directly."
#     The subclass was the NEW of an old/new pair; the old one is gone and the
#     split outlived it.
#
#   - zhi issue F10 reads it the same way: "_process_if_node/_wire_region_phis
#     are duplicated between Context and ElaboratedContext
#     (copy-paste-with-divergence)". Its stated prerequisite -- the 019eb316
#     cache/identity family (4e0d7ba8, 381229b5, 5c7e49ce, d4823444) -- is
#     landed, so the sequencing constraint is satisfied.
#
# The merge also closed a trapdoor: this package's `new` accepted %args and
# passed them to SUPER::new(%args), which took NO arguments and silently
# discarded them. Context::new now accepts `elab` and `class_registry`
# directly.
#
# The name survives as an alias because callers in lib/ and t/ still use it,
# and because "an elaborated context" remains a meaningful thing to ask for --
# a Context constructed WITH the Elaborate pass's phi records. It is the same
# class either way.
# ---------------------------------------------------------------------------
package Chalk::Target::LLVM::ElaboratedContext;
use 5.42.0;
use utf8;

use Chalk::Target::LLVM::Context;

our @ISA = ('Chalk::Target::LLVM::Context');

1;
