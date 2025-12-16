# ABOUTME: Tests for prefix increment/decrement IR generation
# ABOUTME: Verifies Unary.pm generates PreIncrement/PreDecrement nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::Unary;
use Chalk::IR::Node::PreIncrement;
use Chalk::IR::Node::PreDecrement;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Helper to create a mock context for testing
sub mock_context {
    my ($operator, $operand) = @_;

    # Create a simple mock object for the operator token
    package MockToken {
        use overload '""' => sub { $_[0]->{value} };
        sub new { bless { value => $_[1] }, $_[0] }
        sub extract { $_[0] }
    }

    my $op_token = MockToken->new($operator);

    # Create mock context with children
    # Children are EvalContext objects in the real system
    my $op_child_ctx = Chalk::EvalContext->new(
        focus => $op_token,
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Wrap operand in a context too
    my $operand_ctx = Chalk::EvalContext->new(
        focus => $operand,
        children => [],
        start_pos => 2,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    return Chalk::EvalContext->new(
        children => [$op_child_ctx, $operand_ctx],
        focus => undef,
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'prefix increment generates PreIncrement node' => sub {
    # Create operand (a constant for simplicity)
    my $operand = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    # Create mock context
    my $context = mock_context('++', $operand);

    # Create Unary rule and evaluate
    my $unary = Chalk::Grammar::Chalk::Rule::Unary->new(lhs => 'Unary', rhs => []);
    my $result = $unary->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::PreIncrement'),
       'Result is PreIncrement node') or diag "Got: " . ref($result);

    # Verify operand is preserved
    is($result->operand, $operand, 'Operand is preserved');
};

subtest 'prefix decrement generates PreDecrement node' => sub {
    # Create operand (a constant for simplicity)
    my $operand = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    # Create mock context
    my $context = mock_context('--', $operand);

    # Create Unary rule and evaluate
    my $unary = Chalk::Grammar::Chalk::Rule::Unary->new(lhs => 'Unary', rhs => []);
    my $result = $unary->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::PreDecrement'),
       'Result is PreDecrement node') or diag "Got: " . ref($result);

    # Verify operand is preserved
    is($result->operand, $operand, 'Operand is preserved');
};

done_testing();
