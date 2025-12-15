#!/usr/bin/env perl
# ABOUTME: Test for issue #39 - support for while/until statement modifiers
# ABOUTME: Tests parsing of statements with while/until modifiers (e.g., "1 while unlink")
use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


# Create parser
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test basic while statement modifiers
subtest 'while statement modifiers' => sub {
    my @cases = (
        "1 while unlink 'foo'",
        "print while \$x",
        "\$x++ while \$y",
        "next while \$condition",
        "last while 1",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }

    # TODO: redo keyword not yet in grammar
    TODO: {
        local $TODO = "redo keyword not yet in grammar";
        ok($parser->parse_string("redo while \$retry"), "Should parse: redo while \$retry");
    }

    # Print with string literal argument and statement modifier
    # Works via: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
    ok($parser->parse_string("print 'hi' while \$x < 10"),
       "Should parse: print 'hi' while \$x < 10");
};

# Test until statement modifiers
subtest 'until statement modifiers' => sub {
    my @cases = (
        "1 until eof",
        "print until \$done",
        "\$x++ until \$x > 10",
        "next until \$found",
        "last until 0",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }

    # TODO: redo keyword not yet in grammar
    TODO: {
        local $TODO = "redo keyword not yet in grammar";
        ok($parser->parse_string("redo until \$success"), "Should parse: redo until \$success");
    }

    # Print with string literal argument and statement modifier
    # Works via: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
    ok($parser->parse_string("print 'waiting' until \$ready"),
       "Should parse: print 'waiting' until \$ready");
};

# Test for statement modifiers
subtest 'for/foreach statement modifiers' => sub {
    my @cases = (
        "print for \@array",
        "print foreach \@list",
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test");
    }

    # TODO #171, #172: Range operators and compound assignment not fully supported yet
    TODO: {
        local $TODO = "range operator in for modifier not yet supported (#171)";
        ok($parser->parse_string("print \$_ for 1..10"),
           "Should parse: print \$_ for 1..10");
    }

    TODO: {
        local $TODO = "compound assignment with for modifier not yet supported (#172)";
        ok($parser->parse_string("\$sum += \$_ for \@numbers"),
           "Should parse: \$sum += \$_ for \@numbers");
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