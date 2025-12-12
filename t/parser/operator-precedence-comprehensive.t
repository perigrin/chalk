#!/usr/bin/env perl
# ABOUTME: Comprehensive tests for operator precedence validation in parser
# ABOUTME: Tests arithmetic, comma, assignment, and parenthesized expressions
use 5.42.0;
use experimental qw(class builtin);
use utf8;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Chalk::Grammar::BNF;
use Chalk::Grammar;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Composite;
use Chalk::Parser;

# Load the chalk grammar
my $grammar_file = "$RealBin/../../grammar/chalk.bnf";
open my $fh, '<:utf8', $grammar_file or die "Cannot open $grammar_file: $!";
my $bnf = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');

# Create precedence table matching Perl's operator precedence
# Lower index = higher precedence (binds tighter)
my @precedence_table = (
    { assoc => 'left',    ops => ['->'] },                    # 0
    { assoc => 'nonassoc', ops => ['++', '--'] },             # 1
    { assoc => 'right',   ops => ['**'] },                    # 2
    { assoc => 'right',   ops => ['!', '~', '\\'] },          # 3
    { assoc => 'left',    ops => ['=~', '!~'] },              # 4
    { assoc => 'left',    ops => ['*', '/', '%', 'x'] },      # 5
    { assoc => 'left',    ops => ['+', '-', '.'] },           # 6
    { assoc => 'left',    ops => ['<<', '>>'] },              # 7
    { assoc => 'nonassoc', ops => ['isa'] },                  # 8
    { assoc => 'chained', ops => ['<', '>', '<=', '>='] },    # 9
    { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne'] }, # 10
    { assoc => 'left',    ops => ['&'] },                     # 11
    { assoc => 'left',    ops => ['|', '^'] },                # 12
    { assoc => 'left',    ops => ['&&'] },                    # 13
    { assoc => 'left',    ops => ['||', '//'] },              # 14
    { assoc => 'nonassoc', ops => ['..', '...'] },            # 15
    { assoc => 'right',   ops => ['?:'] },                    # 16
    { assoc => 'right',   ops => ['=', '+=', '-=', '*='] },   # 17
    { assoc => 'left',    ops => [',', '=>'] },               # 18
    { assoc => 'right',   ops => ['not'] },                   # 19
    { assoc => 'left',    ops => ['and'] },                   # 20
    { assoc => 'left',    ops => ['or', 'xor'] },             # 21
);

sub make_parser {
    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);
    my $composite = Chalk::Semiring::Composite->new(semirings => [$bool_sr, $prec_sr]);
    return Chalk::Parser->new(grammar => $grammar, semiring => $composite);
}

# Helper to test parsing
sub parses_ok {
    my ($code, $desc) = @_;
    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok(defined $result, $desc // "parses: $code");
}

sub parses_not_ok {
    my ($code, $desc) = @_;
    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok(!defined $result, $desc // "fails to parse: $code");
}

# =============================================================================
# TEST GROUP 1: Basic Arithmetic Precedence
# =============================================================================
subtest 'Basic arithmetic precedence (* binds tighter than +)' => sub {
    # These should all parse - lower precedence parent contains higher precedence child
    parses_ok('my $x = 1 + 2;', 'simple addition');
    parses_ok('my $x = 1 * 2;', 'simple multiplication');
    parses_ok('my $x = 1 + 2 * 3;', 'addition with multiplication (+ contains *)');
    parses_ok('my $x = 1 * 2 + 3;', 'multiplication then addition');
    parses_ok('my $x = 1 + 2 + 3;', 'chained addition');
    parses_ok('my $x = 1 * 2 * 3;', 'chained multiplication');
    parses_ok('my $x = 1 + 2 * 3 + 4;', 'mixed operators');
};

# =============================================================================
# TEST GROUP 2: Comma vs Arithmetic (the bug we fixed)
# =============================================================================
subtest 'Comma has lower precedence than arithmetic' => sub {
    # Comma (level 18) should be able to contain + (level 6)
    # This was failing before the fix
    parses_ok('my $x = 1 + 2, 3;', 'comma after addition');
    parses_ok('my @a = (1 + 2, 3 + 4);', 'comma separating additions in list');
    parses_ok('my @a = (1, 2 + 3, 4);', 'addition in middle of list');
};

# =============================================================================
# TEST GROUP 3: Function calls with arithmetic arguments
# =============================================================================
subtest 'Function calls with arithmetic in arguments' => sub {
    # Function argument commas should not conflict with arithmetic inside args
    parses_ok('my $x = foo(1 + 2);', 'function call with addition');
    parses_ok('my $x = foo(1 + 2, 3);', 'function call with addition and comma');
    parses_ok('my $x = foo(1, 2 + 3);', 'function call with comma then addition');
    parses_ok('my $x = foo(1 + 2, 3 * 4);', 'function call with multiple arithmetic args');
    parses_ok('my $x = foo(1 + 2, 3 + 4, 5 + 6);', 'function call with three arithmetic args');
};

# =============================================================================
# TEST GROUP 4: Parentheses isolate precedence
# =============================================================================
subtest 'Parentheses isolate precedence context' => sub {
    parses_ok('my $x = (1 + 2) * 3;', 'parenthesized addition times 3');
    parses_ok('my $x = 1 * (2 + 3);', '1 times parenthesized addition');
    parses_ok('my $x = (1 + 2) * (3 + 4);', 'two parenthesized additions multiplied');
    parses_ok('my $x = ((1 + 2));', 'nested parentheses');
    parses_ok('my $x = (1 + (2 * 3));', 'nested with different operators');
};

# =============================================================================
# TEST GROUP 5: Assignment has low precedence
# =============================================================================
subtest 'Assignment has lower precedence than arithmetic' => sub {
    parses_ok('my $x = 1 + 2;', 'basic assignment with addition');
    parses_ok('my $x = 1 * 2 + 3;', 'assignment with mixed operators');
    parses_ok('$x = $y = 1 + 2;', 'chained assignment with addition');
    parses_ok('$x += 1 + 2;', 'compound assignment with addition');
};

# =============================================================================
# TEST GROUP 6: Comparison operators
# =============================================================================
subtest 'Comparison has lower precedence than arithmetic' => sub {
    parses_ok('my $x = 1 + 2 == 3;', 'addition compared to value');
    parses_ok('my $x = 1 < 2 + 3;', 'comparison with right-side addition');
    parses_ok('my $x = 1 + 2 < 3 + 4;', 'additions on both sides of comparison');
};

# =============================================================================
# TEST GROUP 7: Logical operators
# =============================================================================
subtest 'Logical operators have lower precedence than comparison' => sub {
    parses_ok('my $x = 1 && 2;', 'simple logical and');
    parses_ok('my $x = 1 || 2;', 'simple logical or');
    parses_ok('my $x = 1 == 2 && 3 == 4;', 'comparisons connected by &&');
    parses_ok('my $x = 1 < 2 || 3 > 4;', 'comparisons connected by ||');
};

# =============================================================================
# TEST GROUP 8: Real-world expressions from Chalk codebase
# =============================================================================
subtest 'Real-world expressions from Chalk codebase' => sub {
    # These are patterns that appear in actual Chalk code
    parses_ok('my $x = $pos + length($value);', 'addition with function call');
    parses_ok('my $y = $start < $end ? $start : $end;', 'ternary with comparisons');
    parses_ok('my @list = ($a, $b + $c, $d);', 'list with arithmetic');
    parses_ok('return $x + $y;', 'return with addition');
};

# =============================================================================
# TEST GROUP 9: Known limitations (TODO tests)
# These involve method calls and need more work
# =============================================================================
subtest 'Method calls with operators' => sub {
    # Method call arrow has highest precedence
    # These may fail due to how -> interacts with other operators
    todo 'Method call precedence needs more work' => sub {
        parses_ok('my $x = $obj->method && $y;', 'method call then logical and');
        parses_ok('my $x = $a && $b->method;', 'logical and then method call');
        parses_ok('my $x = $obj->method + 1;', 'method call plus number');
    };
};

done_testing();
