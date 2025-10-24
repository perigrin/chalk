#!/usr/bin/env perl
# ABOUTME: Integration tests for parsing break/continue statements
# ABOUTME: Validates that Chalk grammar parses loop control flow correctly

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

my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

subtest 'Parse simple break statement' => sub {
    my $code = q{
        my $i = 10;
        while ($i > 0) {
            break;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Break statement parses successfully';
};

subtest 'Parse conditional break' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 10) {
            if ($i == 5) {
                break;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Conditional break parses successfully';
};

subtest 'Parse simple continue statement' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 10) {
            if ($i == 5) {
                $i = $i + 1;
                continue;
            }
            $i = $i + 2;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Continue statement parses successfully';
};

subtest 'Parse break and continue together' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 100) {
            if ($i == 50) {
                break;
            }
            if ($i == 25) {
                $i = $i + 1;
                continue;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Break and continue together parse successfully';
};

subtest 'Parse nested loops with break' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 5) {
            my $j = 0;
            while ($j < 3) {
                if ($j == 2) {
                    break;
                }
                $j = $j + 1;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Nested loops with break parse successfully';
};

subtest 'Parse multiple break exits' => sub {
    my $code = q{
        my $i = 0;
        while ($i < 100) {
            if ($i == 10) {
                break;
            }
            if ($i == 20) {
                break;
            }
            $i = $i + 1;
        }
    };

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);

    ok $result, 'Multiple break exits parse successfully';
};
