#!/usr/bin/env perl
# ABOUTME: Parser integration test for Semantic2 semiring (v2 rewrite)
# ABOUTME: Verifies parser wiring with Semantic2 and resulting IR structure
use 5.42.0;
use experimental qw(class builtin);
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Semantic2;

# Preload v2 Rule classes
use Chalk::Grammar::Chalk::Rule::Integer2;
use Chalk::Grammar::Chalk::Rule::Assignment2;
use Chalk::Grammar::Chalk::Rule::Program2;

# Load Chalk grammar from BNF
my $bnf_file = 'grammar/chalk.bnf';
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

# Test 1: Semantic2 can be instantiated
{
    my $semiring = Chalk::Semiring::Semantic2->new(grammar => $grammar);
    ok($semiring, 'Semantic2 semiring can be created');
    isa_ok($semiring, 'Chalk::Semiring::Semantic2', 'Semantic2');
    ok($semiring->env, 'Semantic2 has env');
    ok($semiring->env->{scope}, 'Semantic2 env has scope');
}

# Test 2: Semantic2 can be used with Parser
{
    my $semiring = Chalk::Semiring::Semantic2->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring
    );
    ok($parser, 'Parser can be created with Semantic2 semiring');
}

# Test 3: Parse simple variable assignment and verify IR structure
# Expected IR for "my $x = 42;":
#   Return2
#   ├── control: Store2
#   │            ├── control: Start2(main)
#   │            ├── var: "x"
#   │            └── value: Constant2(Int, 42)
#   └── value: Constant2(Int, 42)
{
    my $code = 'my $x = 42;';
    my $semiring = Chalk::Semiring::Semantic2->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Simple variable assignment parses');

    SKIP: {
        skip "Parse failed, cannot verify IR structure", 10 unless $result;

        # Extract IR node from Element
        my $ir_node = $result->can('context') ? $result->context->focus : $result;
        ok(defined($ir_node), 'IR node extracted from parse result');

        # Debug output
        diag("Result type: " . ref($result)) if ref($result);
        diag("IR node type: " . ref($ir_node)) if defined($ir_node) && ref($ir_node);
        diag("IR node value: $ir_node") if defined($ir_node);

        # Verify result is a Return2 node
        isa_ok($ir_node, 'Chalk::IR::Node::Return2', 'Parse result');

        # Verify Return2 has control and value
        ok($ir_node->can('control'), 'Return2 has control method');
        ok($ir_node->can('value'), 'Return2 has value method');

        my $control = $ir_node->control;
        my $value = $ir_node->value;

        ok(defined($control), 'Return2 control is defined');
        ok(defined($value), 'Return2 value is defined');

        # Verify control is a Store2 node
        isa_ok($control, 'Chalk::IR::Node::Store2', 'Return2 control');

        # Verify Store2 structure
        ok($control->can('var'), 'Store2 has var method');
        ok($control->can('value'), 'Store2 has value method');
        ok($control->can('control'), 'Store2 has control method');

        is($control->var, 'x', 'Store2 var is "x"');

        # Verify Store2's control is Start2
        my $start = $control->control;
        isa_ok($start, 'Chalk::IR::Node::Start2', 'Store2 control');
        is($start->label, 'main', 'Start2 label is "main"');

        # Verify Store2's value is Constant2(Int, 42)
        my $const = $control->value;
        isa_ok($const, 'Chalk::IR::Node::Constant2', 'Store2 value');
        is($const->type, 'Int', 'Constant2 type is Int');
        is($const->value, 42, 'Constant2 value is 42');

        # Verify Return2's value is the same Constant2
        is($value, $const, 'Return2 value is same as Store2 value');

        # Verify to_hash structure
        my $hash = $ir_node->to_hash;
        is($hash->{op}, 'Return', 'to_hash op is Return');
        ok($hash->{inputs}, 'to_hash has inputs');
        is(scalar(@{$hash->{inputs}}), 2, 'Return has 2 inputs (control, value)');
    }
}

# Test 4: Parse simple constant return
# Expected IR for "return 42;":
#   Return2
#   ├── control: Start2(main)
#   └── value: Constant2(Int, 42)
{
    my $code = 'return 42;';
    my $semiring = Chalk::Semiring::Semantic2->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Simple constant return parses');

    SKIP: {
        skip "Parse failed, cannot verify IR structure", 7 unless $result;

        # Extract IR node from Element
        my $ir_node = $result->can('context') ? $result->context->focus : $result;

        # Verify result is a Return2 node
        isa_ok($ir_node, 'Chalk::IR::Node::Return2', 'Parse result');

        my $control = $ir_node->control;
        my $value = $ir_node->value;

        # Verify control is Start2 (no statements before return)
        isa_ok($control, 'Chalk::IR::Node::Start2', 'Return2 control');
        is($control->label, 'main', 'Start2 label is "main"');

        # Verify value is Constant2(Int, 42)
        isa_ok($value, 'Chalk::IR::Node::Constant2', 'Return2 value');
        is($value->type, 'Int', 'Constant2 type is Int');
        is($value->value, 42, 'Constant2 value is 42');

        # Verify to_hash structure
        my $hash = $ir_node->to_hash;
        is($hash->{op}, 'Return', 'to_hash op is Return');
    }
}

# Test 5: Parse multiple statements with proper sequencing
# Expected IR for "my $x = 1; my $y = 2;":
#   Return2
#   ├── control: Store2(y)
#   │            ├── control: Store2(x)
#   │            │            ├── control: Start2(main)
#   │            │            └── value: Constant2(Int, 1)
#   │            └── value: Constant2(Int, 2)
#   └── value: Constant2(Int, 2)
{
    my $code = 'my $x = 1; my $y = 2;';
    my $semiring = Chalk::Semiring::Semantic2->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Multiple statements parse');

    SKIP: {
        skip "Parse failed, cannot verify IR structure", 9 unless $result;

        # Extract IR node from Element
        my $ir_node = $result->can('context') ? $result->context->focus : $result;

        # Verify result is a Return2 node
        isa_ok($ir_node, 'Chalk::IR::Node::Return2', 'Parse result');

        # Walk control chain: Return2 -> Store2(y) -> Store2(x) -> Start2
        my $store_y = $ir_node->control;
        isa_ok($store_y, 'Chalk::IR::Node::Store2', 'Return2 control is Store2(y)');
        is($store_y->var, 'y', 'First store is for var "y"');

        my $store_x = $store_y->control;
        isa_ok($store_x, 'Chalk::IR::Node::Store2', 'Store2(y) control is Store2(x)');
        is($store_x->var, 'x', 'Second store is for var "x"');

        my $start = $store_x->control;
        isa_ok($start, 'Chalk::IR::Node::Start2', 'Store2(x) control is Start2');
        is($start->label, 'main', 'Start2 label is "main"');

        # Verify values
        is($store_x->value->value, 1, 'Store2(x) value is 1');
        is($store_y->value->value, 2, 'Store2(y) value is 2');
    }
}

done_testing();
