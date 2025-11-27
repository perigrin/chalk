#!/usr/bin/env perl
# ABOUTME: Test parsing with full precedence table
# ABOUTME: Verifies Boolean+Precedence composite works on Boolean.pm

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

# Full precedence table from ChalkSyntax
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
my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);

open my $cfh, '<:utf8', "$RealBin/lib/Chalk/Semiring/Boolean.pm" or die $!;
my $code = do { local $/; <$cfh> };
close $cfh;

print "Boolean+Precedence(full): ";
my $result = $parser->parse_string($code);
print $result ? "SUCCESS" : "FAIL", "\n";
