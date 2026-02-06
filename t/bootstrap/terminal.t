# ABOUTME: Tests for Chalk::Bootstrap::Terminal regex matching at \G position.
# ABOUTME: Validates scanless parsing with anchored terminal matching.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
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

done_testing();
