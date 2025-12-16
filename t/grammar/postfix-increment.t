# ABOUTME: Tests for postfix increment/decrement IR generation
# ABOUTME: Verifies Unary.pm generates PostIncrement/PostDecrement nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::Unary;
use Chalk::IR::Node::PostIncrement;
use Chalk::IR::Node::PostDecrement;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Helper to create a mock context for postfix operator testing
# Postfix pattern: child(0) is Variable/operand, child(1) is operator
sub mock_postfix_context {
    my ($operand, $operator) = @_;

    # Create a simple mock object for the operator token
    package MockToken {
        use overload '""' => sub { $_[0]->{value} };
        sub new { bless { value => $_[1] }, $_[0] }
        sub extract { $_[0] }
    }

    my $op_token = MockToken->new($operator);

    # Wrap operand in a context first (operand comes before operator in postfix)
    my $operand_ctx = Chalk::EvalContext->new(
        focus => $operand,
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create mock context for operator token
    my $op_child_ctx = Chalk::EvalContext->new(
        focus => $op_token,
        children => [],
        start_pos => 2,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    return Chalk::EvalContext->new(
        children => [$operand_ctx, $op_child_ctx],
        focus => undef,
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'postfix increment generates PostIncrement node' => sub {
    # Create operand (a constant for simplicity)
    my $operand = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    # Create mock context with operand BEFORE operator (postfix pattern)
    my $context = mock_postfix_context($operand, '++');

    # Create Unary rule and evaluate
    my $unary = Chalk::Grammar::Chalk::Rule::Unary->new(lhs => 'Unary', rhs => []);
    my $result = $unary->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::PostIncrement'),
       'Result is PostIncrement node') or diag "Got: " . ref($result);

    # Verify operand is preserved
    is($result->operand, $operand, 'Operand is preserved');
};

subtest 'postfix decrement generates PostDecrement node' => sub {
    # Create operand (a constant for simplicity)
    my $operand = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    # Create mock context with operand BEFORE operator (postfix pattern)
    my $context = mock_postfix_context($operand, '--');

    # Create Unary rule and evaluate
    my $unary = Chalk::Grammar::Chalk::Rule::Unary->new(lhs => 'Unary', rhs => []);
    my $result = $unary->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::PostDecrement'),
       'Result is PostDecrement node') or diag "Got: " . ref($result);

    # Verify operand is preserved
    is($result->operand, $operand, 'Operand is preserved');
};

done_testing();
