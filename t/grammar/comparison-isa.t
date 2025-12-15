# ABOUTME: Tests for ComparisonOp isa operator wiring
# ABOUTME: Verifies ComparisonOp generates ISA node for isa operator

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Token;  # Defines Token::Operator subclass
use Chalk::Grammar::Chalk::Rule::ComparisonOp;
use Chalk::IR::Node::ISA;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Helper to create a mock context for ComparisonOp
sub mock_comparison_context {
    my ($left, $operator, $right) = @_;

    # Create operator token
    my $op_token = Chalk::Grammar::Token::Operator->new(
        value => $operator,
    );

    # Wrap left in context
    my $left_ctx = Chalk::EvalContext->new(
        focus => $left,
        children => [],
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Wrap operator in context
    my $op_ctx = Chalk::EvalContext->new(
        focus => $op_token,
        children => [],
        start_pos => 5,
        end_pos => 8,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Wrap right in context
    my $right_ctx = Chalk::EvalContext->new(
        focus => $right,
        children => [],
        start_pos => 9,
        end_pos => 13,
        env => {},
        grammar => undef,
        rule => undef
    );

    return Chalk::EvalContext->new(
        children => [$left_ctx, $op_ctx, $right_ctx],
        focus => undef,
        start_pos => 0,
        end_pos => 13,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'isa operator generates ISA node' => sub {
    # Create operands
    my $left = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Int',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    # Create mock context
    my $context = mock_comparison_context($left, 'isa', $right);

    # Create ComparisonOp rule and evaluate
    my $comp_op = Chalk::Grammar::Chalk::Rule::ComparisonOp->new(
        lhs => 'ComparisonOp',
        rhs => []
    );
    my $result = $comp_op->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::ISA'),
       'Result is ISA node') or diag "Got: " . ref($result);
};

subtest 'ISA node has correct operands' => sub {
    # Create operands
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    # Create mock context
    my $context = mock_comparison_context($left, 'isa', $right);

    # Create ComparisonOp rule and evaluate
    my $comp_op = Chalk::Grammar::Chalk::Rule::ComparisonOp->new(
        lhs => 'ComparisonOp',
        rhs => []
    );
    my $result = $comp_op->evaluate($context);

    ok($result->isa('Chalk::IR::Node::ISA'), 'Result is ISA node');
    is($result->left, $left, 'Left operand is preserved');
    is($result->right, $right, 'Right operand is preserved');
};

done_testing();
