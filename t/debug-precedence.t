#!/usr/bin/env perl
# ABOUTME: Diagnostic test to trace precedence parsing for "1 + 2 * 3"
# ABOUTME: Helps identify which semiring is rejecting the parse
use 5.42.0;
use lib 'lib';
use Test::More;
use FindBin qw($RealBin);

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::ChalkSyntax;

# Load grammar
open my $fh, '<:utf8', "$RealBin/../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Test 1: Parse with Boolean only (should succeed)
diag("=== Test 1: Boolean semiring only ===");
my $bool_sr = Chalk::Semiring::Boolean->new();
my $parser1 = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $bool_sr
);
my $result1 = $parser1->parse_string('1 + 2 * 3');
ok($result1, 'Boolean semiring accepts parse') or diag("Boolean rejected");

# Test 2: Parse with Precedence only (this should reveal the issue)
diag("\n=== Test 2: Precedence semiring only ===");
my @perl_precedence_table = (
    { assoc => 'left',    ops => ['->'] },
    { assoc => 'nonassoc', ops => ['++', '--'] },
    { assoc => 'right',   ops => ['**'] },
    { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
    { assoc => 'left',    ops => ['=~', '!~'] },
    { assoc => 'left',    ops => ['*', '/', '%', 'x'] },      # Index 5
    { assoc => 'left',    ops => ['+', '-', '.'] },           # Index 6
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

my $prec_sr = Chalk::Semiring::Precedence->new(
    precedence_table => \@perl_precedence_table
);

my $parser2 = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $prec_sr
);

my $result2 = $parser2->parse_string('1 + 2 * 3');
ok($result2, 'Precedence semiring accepts parse') or diag("Precedence rejected - THIS IS THE BUG");

if ($result2 && $result2->can('to_string')) {
    diag("Result: " . $result2->to_string());
}

# Test 3: Parse with ChalkSyntax composite (full validation)
diag("\n=== Test 3: ChalkSyntax composite ===");
my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
my $parser3 = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $chalksyntax
);

my $result3 = $parser3->parse_string('1 + 2 * 3');
ok($result3, 'ChalkSyntax accepts parse') or diag("ChalkSyntax rejected");

# Test 4: Simpler expression that works
diag("\n=== Test 4: Simpler expression '1 + 2' ===");
my $result4 = $parser2->parse_string('1 + 2');
ok($result4, 'Simple addition works') or diag("Even simple addition failed!");

done_testing();
