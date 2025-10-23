#!/usr/bin/env perl
# ABOUTME: Test control flow statements in chalk.bnf
# ABOUTME: Covers if/elsif/else, while, for, return, last, next
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');
my $semiring = Chalk::Semiring::Boolean->new();

sub parses_ok {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok($result, $name) or diag("Failed to parse: $code");
}

# If statements
parses_ok(q{
    if ($x > 0) {
        $x;
    }
}, 'simple if statement');

parses_ok(q{
    if ($x > 0) {
        $x;
    } else {
        -$x;
    }
}, 'if-else statement');

parses_ok(q{
    if ($x > 0) {
        $x;
    } elsif ($x < 0) {
        -$x;
    } else {
        0;
    }
}, 'if-elsif-else statement');

parses_ok(q{
    if ($x > 0) {
        $x;
    } elsif ($x < -10) {
        -$x;
    } elsif ($x < 0) {
        $x * 2;
    } else {
        0;
    }
}, 'if with multiple elsif');

# Unless statements
parses_ok(q{
    unless ($x == 0) {
        1 / $x;
    }
}, 'simple unless statement');

# Statement modifiers
parses_ok(q{
    $x = 1 if $condition;
}, 'if statement modifier');

parses_ok(q{
    $x = 0 unless $condition;
}, 'unless statement modifier');

# While loops
parses_ok(q{
    while ($x < 10) {
        $x++;
    }
}, 'simple while loop');

# For loops - list iteration
parses_ok(q{
    for my $item (@list) {
        $item;
    }
}, 'for loop with list iteration');

# Return statements
parses_ok(q{
    return;
}, 'return without value');

parses_ok(q{
    return $x;
}, 'return with value');

parses_ok(q{
    return ($x, $y);
}, 'return with multiple values');

# Loop control
parses_ok(q{
    while ($x < 10) {
        last;
    }
}, 'last in loop');

parses_ok(q{
    for my $item (@list) {
        next;
    }
}, 'next in loop');

# Complex control flow
parses_ok(q{
    for my $item (@list) {
        if ($item > 10) {
            last;
        }
        if ($item < 0) {
            next;
        }
        $sum = $sum + $item;
    }
}, 'nested control flow with loop control');

parses_ok(q{
    if ($condition1) {
        if ($condition2) {
            return $value;
        }
    }
}, 'nested if statements');

parses_ok(q{
    while ($outer < 10) {
        while ($inner < 10) {
            $inner++;
        }
        $outer++;
    }
}, 'nested while loops');

# Control flow in methods
parses_ok(q{
    class Foo {
        method calculate($x) {
            if ($x < 0) {
                return 0;
            }

            my $sum = 0;
            for my $i (1..$x) {
                $sum = $sum + $i;
            }

            return $sum;
        }
    }
}, 'control flow in method');
