# ABOUTME: Tests semantic actions for building IR from BNF meta-grammar parse results
# ABOUTME: Verifies each of the 10 semantic action functions builds correct IR nodes
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

# Create Actions instance to use throughout tests
my $actions = Chalk::Grammar::BNF::Actions->new();

# Test 1: Identifier action creates Constant node with identifier value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'Element',
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    my $result = $actions->Identifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Identifier creates Constant');
    is($result->const_type(), 'string', 'Identifier constant is string type');
    is($result->value(), 'Element', 'Identifier value is preserved');
}

# Test 2: InlineRegex action creates Constant node with regex value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '/[A-Z]+/',
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    my $result = $actions->InlineRegex($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'InlineRegex creates Constant');
    is($result->const_type(), 'string', 'InlineRegex constant is string type');
    is($result->value(), '/[A-Z]+/', 'InlineRegex value is preserved');
}

# Test 3: Quantifier action returns quantifier string
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '*',
        children => [],
        position => 0,
        rule     => 'Quantifier',
    );

    my $result = $actions->Quantifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Quantifier creates Constant');
    is($result->const_type(), 'string', 'Quantifier constant is string type');
    is($result->value(), '*', 'Quantifier value is preserved');
}

# Test 4: Atom action with Identifier creates reference symbol
{
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Element');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Atom ::= Identifier
    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$name_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = $actions->Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Symbol', 'Atom creates Symbol');
    is($result->inputs()->[0]->value(), 'reference', 'Atom type is reference');
    is($result->inputs()->[1]->value(), 'Element', 'Atom value from Identifier');
}

# Test 5: Atom action with InlineRegex creates terminal symbol
{
    my $regex_const = $factory->make('Constant', const_type => 'string', value => '/[A-Z]+/');
    my $regex_ctx = Chalk::Bootstrap::Context->new(
        focus    => $regex_const,
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    # Atom ::= InlineRegex
    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$regex_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = $actions->Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Symbol', 'Atom creates Symbol');
    is($result->inputs()->[0]->value(), 'terminal', 'Atom type is terminal');
    is($result->inputs()->[1]->value(), '/[A-Z]+/', 'Atom value from InlineRegex');
}

# Test 6: Element action with Atom only (no quantifier)
{
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('Constructor',
        class => 'Symbol',
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

    # Element ::= Atom (no quantifier)
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx],
        position => 0,
        rule     => 'Element',
    );

    my $result = $actions->Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Symbol', 'Element returns symbol');
    is($result->inputs()->[2]->value(), undef, 'Element has no quantifier');
}

# Test 7: Element action with Atom and Quantifier
{
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Rule');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('Constructor',
        class => 'Symbol',
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

    my $quant_val = $factory->make('Constant', const_type => 'string', value => '+');
    my $quant_ctx = Chalk::Bootstrap::Context->new(
        focus    => $quant_val,
        children => [],
        position => 5,
        rule     => 'Quantifier',
    );

    # Element ::= Atom Quantifier
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx, $quant_ctx],
        position => 5,
        rule     => 'Element',
    );

    my $result = $actions->Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Symbol', 'Element returns symbol');
    is($result->inputs()->[2]->value(), '+', 'Element has quantifier');
}

# Test 8: Alternatives flattens binary Context trees (verifies Context->leaves() behavior)
{
    # Build a binary tree to verify that Alternatives correctly flattens the tree structure.
    # This tests Context->leaves() behavior through the public API.
    my $elem1 = $factory->make('Constant', const_type => 'string', value => 'A');
    my $expr1 = $factory->make('Constructor',
        class => 'Expression', elements => [$elem1]);
    my $seq1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr1,
        children => [],
        position => 0,
        rule     => 'Sequence',
    );

    my $elem2 = $factory->make('Constant', const_type => 'string', value => 'B');
    my $expr2 = $factory->make('Constructor',
        class => 'Expression', elements => [$elem2]);
    my $seq2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr2,
        children => [],
        position => 2,
        rule     => 'Sequence',
    );

    # Build binary tree: multiply(multiply(one, seq1), seq2)
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        rule     => undef,
    );

    my $inner = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $seq1_ctx],
        position => 1,
        rule     => undef,
    );

    my $outer = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$inner, $seq2_ctx],
        position => 2,
        rule     => 'Alternatives',
    );

    my $result = $actions->Alternatives($outer);

    isa_ok($result, 'ARRAY', 'Alternatives returns arrayref');
    is(scalar($result->@*), 2, 'Alternatives flattens binary tree to find 2 expressions');
    is($result->[0]->inputs()->[0]->[0]->value(), 'A', 'first alternative element is A');
    is($result->[1]->inputs()->[0]->[0]->value(), 'B', 'second alternative element is B');
}

# Test 9: Alternatives with parser-style binary tree
{
    # Alternatives ::= Sequence | Sequence | Alternatives
    # Parser builds: multiply(multiply(one, seq1_ctx), pipe_ws_ctx, alt_ctx)
    # But with complete_value, each Sequence child has an Expression focus

    my $elem1 = $factory->make('Constant', const_type => 'string', value => 'sym1');
    my $expr1 = $factory->make('Constructor',
        class => 'Expression', elements => [$elem1]);
    my $seq1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr1,
        children => [],
        position => 0,
        rule     => 'Sequence',
    );

    my $elem2 = $factory->make('Constant', const_type => 'string', value => 'sym2');
    my $expr2 = $factory->make('Constructor',
        class => 'Expression', elements => [$elem2]);
    my $seq2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $expr2,
        children => [],
        position => 10,
        rule     => 'Sequence',
    );

    # Whitespace/pipe contexts (no rule, no meaningful focus)
    my $ws_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 5,
        rule     => undef,
    );

    # Binary tree: multiply(multiply(multiply(multiply(one, seq1), ws), pipe), multiply(multiply(one, ws), seq2))
    # Simplified: just put both sequences as leaves in a binary tree
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        rule     => undef,
    );

    my $left = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $seq1_ctx],
        position => 0,
        rule     => undef,
    );

    my $mid = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$left, $ws_ctx],
        position => 5,
        rule     => undef,
    );

    # Nested Alternatives for second sequence
    my $one_ctx2 = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 6,
        rule     => undef,
    );
    my $inner_alt = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx2, $seq2_ctx],
        position => 10,
        rule     => undef,
    );

    my $outer = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$mid, $inner_alt],
        position => 10,
        rule     => 'Alternatives',
    );

    my $result = $actions->Alternatives($outer);

    isa_ok($result, 'ARRAY', 'Alternatives returns arrayref');
    is(scalar($result->@*), 2, 'Alternatives finds 2 expressions in binary tree');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->[0]->class(), 'Expression', 'first alt is Expression');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->[1]->class(), 'Expression', 'second alt is Expression');
}

# Test 10: Sequence with parser-style binary tree
{
    my $type1 = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $val1 = $factory->make('Constant', const_type => 'string', value => 'Foo');
    my $quant1 = $factory->make('Constant', const_type => 'string', value => undef);
    my $sym1 = $factory->make('Constructor',
        class => 'Symbol', type => $type1, value => $val1, quantifier => $quant1);

    my $type2 = $factory->make('Constant', const_type => 'enum', value => 'terminal');
    my $val2 = $factory->make('Constant', const_type => 'string', value => '/bar/');
    my $quant2 = $factory->make('Constant', const_type => 'string', value => undef);
    my $sym2 = $factory->make('Constructor',
        class => 'Symbol', type => $type2, value => $val2, quantifier => $quant2);

    my $sym1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $sym1,
        children => [],
        position => 0,
        rule     => 'Element',
    );

    my $sym2_ctx = Chalk::Bootstrap::Context->new(
        focus    => $sym2,
        children => [],
        position => 5,
        rule     => 'Element',
    );

    # Build binary tree
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );
    my $ws_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 3, rule => undef,
    );

    my $left = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $sym1_ctx],
        position => 0,
        rule     => undef,
    );

    my $mid = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$left, $ws_ctx],
        position => 3,
        rule     => undef,
    );

    my $outer = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$mid, $sym2_ctx],
        position => 5,
        rule     => 'Sequence',
    );

    my $result = $actions->Sequence($outer);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Expression', 'Sequence returns Expression');
    # inputs()->[0] is the elements arrayref (Expression's single input)
    my $elements = $result->inputs()->[0];
    is(scalar($elements->@*), 2, 'Sequence finds 2 elements in binary tree');
    isa_ok($elements->[0], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($elements->[0]->class(), 'Symbol', 'first element is Symbol');
    isa_ok($elements->[1], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($elements->[1]->class(), 'Symbol', 'second element is Symbol');
}

# Test 11: Sequence handles mixed node types (verifies Context->leaves() filtering)
{
    # Sequence should extract only Symbol nodes and ignore other node types.
    # This tests the class filtering behavior of Context->leaves() through the public API.
    my $type = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $val = $factory->make('Constant', const_type => 'string', value => 'X');
    my $quant = $factory->make('Constant', const_type => 'string', value => undef);
    my $sym = $factory->make('Constructor',
        class => 'Symbol', type => $type, value => $val, quantifier => $quant);
    my $ctx_sym = Chalk::Bootstrap::Context->new(
        focus    => $sym,
        children => [],
        position => 5,
        rule     => 'Element',
    );

    # Add some noise: a Constant node that should be ignored by Sequence
    my $node_const = $factory->make('Constant', const_type => 'string', value => 'ignored');
    my $ctx_const = Chalk::Bootstrap::Context->new(
        focus    => $node_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Build binary tree with mixed node types
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        rule     => undef,
    );

    my $left = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $ctx_const],
        position => 0,
        rule     => undef,
    );

    my $tree = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$left, $ctx_sym],
        position => 5,
        rule     => 'Sequence',
    );

    my $result = $actions->Sequence($tree);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Expression', 'Sequence returns Expression');
    my $elements = $result->inputs()->[0];
    is(scalar($elements->@*), 1, 'Sequence filters to find only 1 Symbol (ignoring Constant)');
    isa_ok($elements->[0], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($elements->[0]->class(), 'Symbol', 'filtered result is Symbol');
}

# Test 12: Rule_star flattens recursive list
{
    my $rule1 = $factory->make('Constructor',
        class => 'Rule',
        name => $factory->make('Constant', const_type => 'string', value => 'A'),
        expressions => [],
    );
    my $rule2 = $factory->make('Constructor',
        class => 'Rule',
        name => $factory->make('Constant', const_type => 'string', value => 'B'),
        expressions => [],
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
        position => 10,
        rule     => 'Rule',
    );

    # Binary tree: multiply(one, rule1), then multiply(that, rule2)
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );
    my $left = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $rule1_ctx],
        position => 0,
        rule     => undef,
    );
    my $tree = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$left, $rule2_ctx],
        position => 10,
        rule     => 'Rule_star',
    );

    my $result = $actions->Rule_star($tree);

    isa_ok($result, 'ARRAY', 'Rule_star returns arrayref');
    is(scalar($result->@*), 2, 'Rule_star collects 2 rules');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->[0]->class(), 'Rule', 'first is MakeRule');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->[1]->class(), 'Rule', 'second is MakeRule');
}

# Test 13: Rule_plus delegates to Rule_star
{
    my $rule1 = $factory->make('Constructor',
        class => 'Rule',
        name => $factory->make('Constant', const_type => 'string', value => 'X'),
        expressions => [],
    );

    my $rule1_ctx = Chalk::Bootstrap::Context->new(
        focus    => $rule1,
        children => [],
        position => 0,
        rule     => 'Rule',
    );

    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );
    my $tree = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $rule1_ctx],
        position => 0,
        rule     => 'Rule_plus',
    );

    my $result = $actions->Rule_plus($tree);

    isa_ok($result, 'ARRAY', 'Rule_plus returns arrayref');
    is(scalar($result->@*), 1, 'Rule_plus collects 1 rule');
}

# Test 14: Quantifier_opt with quantifier present
{
    my $quant_val = $factory->make('Constant', const_type => 'string', value => '+');
    my $quant_ctx = Chalk::Bootstrap::Context->new(
        focus    => $quant_val,
        children => [],
        position => 0,
        rule     => 'Quantifier',
    );

    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );
    my $tree = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $quant_ctx],
        position => 0,
        rule     => 'Quantifier_opt',
    );

    my $result = $actions->Quantifier_opt($tree);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Quantifier_opt with value returns Constant');
    is($result->value(), '+', 'Quantifier_opt preserves quantifier value');
}

# Test 15: Quantifier_opt with epsilon (no quantifier)
{
    # Epsilon match: just the one() context with no meaningful children
    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );
    my $tree = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx],
        position => 0,
        rule     => 'Quantifier_opt',
    );

    my $result = $actions->Quantifier_opt($tree);

    ok(!defined($result), 'Quantifier_opt with epsilon returns undef');
}

# Test 16: Atom uses rule field instead of regex matching
{
    # When complete_value is wired, child contexts have rule field set
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'SomeName');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    my $one_ctx = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, rule => undef,
    );

    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$one_ctx, $name_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = $actions->Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($result->class(), 'Symbol', 'Atom creates MakeSymbol');
    is($result->inputs()->[0]->value(), 'reference', 'Atom correctly identifies reference via rule field');
}

done_testing();
