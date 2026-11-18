# ABOUTME: Tests for Chalk::Bootstrap::Terminal regex matching at \G position.
# ABOUTME: Validates scanless parsing with anchored terminal matching.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Bootstrap::Terminal;

# Test 1: Simple literal pattern matching
{
    my $input = "hello world";
    my $pattern = qr/hello/;

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $pattern);
    is($end, 5, "matches 'hello' at position 0");

    my $no_match = Chalk::Bootstrap::Terminal::match($input, 1, $pattern);
    is($no_match, undef, "does not match 'hello' at position 1");
}

# Test 2: Whitespace pattern (common in BNF)
{
    my $input = "  \t\n  abc";
    my $ws_pattern = qr/\s+/;

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $ws_pattern);
    is($end, 6, "matches whitespace at position 0");

    my $no_match = Chalk::Bootstrap::Terminal::match($input, 6, $ws_pattern);
    is($no_match, undef, "does not match whitespace at position 6 (letter)");
}

# Test 3: Comment pattern (from BNF meta-grammar)
{
    my $input = "# this is a comment\nRule";
    my $comment_pattern = qr/#[^\n]*/;

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $comment_pattern);
    is($end, 19, "matches comment line");

    my $no_match = Chalk::Bootstrap::Terminal::match($input, 20, $comment_pattern);
    is($no_match, undef, "does not match at newline");
}

# Test 4: Identifier pattern (from BNF meta-grammar)
{
    my $input = "Rule_Name123 ::=";
    my $id_pattern = qr/[A-Za-z_][A-Za-z_0-9]*/;

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $id_pattern);
    is($end, 12, "matches identifier");

    # Match starts at \G position, not anywhere
    my $no_match = Chalk::Bootstrap::Terminal::match($input, 13, $id_pattern);
    is($no_match, undef, "does not match at space");
}

# Test 5: Inline regex pattern (literal forward slashes)
{
    my $input = "/[a-z]+/ x";
    my $regex_pattern = qr{/(?:[^/\\]|\\.)*/};

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $regex_pattern);
    is($end, 8, "matches inline regex with escaped content");
}

# Test 6: Empty string and EOF
{
    my $input = "";
    my $pattern = qr/x/;

    my $no_match = Chalk::Bootstrap::Terminal::match($input, 0, $pattern);
    is($no_match, undef, "no match in empty string");

    # Position at EOF
    my $input2 = "x";
    my $no_match2 = Chalk::Bootstrap::Terminal::match($input2, 1, $pattern);
    is($no_match2, undef, "no match at EOF position");
}

# Test 7: Zero-width match (e.g., lookahead)
{
    my $input = "abc";
    my $pattern = qr/(?=a)/;  # Zero-width positive lookahead

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $pattern);
    is($end, 0, "zero-width match returns same position");
}

# Test 8: Whitespace/comment combo pattern (from BNF)
{
    my $input = "  # comment\n  # another\n  Rule";
    my $ws_comment_pattern = qr/(?:\s|#[^\n]*)*/;

    my $end = Chalk::Bootstrap::Terminal::match($input, 0, $ws_comment_pattern);
    is($end, 26, "matches mixed whitespace and comments");
}

# Test 9: match_at matches in place, through a reference to the input
{
    my $input = "hello world";
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 0, qr/hello/), 5,
        "match_at returns the end position");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 6, qr/hello/), undef,
        "match_at returns undef when the pattern does not match there");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 6, qr/\w+/), 11,
        "match_at matches at a later position");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 11, qr/\w+/), undef,
        "match_at does not match at the end of the input");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 0, 'x|h'), 1,
        "match_at anchors every alternative of a plain pattern string");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 1, 'h|x'), undef,
        "match_at does not search past the position");
    is($input, "hello world", "match_at leaves the input as it was");
}

# Test 10: a zero-width match succeeds every time it is asked for
{
    my $input = "abc";
    my $ws = qr/(?:\s|#[^\n]*)*/;
    for my $attempt (1 .. 3) {
        is(Chalk::Bootstrap::Terminal::match_at(\$input, 1, $ws), 1,
            "zero-width match at the same position, attempt $attempt");
    }
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 1, qr/b/), 2,
        "a different pattern at that position still matches");
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 1, qr/(?=b)/), 1,
        "zero-width lookahead after a successful match there");
}

# Test 11: positions are characters, also past a multi-byte character
{
    my $input = "caf\x{e9} \x{263a} na\x{ef}ve";
    is(Chalk::Bootstrap::Terminal::match_at(\$input, 7, qr/\w+/), 12,
        "match_at counts characters in a wide-character string");
    is(Chalk::Bootstrap::Terminal::match($input, 7, qr/\w+/), 12,
        "match agrees with match_at");
}

# Test 12: the cost of a match does not depend on where in the input it is.
# Earley matches every terminal at every position: a cost linear in the
# position makes a parse quadratic in the input length.
{
    use Time::HiRes qw(time);
    my $input = "my \$x = 1; # \x{263a}\n" x 100_000;   # 1.5M characters, UTF-8 inside
    my $middle = 15 * 50_000;
    my $pattern = qr/my/;

    my $time_matches = sub ($position) {
        my $start = time;
        for my $attempt (1 .. 2_000) {
            Chalk::Bootstrap::Terminal::match_at(\$input, $position, $pattern);
        }
        return time - $start;
    };

    is(Chalk::Bootstrap::Terminal::match_at(\$input, $middle, $pattern), $middle + 2,
        "match_at matches in the middle of a long input");
    my $at_start  = $time_matches->(0);
    my $at_middle = $time_matches->($middle);
    cmp_ok($at_middle, '<', 20 * $at_start + 0.05,
        "2000 matches in the middle of 1.5M characters cost about what they cost at the start")
        or diag sprintf("at start: %.4fs, in the middle: %.4fs", $at_start, $at_middle);
}

done_testing();
