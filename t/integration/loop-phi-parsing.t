#!/usr/bin/env perl
# ABOUTME: Integration tests for loop with variable modifications
# ABOUTME: Validates that loops with modified variables parse correctly

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Parser;
use Chalk::Grammar;

# Load the chalk.bnf grammar
open my $grammar_fh, "<:utf8", "$RealBin/../../grammar/chalk.bnf" or die $!;
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;

my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");

subtest 'Parse loop with single modified variable' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 10) {
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Loop with modified variable parses successfully';
};

subtest 'Parse loop with multiple modified variables' => sub {
    my $code = q{
        my $sum = 0;
        my $i = 0;
        while ($i < 10) {
            $sum = $sum + $i;
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Loop with multiple modified variables parses successfully';
};

subtest 'Parse loop with conditional modification' => sub {
    my $code = q{
        my $count = 0;
        my $i = 0;
        while ($i < 10) {
            if ($i > 5) {
                $count = $count + 1;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Loop with conditional modification parses successfully';
};

subtest 'Parse nested loops with separate variables' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 5) {
            my $j = 0;
            while ($j < 3) {
                $j = $j + 1;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Nested loops parse successfully';
};

subtest 'Parse loop with break and variables' => sub {
    my $code = q{
        my $result = 0;
        my $i = 0;
        while ($i < 10) {
            if ($i == 5) {
                $result = $i;
                break;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Loop with break and variables parses successfully';
};

subtest 'Parse loop with continue and variables' => sub {
    my $code = q{
        my $sum = 0;
        my $i = 0;
        while ($i < 10) {
            if ($i == 5) {
                $i = $i + 1;
                continue;
            }
            $sum = $sum + $i;
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Loop with continue and variables parses successfully';
};

subtest 'Parse complex accumulator pattern' => sub {
    my $code = q{
        my $sum = 0;
        my $prod = 1;
        my $i = 1;
        while ($i < 5) {
            $sum = $sum + $i;
            $prod = $prod * $i;
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Complex accumulator pattern parses successfully';
};
