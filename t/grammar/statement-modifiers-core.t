#!/usr/bin/env perl
# ABOUTME: Core test for issue #39 - support for while statement modifiers with unlink
# ABOUTME: Focused test on the specific failure from rs.t at position 212
use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::Perl;
use Chalk::Semiring::Boolean;

# Create parser
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test the specific construct from rs.t that was failing
subtest 'issue #39 - rs.t line 11' => sub {
    my @cases = (
        "1 while unlink 'foo'",     # The exact problematic line
        "1 while unlink('foo')",    # With parentheses
        "1 while unlink",           # Without argument
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

# Test the full context from rs.t
subtest 'issue #39 - rs.t context' => sub {
    my $rs_snippet = <<'EOF';
# Create our test datafile
1 while unlink 'foo';                # in case junk left around
rmdir 'foo';
EOF
    ok($parser->parse_string($rs_snippet), "Should parse snippet from rs.t");
};

# Test similar statement modifier patterns
subtest 'statement modifiers with built-in functions' => sub {
    my @cases = (
        "1 if unlink 'foo'",
        "1 unless unlink 'foo'",
        "1 while rmdir 'foo'",
        "1 until eof",
        "\$x while chdir '/tmp'",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

done_testing();