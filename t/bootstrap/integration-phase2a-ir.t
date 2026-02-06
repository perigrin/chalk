# ABOUTME: Integration test for Phase 2a - IR construction for BNF meta-grammar
# ABOUTME: Verifies that IR nodes can represent the BNF meta-grammar structure correctly
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Constant;
use Chalk::Bootstrap::IR::Node::MakeSymbol;
use Chalk::Bootstrap::IR::Node::MakeExpression;
use Chalk::Bootstrap::IR::Node::MakeRule;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: Build IR for a simple terminal rule
# Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
{
    # Create constant nodes
    my $rule_name = $factory->make('Constant', const_type => 'string', value => 'Identifier');
    my $terminal_type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $pattern = $factory->make('Constant', const_type => 'string', value => '[A-Za-z_][A-Za-z_0-9]*');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    # Create symbol node
    my $symbol = $factory->make('MakeSymbol',
        type => $terminal_type,
        value => $pattern,
        quantifier => $no_quant,
    );

    # Create expression node (list of symbols)
    my $expression = $factory->make('MakeExpression',
        elements => [$symbol],
    );

    # Create rule node
    my $rule = $factory->make('MakeRule',
        name => $rule_name,
        expressions => $expression,
    );

    isa_ok($rule, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created MakeRule node');
    is($rule->inputs()->[0]->value(), 'Identifier', 'rule name is Identifier');

    my $expr = $rule->inputs()->[1];
    isa_ok($expr, 'Chalk::Bootstrap::IR::Node::MakeExpression', 'rule has MakeExpression');

    my $sym = $expr->inputs()->[0][0];
    isa_ok($sym, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'expression has MakeSymbol');
    is($sym->inputs()->[0]->value(), 'terminal', 'symbol type is terminal');
    is($sym->inputs()->[1]->value(), '[A-Za-z_][A-Za-z_0-9]*', 'symbol value is pattern');
}

# Test 2: Build IR for a rule with alternatives
# Atom ::= Identifier | InlineRegex
{
    # Rule name
    my $rule_name = $factory->make('Constant', const_type => 'string', value => 'Atom');

    # First alternative: Identifier (reference)
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $ident_value = $factory->make('Constant', const_type => 'string', value => 'Identifier');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $ident_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $ident_value,
        quantifier => $no_quant,
    );

    my $expr1 = $factory->make('MakeExpression',
        elements => [$ident_sym],
    );

    # Second alternative: InlineRegex (reference)
    my $regex_value = $factory->make('Constant', const_type => 'string', value => 'InlineRegex');

    my $regex_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $regex_value,
        quantifier => $no_quant,
    );

    my $expr2 = $factory->make('MakeExpression',
        elements => [$regex_sym],
    );

    # NOTE: MakeRule expects expressions input to be a single MakeExpression or array
    # According to Actions.pm, action_Rule expects a single node from Alternatives
    # But the semantic should be that MakeRule wraps multiple alternatives
    # For now, test with single expression and document this

    # Create rule with first expression (simplified)
    my $rule = $factory->make('MakeRule',
        name => $rule_name,
        expressions => $expr1,
    );

    isa_ok($rule, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created Atom rule');
    is($rule->inputs()->[0]->value(), 'Atom', 'rule name is Atom');
}

# Test 3: Build IR for a rule with quantifier
# Grammar ::= Rule+
# (Simplified without whitespace terminal)
{
    my $rule_name = $factory->make('Constant', const_type => 'string', value => 'Grammar');
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $rule_value = $factory->make('Constant', const_type => 'string', value => 'Rule');
    my $plus_quant = $factory->make('Constant', const_type => 'string', value => '+');

    my $rule_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $rule_value,
        quantifier => $plus_quant,
    );

    my $expression = $factory->make('MakeExpression',
        elements => [$rule_sym],
    );

    my $grammar_rule = $factory->make('MakeRule',
        name => $rule_name,
        expressions => $expression,
    );

    isa_ok($grammar_rule, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created Grammar rule');

    my $sym = $grammar_rule->inputs()->[1]->inputs()->[0][0];
    is($sym->inputs()->[2]->value(), '+', 'symbol has + quantifier');
}

# Test 4: Build IR for a sequence (multiple symbols)
# Element ::= Atom Quantifier
{
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    # Atom symbol
    my $atom_value = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $atom_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $atom_value,
        quantifier => $no_quant,
    );

    # Quantifier symbol
    my $quant_value = $factory->make('Constant', const_type => 'string', value => 'Quantifier');
    my $quant_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $quant_value,
        quantifier => $no_quant,
    );

    # Create expression with two symbols (sequence)
    my $expression = $factory->make('MakeExpression',
        elements => [$atom_sym, $quant_sym],
    );

    isa_ok($expression, 'Chalk::Bootstrap::IR::Node::MakeExpression', 'created sequence expression');
    my $elements = $expression->inputs()->[0];
    is(scalar($elements->@*), 2, 'expression has 2 elements');
    is($elements->[0]->inputs()->[1]->value(), 'Atom', 'first element is Atom');
    is($elements->[1]->inputs()->[1]->value(), 'Quantifier', 'second element is Quantifier');
}

# Test 5: Verify hash consing deduplicates identical nodes
{
    # Create two identical Constant nodes
    my $const1 = $factory->make('Constant', const_type => 'string', value => 'Identifier');
    my $const2 = $factory->make('Constant', const_type => 'string', value => 'Identifier');

    # They should be the same object (same reference)
    is($const1, $const2, 'hash consing deduplicates identical Constant nodes');
    is($const1->id(), $const2->id(), 'deduplicated nodes have same ID');

    # Create two identical MakeSymbol nodes
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $sym1 = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $const1,
        quantifier => $no_quant,
    );

    my $sym2 = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $const1,
        quantifier => $no_quant,
    );

    is($sym1, $sym2, 'hash consing deduplicates identical MakeSymbol nodes');
}

# Test 6: Verify use-def chains are correct
{
    my $const_name = $factory->make('Constant', const_type => 'string', value => 'TestRule');
    my $const_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $const_value = $factory->make('Constant', const_type => 'string', value => 'Foo');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('MakeSymbol',
        type => $const_type,
        value => $const_value,
        quantifier => $no_quant,
    );

    my $expression = $factory->make('MakeExpression',
        elements => [$symbol],
    );

    my $rule = $factory->make('MakeRule',
        name => $const_name,
        expressions => $expression,
    );

    # Verify const_name is used by rule
    my @name_consumers = $const_name->consumers()->@*;
    ok((grep { $_ == $rule } @name_consumers), 'const_name is consumed by rule');

    # Verify symbol is used by expression
    my @symbol_consumers = $symbol->consumers()->@*;
    ok((grep { $_ == $expression } @symbol_consumers), 'symbol is consumed by expression');

    # Verify expression is used by rule
    my @expr_consumers = $expression->consumers()->@*;
    ok((grep { $_ == $rule } @expr_consumers), 'expression is consumed by rule');
}

# Test 7: Build multi-rule IR graph
# Build IR for two rules that reference each other
# Rule1 ::= Rule2
# Rule2 ::= /terminal/
{
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $term_type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    # Rule2 ::= /terminal/
    my $rule2_name = $factory->make('Constant', const_type => 'string', value => 'Rule2');
    my $terminal_value = $factory->make('Constant', const_type => 'string', value => 'abc');

    my $terminal_sym = $factory->make('MakeSymbol',
        type => $term_type,
        value => $terminal_value,
        quantifier => $no_quant,
    );

    my $expr2 = $factory->make('MakeExpression',
        elements => [$terminal_sym],
    );

    my $rule2 = $factory->make('MakeRule',
        name => $rule2_name,
        expressions => $expr2,
    );

    # Rule1 ::= Rule2
    my $rule1_name = $factory->make('Constant', const_type => 'string', value => 'Rule1');
    my $rule2_ref_value = $factory->make('Constant', const_type => 'string', value => 'Rule2');

    my $rule2_ref_sym = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $rule2_ref_value,
        quantifier => $no_quant,
    );

    my $expr1 = $factory->make('MakeExpression',
        elements => [$rule2_ref_sym],
    );

    my $rule1 = $factory->make('MakeRule',
        name => $rule1_name,
        expressions => $expr1,
    );

    # Verify structure
    isa_ok($rule1, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created Rule1');
    isa_ok($rule2, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created Rule2');

    is($rule1->inputs()->[0]->value(), 'Rule1', 'Rule1 name correct');
    is($rule2->inputs()->[0]->value(), 'Rule2', 'Rule2 name correct');

    # Rule1's expression references Rule2 (by name string, not by node)
    my $ref_sym = $rule1->inputs()->[1]->inputs()->[0][0];
    is($ref_sym->inputs()->[1]->value(), 'Rule2', 'Rule1 references Rule2 by name');
}

# Test 8: Verify IR can represent quantifiers (*, +, ?)
{
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $sym_value = $factory->make('Constant', const_type => 'string', value => 'Element');

    # Test * quantifier
    my $star_quant = $factory->make('Constant', const_type => 'string', value => '*');
    my $sym_star = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $sym_value,
        quantifier => $star_quant,
    );
    is($sym_star->inputs()->[2]->value(), '*', 'symbol can have * quantifier');

    # Test + quantifier
    my $plus_quant = $factory->make('Constant', const_type => 'string', value => '+');
    my $sym_plus = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $sym_value,
        quantifier => $plus_quant,
    );
    is($sym_plus->inputs()->[2]->value(), '+', 'symbol can have + quantifier');

    # Test ? quantifier
    my $quest_quant = $factory->make('Constant', const_type => 'string', value => '?');
    my $sym_quest = $factory->make('MakeSymbol',
        type => $ref_type,
        value => $sym_value,
        quantifier => $quest_quant,
    );
    is($sym_quest->inputs()->[2]->value(), '?', 'symbol can have ? quantifier');
}

# Test 9: Verify IR can represent both terminal and reference symbols
{
    my $terminal_type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $reference_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $value = $factory->make('Constant', const_type => 'string', value => 'foo');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $terminal_sym = $factory->make('MakeSymbol',
        type => $terminal_type,
        value => $value,
        quantifier => $no_quant,
    );
    is($terminal_sym->inputs()->[0]->value(), 'terminal', 'created terminal symbol');

    my $reference_sym = $factory->make('MakeSymbol',
        type => $reference_type,
        value => $value,
        quantifier => $no_quant,
    );
    is($reference_sym->inputs()->[0]->value(), 'reference', 'created reference symbol');
}

# Test 10: Complex multi-symbol sequence
# Rule ::= Identifier /ws/ /::=/ /ws/ Alternatives /ws/ /;/ /ws/
{
    my $rule_name = $factory->make('Constant', const_type => 'string', value => 'Rule');
    my $ref_type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $term_type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    # Build 8 symbols
    my @symbols;

    # Identifier (reference)
    push @symbols, $factory->make('MakeSymbol',
        type => $ref_type,
        value => $factory->make('Constant', const_type => 'string', value => 'Identifier'),
        quantifier => $no_quant,
    );

    # /ws/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '(?:\\s|#[^\\n]*)*'),
        quantifier => $no_quant,
    );

    # /::=/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '::='),
        quantifier => $no_quant,
    );

    # /ws/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '(?:\\s|#[^\\n]*)*'),
        quantifier => $no_quant,
    );

    # Alternatives (reference)
    push @symbols, $factory->make('MakeSymbol',
        type => $ref_type,
        value => $factory->make('Constant', const_type => 'string', value => 'Alternatives'),
        quantifier => $no_quant,
    );

    # /ws/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '(?:\\s|#[^\\n]*)*'),
        quantifier => $no_quant,
    );

    # /;/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => ';'),
        quantifier => $no_quant,
    );

    # /ws/ (terminal)
    push @symbols, $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '(?:\\s|#[^\\n]*)*'),
        quantifier => $no_quant,
    );

    my $expression = $factory->make('MakeExpression',
        elements => \@symbols,
    );

    my $rule = $factory->make('MakeRule',
        name => $rule_name,
        expressions => $expression,
    );

    isa_ok($rule, 'Chalk::Bootstrap::IR::Node::MakeRule', 'created complex Rule');
    my $elements = $rule->inputs()->[1]->inputs()->[0];
    is(scalar($elements->@*), 8, 'Rule has 8 symbols in sequence');
}

done_testing();
