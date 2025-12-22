# ABOUTME: Tests for ExpressionList semantic action
# ABOUTME: Verifies ExpressionList generates proper List IR nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::ExpressionList;
use Chalk::IR::Node::List;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Helper to create a context with IR node children
sub make_context {
    my (@elements) = @_;

    my @child_contexts;
    my $pos = 0;
    for my $elem (@elements) {
        push @child_contexts, Chalk::EvalContext->new(
            focus => $elem,
            children => [],
            start_pos => $pos,
            end_pos => $pos + 1,
            env => {},
            grammar => undef,
            rule => undef
        );
        $pos += 2;  # Account for comma
    }

    return Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => $pos,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'ExpressionList empty returns undef' => sub {
    my $context = make_context();

    my $rule = Chalk::Grammar::Chalk::Rule::ExpressionList->new(
        lhs => 'ExpressionList',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(!defined($result), 'Empty ExpressionList returns undef');
};

subtest 'ExpressionList single element passes through' => sub {
    my $elem = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $context = make_context($elem);

    my $rule = Chalk::Grammar::Chalk::Rule::ExpressionList->new(
        lhs => 'ExpressionList',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Single element returns IR node');
    is($result->id, $elem->id, 'Returns the same element');
};

subtest 'ExpressionList multiple elements returns List node' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $context = make_context($elem1, $elem2, $elem3);

    my $rule = Chalk::Grammar::Chalk::Rule::ExpressionList->new(
        lhs => 'ExpressionList',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Multiple elements returns blessed object');
    is($result->op, 'List', 'Returns a List node');
    is($result->length, 3, 'List has 3 elements');
    is($result->element_at(0)->id, $elem1->id, 'First element is correct');
    is($result->element_at(1)->id, $elem2->id, 'Second element is correct');
    is($result->element_at(2)->id, $elem3->id, 'Third element is correct');
};

subtest 'ExpressionList with two elements' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 'hello',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 'world',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $context = make_context($elem1, $elem2);

    my $rule = Chalk::Grammar::Chalk::Rule::ExpressionList->new(
        lhs => 'ExpressionList',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Two elements returns blessed object');
    is($result->op, 'List', 'Returns a List node');
    is($result->length, 2, 'List has 2 elements');
};

subtest 'ExpressionList filters non-IR children (like commas)' => sub {
    # This tests that ExpressionList properly filters out non-IR nodes
    # like comma tokens that might appear in the children

    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $comma = ',';  # Non-IR token
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    # Create context with mixed children (IR nodes and tokens)
    my @child_contexts = (
        Chalk::EvalContext->new(
            focus => $elem1,
            children => [],
            start_pos => 0,
            end_pos => 2,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => $comma,
            children => [],
            start_pos => 2,
            end_pos => 3,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => $elem2,
            children => [],
            start_pos => 4,
            end_pos => 6,
            env => {},
            grammar => undef,
            rule => undef
        ),
    );

    my $context = Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 6,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ExpressionList->new(
        lhs => 'ExpressionList',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'List', 'Returns a List node');
    is($result->length, 2, 'List has 2 elements (comma filtered out)');
    is($result->element_at(0)->id, $elem1->id, 'First element is correct');
    is($result->element_at(1)->id, $elem2->id, 'Second element is correct');
};

done_testing();
