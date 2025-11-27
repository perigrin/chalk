#!/usr/bin/env perl
# ABOUTME: Find what in second class triggers Precedence bug
# ABOUTME: Tests progressively adding content

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

# Read Boolean.pm lines 1-38 (first class complete)
open my $cfh, '<:utf8', "$RealBin/lib/Chalk/Semiring/Boolean.pm" or die $!;
my @lines = <$cfh>;
close $cfh;
my $base = join('', @lines[0..37]);

# Test progressively adding second class content
my @tests = (
    ['Empty', 'class Bar { }'],
    ['With comment', "class Bar {\n    # comment\n}"],
    ['With field', "class Bar {\n    field \$x :param;\n}"],
    ['With field = expr', "class Bar {\n    field \$x :reader = 1;\n}"],
    ['With new() call', "class Bar {\n    field \$x = Foo->new();\n}"],
    ['Exact line 41', 'class Bar { field $mul_id :reader = Chalk::Semiring::BooleanElement->new(value => 1); }'],
);

for my $test (@tests) {
    my ($name, $second_class) = @$test;
    my $code = $base . "\n" . $second_class . "\n";
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);
    my $result = $parser->parse_string($code);
    print "$name: " . ($result ? "SUCCESS" : "FAIL") . "\n";
}
