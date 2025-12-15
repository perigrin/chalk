# ABOUTME: Tests for Match/NotMatch operators in ComparisonOp
# ABOUTME: Verifies =~ and !~ generate Match/NotMatch IR nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Token;  # Defines Token::Operator subclass
use Chalk::Grammar::Chalk::Rule::ComparisonOp;
use Chalk::IR::Node::Match;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Create fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Helper to create identifier constant
sub make_identifier {
    my ($name) = @_;
    return Chalk::IR::Node::Constant->new(
        value => $name,
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
}

# Helper to create mock context for ComparisonOp
sub mock_comparison_context {
    my ($left, $operator, $right) = @_;

    # Left operand context
    my $left_ctx = Chalk::EvalContext->new(
        focus => $left,
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Operator context
    my $op_token = Chalk::Grammar::Token::Operator->new(value => $operator);
    my $op_ctx = Chalk::EvalContext->new(
        focus => $op_token,
        children => [],
        start_pos => 6,
        end_pos => 6 + length($operator),
        env => {},
        grammar => undef,
        rule => undef
    );

    # Right operand context
    my $right_ctx = Chalk::EvalContext->new(
        focus => $right,
        children => [],
        start_pos => 10,
        end_pos => 15,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Build children
    my @children = ($left_ctx, $op_ctx, $right_ctx);

    return Chalk::EvalContext->new(
        children => \@children,
        focus => undef,
        start_pos => 0,
        end_pos => 15,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'Match operator =~ generates Match node' => sub {
    my $left = make_identifier('$string');
    my $right = make_identifier('/pattern/');
    my $context = mock_comparison_context($left, '=~', $right);

    my $rule = Chalk::Grammar::Chalk::Rule::ComparisonOp->new(
        lhs => 'ComparisonOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::Match'),
       'Result is Match node for =~ operator') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'NotMatch operator !~ generates NotMatch node' => sub {
    my $left = make_identifier('$string');
    my $right = make_identifier('/pattern/');
    my $context = mock_comparison_context($left, '!~', $right);

    my $rule = Chalk::Grammar::Chalk::Rule::ComparisonOp->new(
        lhs => 'ComparisonOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::NotMatch'),
       'Result is NotMatch node for !~ operator') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'Match node has correct left and right' => sub {
    my $left = make_identifier('my_string');
    my $right = make_identifier('my_pattern');
    my $context = mock_comparison_context($left, '=~', $right);

    my $rule = Chalk::Grammar::Chalk::Rule::ComparisonOp->new(
        lhs => 'ComparisonOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok($result->isa('Chalk::IR::Node::Match'), 'Result is Match');
    ok(defined($result->left), 'Match has left');
    ok(defined($result->right), 'Match has right');
    is($result->left->id, $left->id, 'left is correct');
    is($result->right->id, $right->id, 'right is correct');
};

done_testing();
