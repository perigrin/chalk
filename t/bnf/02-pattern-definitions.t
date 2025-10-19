#!/usr/bin/env perl
# ABOUTME: Tests for pattern definitions and pattern references
# ABOUTME: Validates %PATTERN% syntax and regex compilation
use 5.42.0;
use Test::More;
use lib 'lib';
use Chalk::BNF;

# Test 1: Simple pattern definition
{
    my $bnf = <<'EOF';
%DIGIT% = /\d+/
Number -> %DIGIT%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed');
    is($rules->[0][0], 'Number', 'Rule LHS correct');
    isa_ok($rules->[0][1][0], 'Regexp', 'Pattern reference is a regex');
}

# Test 2: Pattern with flags
{
    my $bnf = <<'EOF';
%WORD% = /[a-z]+/i
Word -> %WORD%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule with flagged pattern');
    isa_ok($rules->[0][1][0], 'Regexp', 'Pattern is a regex');

    # Test that the pattern actually works with case-insensitive flag
    my $pattern = $rules->[0][1][0];
    ok('ABC' =~ $pattern, 'Case-insensitive flag works');
}

# Test 3: Multiple pattern definitions
{
    my $bnf = <<'EOF';
%DIGIT% = /\d+/
%LETTER% = /[a-z]+/i
%WORD% = /\w+/
AlphaNum -> %LETTER% %DIGIT%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule with multiple patterns defined');
    is(scalar @{$rules->[0][1]}, 2, 'Two pattern references in rule');
    isa_ok($rules->[0][1][0], 'Regexp', 'First pattern is regex');
    isa_ok($rules->[0][1][1], 'Regexp', 'Second pattern is regex');
}

# Test 4: Pattern with complex regex
{
    my $bnf = <<'EOF';
%QUALIFIED% = /[a-zA-Z_][a-zA-Z0-9_]*(?:::+[a-zA-Z_][a-zA-Z0-9_]*)*/u
Identifier -> %QUALIFIED%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'Complex pattern parsed');
    isa_ok($rules->[0][1][0], 'Regexp', 'Complex regex compiled');
}

# Test 5: Pattern containing # character (not a comment)
{
    my $bnf = <<'EOF';
%SPECIAL% = /#.*$/um
Comment -> %SPECIAL%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'Pattern with # character parsed');
    isa_ok($rules->[0][1][0], 'Regexp', 'Pattern is regex');
}

# Test 6: Multiple patterns used in one rule
{
    my $bnf = <<'EOF';
%DIGIT% = /\d+/
%OP% = /[+\-*\/]/
Expr -> %DIGIT% %OP% %DIGIT%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'One rule parsed');
    is(scalar @{$rules->[0][1]}, 3, 'Three elements in RHS');
    isa_ok($rules->[0][1][0], 'Regexp', 'First is regex');
    isa_ok($rules->[0][1][1], 'Regexp', 'Second is regex');
    isa_ok($rules->[0][1][2], 'Regexp', 'Third is regex');
}

# Test 7: Pattern and terminals mixed
{
    my $bnf = <<'EOF';
%NUM% = /\d+/
Assignment -> Var '=' %NUM%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'Mixed pattern and terminals');
    is($rules->[0][1][0], 'Var', 'Nonterminal');
    is($rules->[0][1][1], '=', 'Terminal');
    isa_ok($rules->[0][1][2], 'Regexp', 'Pattern');
}

# Test 8: Pattern with various regex flags
{
    my $bnf = <<'EOF';
%MULTI% = /foo.*bar/ms
%UNICODE% = /\w+/u
Rule1 -> %MULTI%
Rule2 -> %UNICODE%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 2, 'Two rules with different flags');
    isa_ok($rules->[0][1][0], 'Regexp', 'Multiline pattern is regex');
    isa_ok($rules->[1][1][0], 'Regexp', 'Unicode pattern is regex');
}

# Test 9: Empty flags (no flags specified)
{
    my $bnf = <<'EOF';
%SIMPLE% = /abc/
Rule -> %SIMPLE%
EOF
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    is(scalar @$rules, 1, 'Pattern without flags');
    isa_ok($rules->[0][1][0], 'Regexp', 'Pattern compiled without flags');
}

done_testing();
