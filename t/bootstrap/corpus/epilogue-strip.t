# ABOUTME: Tests the robust known-epilogue strip that separates lli's TYPE:value
# ABOUTME: epilogue line from t/op TAP output without eating a real TAP line.
use 5.42.0;
use utf8;
use Test::More;

use lib 't/lib';
use Chalk::CodeGen::Harness::EpilogueStrip qw(strip_epilogue);

# ---------------------------------------------------------------------------
# The false-strip trap: a REAL TAP line legitimately ends in a TYPE: prefix.
# The naive "strip final line matching ^(Int|Num|Bool|Str|Undef):" would ALSO
# match `ok 1 - Str:foo` in t/op descriptions and eat a real conformance line,
# turning a miscompile into a false PASS. The robust scheme strips ONLY the
# known epilogue string as the final line, so a TAP line that merely CONTAINS
# a TYPE: substring is preserved.
# ---------------------------------------------------------------------------
{
    my $stdout   = "ok 1 - Str:foo\nInt:1\n";
    my $expected = "Int:1";
    my ($body, $stripped) = strip_epilogue($stdout, $expected);

    is $body, "ok 1 - Str:foo\n",
        "false-strip guard: real TAP line 'ok 1 - Str:foo' is preserved";
    is $stripped, "Int:1",
        "false-strip guard: only the known epilogue Int:1 was stripped";
}

# Normal case: TAP line then the epilogue.
{
    my ($body, $stripped) = strip_epilogue("ok 1\nInt:42\n", "Int:42");
    is $body, "ok 1\n", "normal case: keeps 'ok 1'";
    is $stripped, "Int:42", "normal case: strips 'Int:42'";
}

# Epilogue is the only output.
{
    my ($body, $stripped) = strip_epilogue("Int:7\n", "Int:7");
    is $body, "", "epilogue-only: body is empty";
    is $stripped, "Int:7", "epilogue-only: whole output was the epilogue";
}

# Final line is NOT the known epilogue: do NOT strip, and flag it.
{
    my ($body, $stripped) = strip_epilogue("ok 1 - Str:foo\n", "Int:1");
    is $body, "ok 1 - Str:foo\n",
        "non-match: body is returned unchanged when final line != known epilogue";
    is $stripped, undef,
        "non-match: nothing stripped is signalled with undef";
}

# Multi-line TAP stream, epilogue at the very end only.
{
    my $stdout = "1..3\nok 1 - Str:foo roundtrip\nok 2 - Int:42 add\nok 3\nBool:1\n";
    my ($body, $stripped) = strip_epilogue($stdout, "Bool:1");
    is $body, "1..3\nok 1 - Str:foo roundtrip\nok 2 - Int:42 add\nok 3\n",
        "multi-line: every real TAP line (even ones containing TYPE:) preserved";
    is $stripped, "Bool:1", "multi-line: only the trailing Bool:1 epilogue stripped";
}

# Acknowledged edge: a real final TAP line that coincidentally EQUALS the known
# epilogue string. Final-line-only + known-string exact match keeps the scheme
# robust for realistic input (a raw `Int:1\n` with no `ok`/`not ok`/plan prefix
# is not a valid Test::More line), but this documents that if a case's known
# epilogue is `Int:1` and a TAP line is literally `Int:1`, it is treated as the
# epilogue. Bytes are identical, so nothing downstream can tell them apart.
{
    my ($body, $stripped) = strip_epilogue("Int:1\n", "Int:1");
    is $body, "", "edge: bytewise-identical final line is treated as the epilogue";
    is $stripped, "Int:1", "edge: the identical line is what gets stripped";
}

done_testing;
