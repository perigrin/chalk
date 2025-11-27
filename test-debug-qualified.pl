#!/usr/bin/env perl
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

# Test with just Boolean (no Precedence) to see if it's a grammar issue
my $boolean_only = Chalk::Semiring::Boolean->new();
my $parser1 = Chalk::Parser->new(grammar => $grammar, semiring => $boolean_only);

my $code = 'class Bar { field $x = Foo::Bar->new(value => 1); }';
my $result1 = $parser1->parse_string($code);
print "Boolean only: " . ($result1 ? "SUCCESS" : "FAIL") . "\n";

# Now with composite
my $composite = Chalk::Semiring::Composite->new(
    semirings => [
        Chalk::Semiring::Boolean->new(),
        Chalk::Semiring::Precedence->new(precedence_table => \@perl_precedence_table)
    ]
);
my $parser2 = Chalk::Parser->new(grammar => $grammar, semiring => $composite);
my $result2 = $parser2->parse_string($code);
print "Boolean+Precedence: " . ($result2 ? "SUCCESS" : "FAIL") . "\n";
