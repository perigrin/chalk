# ABOUTME: Tests for ListOp semantic action
# ABOUTME: Verifies ListOp generates Map/Filter IR nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Token;
use Chalk::Grammar::Chalk::Rule::ListOp;
use Chalk::IR::Node::Map;
use Chalk::IR::Node::Filter;
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

# Helper to create mock context for ListOp
sub mock_listop_context {
    my ($op_keyword, $block, $list) = @_;

    # Create keyword token
    my $keyword = Chalk::Grammar::Token->new(value => $op_keyword);
    my $keyword_ctx = Chalk::EvalContext->new(
        focus => $keyword,
        children => [],
        start_pos => 0,
        end_pos => length($op_keyword),
        env => {},
        grammar => undef,
        rule => undef
    );

    # Block context
    my $block_ctx = Chalk::EvalContext->new(
        focus => $block,
        children => [],
        start_pos => length($op_keyword) + 1,
        end_pos => length($op_keyword) + 10,
        env => {},
        grammar => undef,
        rule => undef
    );

    # List/Expression context
    my $list_ctx = Chalk::EvalContext->new(
        focus => $list,
        children => [],
        start_pos => length($op_keyword) + 11,
        end_pos => length($op_keyword) + 20,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Build children: keyword block expression
    my @children = ($keyword_ctx, $block_ctx, $list_ctx);

    return Chalk::EvalContext->new(
        children => \@children,
        focus => undef,
        start_pos => 0,
        end_pos => length($op_keyword) + 20,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'ListOp generates Map node for map keyword' => sub {
    my $block = make_identifier('block_placeholder');
    my $list = make_identifier('list_placeholder');
    my $context = mock_listop_context('map', $block, $list);

    my $rule = Chalk::Grammar::Chalk::Rule::ListOp->new(
        lhs => 'ListOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::Map'),
       'Result is Map node for map keyword') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'ListOp generates Filter node for grep keyword' => sub {
    my $block = make_identifier('block_placeholder');
    my $list = make_identifier('list_placeholder');
    my $context = mock_listop_context('grep', $block, $list);

    my $rule = Chalk::Grammar::Chalk::Rule::ListOp->new(
        lhs => 'ListOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::Filter'),
       'Result is Filter node for grep keyword') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'Map node has correct block and list' => sub {
    my $block = make_identifier('my_block');
    my $list = make_identifier('my_list');
    my $context = mock_listop_context('map', $block, $list);

    my $rule = Chalk::Grammar::Chalk::Rule::ListOp->new(
        lhs => 'ListOp',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok($result->isa('Chalk::IR::Node::Map'), 'Result is Map');
    ok(defined($result->block), 'Map has block');
    ok(defined($result->list), 'Map has list');
};

done_testing();
