# ABOUTME: Integration test for Phase 2b - Semantic actions building IR from parse contexts
# ABOUTME: Verifies that semantic actions correctly construct IR nodes from Context trees
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: action_Identifier creates Constant with identifier value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'Element',
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Identifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'action_Identifier creates Constant');
    is($result->const_type(), 'string', 'Identifier constant is string type');
    is($result->value(), 'Element', 'Identifier value preserved');
}

# Test 2: action_InlineRegex creates Constant with regex value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '/[A-Za-z]+/',
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_InlineRegex($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'action_InlineRegex creates Constant');
    is($result->const_type(), 'string', 'InlineRegex constant is string type');
    is($result->value(), '/[A-Za-z]+/', 'InlineRegex value preserved');
}

# Test 3: action_Quantifier creates Constant with quantifier value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '+',
        children => [],
        position => 0,
        rule     => 'Quantifier',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Quantifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'action_Quantifier creates Constant');
    is($result->const_type(), 'string', 'Quantifier constant is string type');
    is($result->value(), '+', 'Quantifier value preserved');
}

# Test 4: action_Atom with Identifier creates reference symbol
{
    # Create Identifier context with Constant node as focus
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Element');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Atom context with Identifier child
    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$name_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'action_Atom creates MakeSymbol');
    is($result->inputs()->[0]->value(), 'reference', 'Atom with Identifier is reference type');
    is($result->inputs()->[1]->value(), 'Element', 'Atom value from Identifier');
    ok(!defined $result->inputs()->[2]->value(), 'Atom has no quantifier initially');
}

# Test 5: action_Atom with InlineRegex creates terminal symbol
{
    my $regex_const = $factory->make('Constant', const_type => 'string', value => '/[A-Z]+/');
    my $regex_ctx = Chalk::Bootstrap::Context->new(
        focus    => $regex_const,
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$regex_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'action_Atom creates MakeSymbol');
    is($result->inputs()->[0]->value(), 'terminal', 'Atom with InlineRegex is terminal type');
    is($result->inputs()->[1]->value(), '/[A-Z]+/', 'Atom value from InlineRegex');
}

# Test 6: action_Element with Atom only (no quantifier)
{
    # Create Atom symbol
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('MakeSymbol',
        type => $type_const,
        value => $name_const,
        quantifier => $quant_const,
    );

    my $symbol_ctx = Chalk::Bootstrap::Context->new(
        focus    => $symbol,
        children => [],
        position => 0,
        rule     => 'Atom',
    );

    # Element context with just Atom child (no quantifier)
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx],
        position => 0,
        rule     => 'Element',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'action_Element returns symbol');
    ok(!defined $result->inputs()->[2]->value(), 'Element has no quantifier');
}

# Test 7: action_Element with Atom and Quantifier
{
    # Create Atom symbol
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Rule');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('MakeSymbol',
        type => $type_const,
        value => $name_const,
        quantifier => $quant_const,
    );

    my $symbol_ctx = Chalk::Bootstrap::Context->new(
        focus    => $symbol,
        children => [],
        position => 0,
        rule     => 'Atom',
    );

    # Create Quantifier node
    my $quant_val = $factory->make('Constant', const_type => 'string', value => '+');
    my $quant_ctx = Chalk::Bootstrap::Context->new(
        focus    => $quant_val,
        children => [],
        position => 4,
        rule     => 'Quantifier',
    );

    # Element context with Atom and Quantifier children
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx, $quant_ctx],
        position => 4,
        rule     => 'Element',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'action_Element returns symbol');
    is($result->inputs()->[2]->value(), '+', 'Element has + quantifier');
}

# Test 8: action_Sequence collects multiple Elements into MakeExpression
{
    # Create two Element symbols
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $elem1 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'Atom'),
        quantifier => $no_quant,
    );

    my $elem2 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'Quantifier'),
        quantifier => $no_quant,
    );

    my $elem1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $elem1,
        children => [],
        position => 0,
        rule     => 'Element',
    );

    my $elem2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $elem2,
        children => [],
        position => 5,
        rule     => 'Element',
    );

    # Sequence context with two Element children
    my $seq_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$elem1_ctx, $elem2_ctx],
        position => 5,
        rule     => 'Sequence',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Sequence($seq_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeExpression', 'action_Sequence creates MakeExpression');
    my $elements = $result->inputs()->[0];
    is(scalar($elements->@*), 2, 'Sequence has 2 elements');
    is($elements->[0]->inputs()->[1]->value(), 'Atom', 'first element is Atom');
    is($elements->[1]->inputs()->[1]->value(), 'Quantifier', 'second element is Quantifier');
}

# Test 9: action_Alternatives collects multiple Sequences into arrayref
{
    # Create two Sequence expressions
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $sym1 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'Identifier'),
        quantifier => $no_quant,
    );

    my $expr1 = $factory->make('MakeExpression',
        elements => [$sym1],
    );

    my $sym2 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'InlineRegex'),
        quantifier => $no_quant,
    );

    my $expr2 = $factory->make('MakeExpression',
        elements => [$sym2],
    );

    my $seq1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr1,
        children => [],
        position => 0,
        rule     => 'Sequence',
    );

    my $seq2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr2,
        children => [],
        position => 10,
        rule     => 'Sequence',
    );

    # Alternatives context with two Sequence children
    my $alts_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$seq1_ctx, $seq2_ctx],
        position => 10,
        rule     => 'Alternatives',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Alternatives($alts_ctx);

    ok(ref($result) eq 'ARRAY', 'action_Alternatives returns arrayref');
    is(scalar($result->@*), 2, 'Alternatives has 2 expressions');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'first alternative is MakeExpression');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'second alternative is MakeExpression');
}

# Test 10: action_Rule builds MakeRule from name and alternatives
{
    # Create rule name
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Create alternatives arrayref (two expressions)
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    my $sym1 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'Identifier'),
        quantifier => $no_quant,
    );

    my $expr1 = $factory->make('MakeExpression',
        elements => [$sym1],
    );

    my $sym2 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'InlineRegex'),
        quantifier => $no_quant,
    );

    my $expr2 = $factory->make('MakeExpression',
        elements => [$sym2],
    );

    my $alts_arrayref = [$expr1, $expr2];

    my $alts_ctx = Chalk::Bootstrap::Context->new(
        focus    => $alts_arrayref,
        children => [],
        position => 20,
        rule     => 'Alternatives',
    );

    # Dummy whitespace and punctuation contexts (focus is undef, will be skipped)
    my $ws_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 5,
        rule     => 'Whitespace',
    );

    # Rule context with Identifier and Alternatives children
    my $rule_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$name_ctx, $ws_ctx, $ws_ctx, $alts_ctx, $ws_ctx],
        position => 30,
        rule     => 'Rule',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Rule($rule_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeRule', 'action_Rule creates MakeRule');
    is($result->inputs()->[0]->value(), 'Atom', 'rule name is Atom');

    my $expressions = $result->inputs()->[1];
    ok(ref($expressions) eq 'ARRAY', 'rule expressions is arrayref');
    is(scalar($expressions->@*), 2, 'rule has 2 alternatives');
}

# Test 11: action_Grammar collects multiple Rules into arrayref
{
    # Create two MakeRule nodes
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $no_quant = $factory->make('Constant', const_type => 'string', value => undef);

    # Rule 1: Atom ::= Identifier
    my $rule1_name = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $sym1 = $factory->make('MakeSymbol',
        type => $type_const,
        value => $factory->make('Constant', const_type => 'string', value => 'Identifier'),
        quantifier => $no_quant,
    );
    my $expr1 = $factory->make('MakeExpression', elements => [$sym1]);
    my $rule1 = $factory->make('MakeRule',
        name => $rule1_name,
        expressions => [$expr1],
    );

    # Rule 2: Quantifier ::= /\*/
    my $rule2_name = $factory->make('Constant', const_type => 'string', value => 'Quantifier');
    my $term_type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $sym2 = $factory->make('MakeSymbol',
        type => $term_type,
        value => $factory->make('Constant', const_type => 'string', value => '\\*'),
        quantifier => $no_quant,
    );
    my $expr2 = $factory->make('MakeExpression', elements => [$sym2]);
    my $rule2 = $factory->make('MakeRule',
        name => $rule2_name,
        expressions => [$expr2],
    );

    my $rule1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $rule1,
        children => [],
        position => 0,
        rule     => 'Rule',
    );

    my $rule2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $rule2,
        children => [],
        position => 20,
        rule     => 'Rule',
    );

    # Whitespace context (will be skipped)
    my $ws_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        rule     => 'Whitespace',
    );

    # Grammar context with whitespace and two Rule children
    my $grammar_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$ws_ctx, $rule1_ctx, $rule2_ctx],
        position => 40,
        rule     => 'Grammar',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Grammar($grammar_ctx);

    ok(ref($result) eq 'ARRAY', 'action_Grammar returns arrayref');
    is(scalar($result->@*), 2, 'Grammar has 2 rules');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::MakeRule', 'first rule is MakeRule');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::MakeRule', 'second rule is MakeRule');
    is($result->[0]->inputs()->[0]->value(), 'Atom', 'first rule is Atom');
    is($result->[1]->inputs()->[0]->value(), 'Quantifier', 'second rule is Quantifier');
}

# Test 12: action_Comment returns undef (comments are ignored)
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '# this is a comment',
        children => [],
        position => 0,
        rule     => 'Comment',
    );

    my $result = Chalk::Grammar::BNF::Actions::action_Comment($ctx);

    ok(!defined $result, 'action_Comment returns undef');
}

# Test 13: Multi-rule grammar with alternatives
# Build complete parse tree for: Atom ::= Identifier | InlineRegex
{
    # Build the parse tree bottom-up

    # Identifier constant
    my $ident_const = $factory->make('Constant', const_type => 'string', value => 'Identifier');
    my $ident_ctx = Chalk::Bootstrap::Context->new(
        focus    => $ident_const,
        children => [],
        position => 10,
        rule     => 'Identifier',
    );

    # Atom context for Identifier
    my $atom1_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$ident_ctx],
        position => 10,
        rule     => 'Atom',
    );

    my $atom1_ir = Chalk::Grammar::BNF::Actions::action_Atom($atom1_ctx);

    # Element context for Identifier
    my $elem1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $atom1_ir,
        children => [],
        position => 10,
        rule     => 'Element',
    );

    # Sequence context for Identifier
    my $seq1_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$elem1_ctx],
        position => 10,
        rule     => 'Sequence',
    );

    my $seq1_ir = Chalk::Grammar::BNF::Actions::action_Sequence($seq1_ctx);

    # InlineRegex constant
    my $regex_const = $factory->make('Constant', const_type => 'string', value => 'InlineRegex');
    my $regex_ctx = Chalk::Bootstrap::Context->new(
        focus    => $regex_const,
        children => [],
        position => 25,
        rule     => 'Identifier',
    );

    # Atom context for InlineRegex
    my $atom2_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$regex_ctx],
        position => 25,
        rule     => 'Atom',
    );

    my $atom2_ir = Chalk::Grammar::BNF::Actions::action_Atom($atom2_ctx);

    # Element context for InlineRegex
    my $elem2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $atom2_ir,
        children => [],
        position => 25,
        rule     => 'Element',
    );

    # Sequence context for InlineRegex
    my $seq2_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$elem2_ctx],
        position => 25,
        rule     => 'Sequence',
    );

    my $seq2_ir = Chalk::Grammar::BNF::Actions::action_Sequence($seq2_ctx);

    # Alternatives context with both sequences
    my $alts_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [
            Chalk::Bootstrap::Context->new(focus => $seq1_ir, children => [], position => 10, rule => 'Sequence'),
            Chalk::Bootstrap::Context->new(focus => $seq2_ir, children => [], position => 25, rule => 'Sequence'),
        ],
        position => 25,
        rule     => 'Alternatives',
    );

    my $alts_ir = Chalk::Grammar::BNF::Actions::action_Alternatives($alts_ctx);

    # Rule name: Atom
    my $rule_name_const = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $rule_name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $rule_name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Rule context
    my $rule_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [
            $rule_name_ctx,
            Chalk::Bootstrap::Context->new(focus => $alts_ir, children => [], position => 25, rule => 'Alternatives'),
        ],
        position => 30,
        rule     => 'Rule',
    );

    my $rule_ir = Chalk::Grammar::BNF::Actions::action_Rule($rule_ctx);

    # Verify the complete rule
    isa_ok($rule_ir, 'Chalk::Bootstrap::IR::Node::MakeRule', 'complete rule is MakeRule');
    is($rule_ir->inputs()->[0]->value(), 'Atom', 'rule name is Atom');

    my $exprs = $rule_ir->inputs()->[1];
    ok(ref($exprs) eq 'ARRAY', 'rule has arrayref of expressions');
    is(scalar($exprs->@*), 2, 'rule has 2 alternatives');

    # Verify first alternative (Identifier)
    my $expr1_elements = $exprs->[0]->inputs()->[0];
    is(scalar($expr1_elements->@*), 1, 'first alternative has 1 element');
    is($expr1_elements->[0]->inputs()->[1]->value(), 'Identifier', 'first alternative is Identifier');

    # Verify second alternative (InlineRegex)
    my $expr2_elements = $exprs->[1]->inputs()->[0];
    is(scalar($expr2_elements->@*), 1, 'second alternative has 1 element');
    is($expr2_elements->[0]->inputs()->[1]->value(), 'InlineRegex', 'second alternative is InlineRegex');
}

done_testing();
