#!/usr/bin/env perl
# ABOUTME: Find what triggers Precedence semiring bug
# ABOUTME: Progressively adds content from Boolean.pm

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Composite;

open my $fh, '<:utf8', "$RealBin/grammar/chalk.bnf" or die $!;
my $bnf = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');

my @perl_precedence_table = (
    { assoc => 'left',    ops => ['->'] },
    { assoc => 'nonassoc', ops => ['++', '--'] },
    { assoc => 'right',   ops => ['**'] },
    { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
    { assoc => 'left',    ops => ['=~', '!~'] },
    { assoc => 'left',    ops => ['*', '/', '%', 'x'] },
    { assoc => 'left',    ops => ['+', '-', '.'] },
    { assoc => 'left',    ops => ['<<', '>>'] },
    { assoc => 'nonassoc', ops => ['named unary'] },
    { assoc => 'nonassoc', ops => ['isa'] },
    { assoc => 'chained', ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'] },
    { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne', '<=>', 'cmp', '~~'] },
    { assoc => 'left',    ops => ['&'] },
    { assoc => 'left',    ops => ['|', '^'] },
    { assoc => 'left',    ops => ['&&'] },
    { assoc => 'left',    ops => ['||', '^^', '//'] },
    { assoc => 'nonassoc', ops => ['..', '...'] },
    { assoc => 'right',   ops => ['?:'] },
    { assoc => 'right',   ops => ['=', '+=', '-=', '*=', '/=', '%=', '**=', '&=', '|=', '^=', '.=', '<<=', '>>=', '&&=', '||=', '//='] },
    { assoc => 'left',    ops => [',', '=>'] },
    { assoc => 'right',   ops => ['not'] },
    { assoc => 'left',    ops => ['and'] },
    { assoc => 'left',    ops => ['or', 'xor'] },
);

my $composite = Chalk::Semiring::Composite->new(
    semirings => [
        Chalk::Semiring::Boolean->new(),
        Chalk::Semiring::Precedence->new(precedence_table => \@perl_precedence_table)
    ]
);

# Read Boolean.pm
open my $cfh, '<:utf8', "$RealBin/lib/Chalk/Semiring/Boolean.pm" or die $!;
my @lines = <$cfh>;
close $cfh;

# Test exact slices from file
for my $end (10, 15, 20, 25, 30, 35, 38, 40) {
    my $code = join('', @lines[0..($end-1)]);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);
    my $result = $parser->parse_string($code);
    print "Lines 1-$end: " . ($result ? "SUCCESS" : "FAIL") . "\n";
}

# Test exactly lines 1-38 + lines 39-40
my $code = join('', @lines[0..39]);
my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);
my $result = $parser->parse_string($code);
print "Lines 1-40: " . ($result ? "SUCCESS" : "FAIL") . "\n";
print "Line 39: $lines[38]";
print "Line 40: $lines[39]";
