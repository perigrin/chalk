# ABOUTME: Robust strip of the compiler's TYPE:value epilogue line from lli stdout
# ABOUTME: by known-string exact match, so a real TAP line ending in TYPE: is never eaten.
package Chalk::CodeGen::Harness::EpilogueStrip;

use 5.42.0;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(strip_epilogue);

# ---------------------------------------------------------------------------
# strip_epilogue($lli_stdout, $expected_epilogue) -> ($body, $stripped)
#
# The Mode-1 harvester runs a compiled case under lli and gets stdout that is
# the case's real (TAP) output followed by ONE compiler epilogue line of the
# form "TYPE:value\n", TYPE in {Int,Num,Bool,Str,Undef} (see
# Chalk::Target::LLVM::lower_with_elaboration). To compare against perl's TAP
# output the epilogue must be removed FIRST.
#
# The naive scheme — strip the final line if it matches /^(Int|Num|...):/ — is
# unsafe for t/op: a Test::More description can legitimately be
# "ok 5 - Str:foo roundtrip", and a value line "Int:1" appears inside such a
# description's text. A pattern strip would eat a real TAP line, converting a
# conformance FAILURE into a false PASS.
#
# Robust scheme (b): the runner KNOWS the case's expected epilogue string (it
# lowered the return node, or the case declares its return value), so it strips
# ONLY the final line and ONLY when that line EQUALS the known epilogue string
# exactly. A TAP line that merely contains a TYPE: substring — or even one that
# starts with a TYPE: prefix but differs from the known value — is preserved.
#
# Returns a two-element list:
#   $body     — $lli_stdout with the epilogue line removed (or unchanged if the
#               final line was not the known epilogue). Line terminators of the
#               remaining body are preserved exactly.
#   $stripped — the epilogue string that was removed, or undef when the final
#               line did not equal $expected_epilogue (the caller can flag a
#               missing/unexpected epilogue as a hard error rather than a pass).
# ---------------------------------------------------------------------------
sub strip_epilogue {
    my ($stdout, $expected_epilogue) = @_;

    # The epilogue is exactly one line: the known value plus its newline. Match
    # it as a literal suffix so we never re-interpret it as a pattern.
    my $suffix = $expected_epilogue . "\n";

    if (length($stdout) >= length($suffix)
        && substr($stdout, -length($suffix)) eq $suffix)
    {
        my $body = substr($stdout, 0, length($stdout) - length($suffix));
        return ($body, $expected_epilogue);
    }

    # Final line is not the known epilogue: strip nothing, signal with undef so
    # the runner can treat a missing epilogue as a failure, not a silent pass.
    return ($stdout, undef);
}

1;
