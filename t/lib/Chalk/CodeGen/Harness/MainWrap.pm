# ABOUTME: Source-prep that wraps a top-level program body in a synthetic
# ABOUTME: sub __main__ { <body> }, so B::SoN emits a method (not methods: {}).
package Chalk::CodeGen::Harness::MainWrap;

use 5.42.0;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(wrap_main);

# ---------------------------------------------------------------------------
# wrap_main($body) -> "sub __main__ {\n$body\n}\n"
#
# A t/base file (and any harvested conformance case) is a sequence of
# TOP-LEVEL statements, not a sub. B::SoN emits `methods: {}` for a bare
# program body -- there is no CV to walk -- so the body must be wrapped in a
# synthetic sub before it can be lowered. This mirrors exactly how
# son-corpus-wide.t's split_class_source builds `sub corpus_case { <body> }`
# for the driver portion of a corpus case; __main__ is the conventional name
# for the wrapped top-level program.
#
# The body is placed verbatim between the braces (its own newlines
# preserved): this is a FAITHFUL wrap that drops no statement. With
# effect-by-default (I1) and the Print node (I2), a sequence of top-level void
# statements inside __main__ all thread on the control chain in program order.
# ---------------------------------------------------------------------------
sub wrap_main ($body) {
    return "sub __main__ {\n$body\n}\n";
}

1;
