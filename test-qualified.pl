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

my $composite = Chalk::Semiring::Composite->new(
    semirings => [
        Chalk::Semiring::Boolean->new(),
        Chalk::Semiring::Precedence->new(precedence_table => \@perl_precedence_table)
    ]
);

open my $cfh, '<:utf8', "$RealBin/lib/Chalk/Semiring/Boolean.pm" or die $!;
my @lines = <$cfh>;
close $cfh;

my $first_class = join('', @lines[0..37]);

my @tests = (
    ['Simple', 'field $x = Foo->new(value => 1);'],
    ['Two parts', 'field $x = Foo::Bar->new(value => 1);'],
    ['Three parts', 'field $x = Foo::Bar::Baz->new(value => 1);'],
    ['Four parts', 'field $x = A::B::C::D->new(value => 1);'],
    ['Long name', 'field $x = Chalk::Semiring::BooleanElement->new(value => 1);'],
);

for my $test (@tests) {
    my ($name, $field_line) = @$test;
    my $code = $first_class . "\nclass Bar {\n    $field_line\n}\n";
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $composite);
    my $result = $parser->parse_string($code);
    print "$name: " . ($result ? "SUCCESS" : "FAIL") . "\n";
}
