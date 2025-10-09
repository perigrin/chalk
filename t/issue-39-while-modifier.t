#!/usr/bin/env perl
# ABOUTME: Test for issue #39 - support for while/until statement modifiers
# ABOUTME: Tests parsing of statements with while/until modifiers (e.g., "1 while unlink")
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

# Test basic while statement modifiers
subtest 'while statement modifiers' => sub {
    my @cases = (
        "1 while unlink 'foo'",
        "print while \$x",
        "print 'hi' while \$x < 10",
        "\$x++ while \$y",
        "next while \$condition",
        "last while 1",
        "redo while \$retry",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

# Test until statement modifiers
subtest 'until statement modifiers' => sub {
    my @cases = (
        "1 until eof",
        "print until \$done",
        "print 'waiting' until \$ready",
        "\$x++ until \$x > 10",
        "next until \$found",
        "last until 0",
        "redo until \$success",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

# Test for statement modifiers
subtest 'for/foreach statement modifiers' => sub {
    my @cases = (
        "print for \@array",
        "print \$_ for 1..10",
        "\$sum += \$_ for \@numbers",
        "print foreach \@list",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

# Test when statement modifiers (for given/when constructs)
subtest 'when statement modifiers' => sub {
    my @cases = (
        "print when 1",
        "\$x++ when \$y",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }
};

# Specific test from issue #39
subtest 'issue #39 specific case' => sub {
    my $rs_snippet = <<'EOF';
# Create our test datafile
1 while unlink 'foo';
rmdir 'foo';
EOF
    ok($parser->parse_string($rs_snippet), "Should parse snippet from rs.t");
};

done_testing();