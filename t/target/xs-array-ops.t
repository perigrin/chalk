# ABOUTME: Test XS visitors for array operations (NewArray, ArrayLoad, ArrayStore, ArrayLength)
# ABOUTME: Verifies correct AV* operations in generated XS code
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::Target::XS;
use Chalk::IR::Graph;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::ArrayLoad;
use Chalk::IR::Node::ArrayStore;
use Chalk::IR::Node::ArrayLength;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

# Test 1: NewArray visitor
subtest 'NewArray generates newAV()' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $new_array = Chalk::IR::Node::NewArray->new(inputs => []);
    $graph->add_node($new_array);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );
    my $xs_node = $xs->visit($new_array);

    ok(defined $xs_node, 'NewArray visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'NewArray emits code');
    like($code, qr/AV\s*\*/, 'NewArray declares AV* type');
    like($code, qr/newAV\s*\(\s*\)/, 'NewArray uses newAV()');
};

# Test 2: ArrayLoad visitor
subtest 'ArrayLoad generates av_fetch' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create array and index nodes
    my $array = Chalk::IR::Node::NewArray->new(inputs => []);
    $graph->add_node($array);

    my $index = Chalk::IR::Node::Constant->new(
        value => 0,
        type  => Chalk::IR::Type::Integer->constant(0),
    );
    $graph->add_node($index);

    my $load = Chalk::IR::Node::ArrayLoad->new(
        inputs => [],
        array => $array,
        index => $index,
    );
    $graph->add_node($load);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit array first to bind it
    $xs->visit($array);
    # Visit index to bind it
    $xs->visit($index);

    my $xs_node = $xs->visit($load);
    ok(defined $xs_node, 'ArrayLoad visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'ArrayLoad emits code');
    like($code, qr/av_fetch/, 'ArrayLoad uses av_fetch');
    like($code, qr/elem\s*\?\s*\*elem\s*:\s*&PL_sv_undef/, 'ArrayLoad handles NULL with undef fallback');
};

# Test 3: ArrayStore visitor
subtest 'ArrayStore generates av_store' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $array = Chalk::IR::Node::NewArray->new(inputs => []);
    $graph->add_node($array);

    my $index = Chalk::IR::Node::Constant->new(
        value => 0,
        type  => Chalk::IR::Type::Integer->constant(0),
    );
    $graph->add_node($index);

    my $value = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );
    $graph->add_node($value);

    my $store = Chalk::IR::Node::ArrayStore->new(
        inputs => [],
        array => $array,
        index => $index,
        value => $value,
    );
    $graph->add_node($store);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit dependencies first
    $xs->visit($array);
    $xs->visit($index);
    $xs->visit($value);

    my $xs_node = $xs->visit($store);
    ok(defined $xs_node, 'ArrayStore visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'ArrayStore emits code');
    like($code, qr/av_store/, 'ArrayStore uses av_store');
    like($code, qr/newSVsv/, 'ArrayStore uses newSVsv to copy value');
};

# Test 4: ArrayLength visitor
subtest 'ArrayLength generates av_len' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $array = Chalk::IR::Node::NewArray->new(inputs => []);
    $graph->add_node($array);

    my $length = Chalk::IR::Node::ArrayLength->new(
        inputs => [],
        array => $array,
    );
    $graph->add_node($length);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit array first
    $xs->visit($array);

    my $xs_node = $xs->visit($length);
    ok(defined $xs_node, 'ArrayLength visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'ArrayLength emits code');
    like($code, qr/av_len/, 'ArrayLength uses av_len');
    like($code, qr/\+\s*1/, 'ArrayLength adds 1 to av_len result');
};

done_testing();
