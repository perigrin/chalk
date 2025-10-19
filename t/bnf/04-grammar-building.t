#!/usr/bin/env perl
# ABOUTME: Tests for build_chalk_grammar function
# ABOUTME: Validates Grammar object construction and start symbol handling
use 5.42.0;
use Test::More;
use lib 'lib';
use Chalk::BNF;
use Chalk::Grammar;

# Test 1: Build grammar without start symbol
{
    my $bnf = <<'EOF';
Expr -> Term
Term -> Number
Number -> /\d+/
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    isa_ok($grammar, 'Chalk::Grammar', 'Returns Grammar object');
    is($grammar->start_symbol, 'Expr', 'First rule becomes start symbol');
}

# Test 2: Build grammar with explicit start symbol
{
    my $bnf = <<'EOF';
Expr -> Term
Term -> Number
Number -> /\d+/
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Number');

    isa_ok($grammar, 'Chalk::Grammar', 'Returns Grammar object');
    is($grammar->start_symbol, 'Number', 'Explicit start symbol used');
}

# Test 3: Start symbol reordering
{
    my $bnf = <<'EOF';
Rule1 -> 'a'
Rule2 -> 'b'
Rule3 -> 'c'
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Rule2');

    is($grammar->start_symbol, 'Rule2', 'Start symbol is Rule2');
    # The start symbol rule should be first in the grammar
}

# Test 4: Grammar with patterns
{
    my $bnf = <<'EOF';
%DIGIT% = /\d+/
Number -> %DIGIT%
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    isa_ok($grammar, 'Chalk::Grammar', 'Grammar with patterns builds');
    ok($grammar->rules, 'Grammar has rules');
}

# Test 5: Complex grammar
{
    my $bnf = <<'EOF';
%WS% = /\s+/
Program -> StatementList
StatementList -> Statement
StatementList -> Statement StatementList
Statement -> 'if' Expr Block
Expr -> /\w+/
Block -> '{' StatementList '}'
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Program');

    isa_ok($grammar, 'Chalk::Grammar', 'Complex grammar builds');
    is($grammar->start_symbol, 'Program', 'Correct start symbol');
}

# Test 6: Grammar with epsilon rules
{
    my $bnf = <<'EOF';
List -> Item List
List ->
Item -> /\w+/
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    isa_ok($grammar, 'Chalk::Grammar', 'Grammar with epsilon rules builds');
}

# Test 7: Start symbol that doesn't exist
{
    my $bnf = <<'EOF';
Rule -> 'foo'
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'NonExistent');

    isa_ok($grammar, 'Chalk::Grammar', 'Grammar builds even with non-existent start symbol');
    # The grammar will still build, but NonExistent won't be in the rules
}

# Test 8: Empty grammar
{
    my $bnf = '';

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    isa_ok($grammar, 'Chalk::Grammar', 'Empty grammar builds');
}

# Test 9: Grammar rules accessible
{
    my $bnf = <<'EOF';
Expr -> Term '+' Expr
Expr -> Term
Term -> Number
Number -> /\d+/
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    my $rules = $grammar->rules;
    ok(exists $rules->{Expr}, 'Expr rules exist');
    ok(exists $rules->{Term}, 'Term rules exist');
    ok(exists $rules->{Number}, 'Number rules exist');

    is(scalar @{$rules->{Expr}}, 2, 'Expr has 2 alternative rules');
}

# Test 10: Nullable computation
{
    my $bnf = <<'EOF';
Nullable ->
NonNullable -> 'foo'
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf);

    ok($grammar->is_nullable('Nullable'), 'Epsilon rule is nullable');
    ok(!$grammar->is_nullable('NonNullable'), 'Non-epsilon rule not nullable');
}

# Test 11: Real-world-like grammar snippet
{
    my $bnf = <<'EOF';
%IDENT% = /[a-zA-Z_]\w*/
%NUM% = /\d+/
Program -> Statement
Statement -> Assignment
Statement -> IfStatement
Assignment -> %IDENT% '=' Expr
Expr -> %IDENT%
Expr -> %NUM%
IfStatement -> 'if' '(' Expr ')' Block
Block -> '{' '}'
EOF

    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Program');

    isa_ok($grammar, 'Chalk::Grammar', 'Real-world grammar builds');
    is($grammar->start_symbol, 'Program', 'Program is start symbol');

    my $rules = $grammar->rules;
    ok(exists $rules->{Statement}, 'Statement rules exist');
    is(scalar @{$rules->{Statement}}, 2, 'Statement has 2 alternatives');
}

done_testing();
