# ABOUTME: Tests for Cast node implementation (type upcasting/projection)
# ABOUTME: Cast refines input type by joining with target type, used after guard tests

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node::Cast;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Ctrl;
use Chalk::IR::Graph;

subtest 'Cast node construction' => sub {
    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Ctrl->CTRL(),
    );

    my $input = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    my $target_type = Chalk::IR::Type::Integer->constant(42);

    my $cast = Chalk::IR::Node::Cast->new(
        inputs      => [$ctrl->id, $input->id],
        target_type => $target_type,
        ctrl        => $ctrl,
        input       => $input,
    );

    is $cast->op, 'Cast', 'Cast node has correct op';
    ok defined $cast->target_type, 'Cast has target_type field';
    ok defined $cast->ctrl, 'Cast has ctrl field';
    ok defined $cast->input, 'Cast has input field';
};

subtest 'Cast compute() joins input and target types' => sub {
    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Ctrl->CTRL(),
    );

    my $input = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    # Target type: Integer constant 42
    my $target_type = Chalk::IR::Type::Integer->constant(42);

    my $cast = Chalk::IR::Node::Cast->new(
        inputs      => [$ctrl->id, $input->id],
        target_type => $target_type,
        ctrl        => $ctrl,
        input       => $input,
    );

    my $result_type = $cast->compute();
    ok $result_type->is_constant, 'Cast computes constant type';
    is $result_type->value, 42, 'Cast preserves constant value when types match';
};

subtest 'Cast peephole removes redundant cast' => sub {
    plan 1;

    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Ctrl->CTRL(),
    );

    my $input = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    # Target type: Integer TOP (any integer)
    my $target_type = Chalk::IR::Type::Integer->TOP();

    my $cast = Chalk::IR::Node::Cast->new(
        inputs      => [$ctrl->id, $input->id],
        target_type => $target_type,
        ctrl        => $ctrl,
        input       => $input,
    );

    my $graph = Chalk::IR::Graph->new();
    $graph->add_node($ctrl);
    $graph->add_node($input);
    $graph->add_node($cast);

    # When input type satisfies target type, cast should be removed
    my $optimized = $cast->peephole($graph);

    # Cast should return the input node directly
    is $optimized->id, $input->id, 'Redundant cast eliminated, returns input';
};

subtest 'Cast peephole preserves necessary cast' => sub {
    plan 1;

    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Ctrl->CTRL(),
    );

    my $input = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    # Target type: Integer constant 7 (different from input)
    my $target_type = Chalk::IR::Type::Integer->constant(7);

    my $cast = Chalk::IR::Node::Cast->new(
        inputs      => [$ctrl->id, $input->id],
        target_type => $target_type,
        ctrl        => $ctrl,
        input       => $input,
    );

    my $graph = Chalk::IR::Graph->new();
    $graph->add_node($ctrl);
    $graph->add_node($input);
    $graph->add_node($cast);

    # When input type doesn't satisfy target type, cast should remain
    my $optimized = $cast->peephole($graph);

    # Cast should return itself
    is $optimized->id, $cast->id, 'Necessary cast preserved';
};

subtest 'Cast to_hash includes attributes' => sub {
    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Ctrl->CTRL(),
    );

    my $input = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    my $target_type = Chalk::IR::Type::Integer->constant(42);

    my $cast = Chalk::IR::Node::Cast->new(
        inputs      => [$ctrl->id, $input->id],
        target_type => $target_type,
        ctrl        => $ctrl,
        input       => $input,
    );

    my $hash = $cast->to_hash();

    is $hash->{op}, 'Cast', 'to_hash includes correct op';
    ok defined $hash->{attributes}{target_type}, 'to_hash includes target_type attribute';
};
