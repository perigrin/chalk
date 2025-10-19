#!/usr/bin/env perl
# ABOUTME: Basic BNF parsing tests - simple rules and patterns
# ABOUTME: Tests fundamental parse_bnf_string functionality
use 5.42.0;
use Test::More;
use lib 'lib';
use Chalk::BNF;

# Test 1: Empty input
{
    my $rules = Chalk::BNF::parse_bnf_string('');
    is_deeply($rules, [], 'Empty input produces empty rule list');
}

# Test 2: Simple rule with terminals
{
    my $bnf = q{SimpleRule -> 'foo' 'bar'};
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed');
    is($rules->[0][0], 'SimpleRule', 'Correct LHS');
    is(scalar @{$rules->[0][1]}, 2, 'Two RHS elements');
    is($rules->[0][1][0], 'foo', 'First terminal correct');
    is($rules->[0][1][1], 'bar', 'Second terminal correct');
}

# Test 3: Rule with nonterminals
{
    my $bnf = q{Expr -> Term '+' Expr};
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed');
    is($rules->[0][0], 'Expr', 'Correct LHS');
    is($rules->[0][1][0], 'Term', 'First nonterminal');
    is($rules->[0][1][1], '+', 'Terminal operator');
    is($rules->[0][1][2], 'Expr', 'Second nonterminal');
}

# Test 4: Multiple rules
{
    my $bnf = <<'EOF';
Expr -> Term
Term -> Number
Number -> /\d+/
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 3, 'Three rules parsed');
    is($rules->[0][0], 'Expr', 'First rule LHS');
    is($rules->[1][0], 'Term', 'Second rule LHS');
    is($rules->[2][0], 'Number', 'Third rule LHS');
}

# Test 5: Epsilon (empty) rule
{
    my $bnf = q{Empty ->};
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed');
    is($rules->[0][0], 'Empty', 'Correct LHS');
    is_deeply($rules->[0][1], [], 'Empty RHS for epsilon rule');
}

# Test 6: Rule with whitespace variations
{
    my $bnf = q{  Spaced  ->  'a'   'b'  };
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed with whitespace');
    is($rules->[0][0], 'Spaced', 'LHS trimmed correctly');
    is($rules->[0][1][0], 'a', 'First token correct');
    is($rules->[0][1][1], 'b', 'Second token correct');
}

# Test 7: Comments in grammar
{
    my $bnf = <<'EOF';
# This is a comment
Rule -> 'token'  # inline comment
# Another comment
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'Comments ignored, one rule parsed');
    is($rules->[0][0], 'Rule', 'Rule parsed correctly');
}

# Test 8: Blank lines
{
    my $bnf = <<'EOF';

Rule1 -> 'a'

Rule2 -> 'b'

EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 2, 'Blank lines ignored');
}

done_testing();
