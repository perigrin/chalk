# ABOUTME: Tests for XS field access via FieldLoad and FieldStore visitors
# ABOUTME: Verifies generation of ObjectFIELDS array access in XS code

use 5.42.0;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::FieldLoad;
use Chalk::IR::Node::FieldStore;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::String;
use Chalk::Target::XS;

subtest 'FieldLoad generates ObjectFIELDS read' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a simple graph: load field at index 0
    my $const_obj = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $const_field = Chalk::IR::Node::Constant->new(
        value => 'x',
        type  => Chalk::IR::Type::String->constant('x'),
    );

    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs      => [$const_obj->id, $const_field->id],
        object_id   => $const_obj->id,
        field_id    => $const_field->id,
        field_index => 0,
    );

    $graph->add_node($const_obj);
    $graph->add_node($const_field);
    $graph->add_node($load);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    my $xs_node = $xs->visit($load);
    ok(defined $xs_node, 'FieldLoad visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'FieldLoad emits code');
    like($code, qr/SV\*/, 'FieldLoad declares SV* variable');
    like($code, qr/ObjectFIELDS\s*\(\s*self\s*\)\s*\[\s*0\s*\]/, 'FieldLoad uses ObjectFIELDS[0]');
};

subtest 'FieldLoad with different index' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_obj = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $const_field = Chalk::IR::Node::Constant->new(
        value => 'y',
        type  => Chalk::IR::Type::String->constant('y'),
    );

    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs      => [$const_obj->id, $const_field->id],
        object_id   => $const_obj->id,
        field_id    => $const_field->id,
        field_index => 2,
    );

    $graph->add_node($const_obj);
    $graph->add_node($const_field);
    $graph->add_node($load);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    my $xs_node = $xs->visit($load);
    my $code = $xs_node->emit();
    like($code, qr/ObjectFIELDS\s*\(\s*self\s*\)\s*\[\s*2\s*\]/, 'FieldLoad uses ObjectFIELDS[2]');
};

subtest 'FieldStore generates ObjectFIELDS write' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a simple graph: store value to field at index 0
    my $const_obj = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $const_field = Chalk::IR::Node::Constant->new(
        value => 'x',
        type  => Chalk::IR::Type::String->constant('x'),
    );
    my $const_value = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    my $store = Chalk::IR::Node::FieldStore->new(
        inputs      => [$const_obj->id, $const_field->id, $const_value->id],
        object_id   => $const_obj->id,
        field_id    => $const_field->id,
        value_id    => $const_value->id,
        field_index => 0,
    );

    $graph->add_node($const_obj);
    $graph->add_node($const_field);
    $graph->add_node($const_value);
    $graph->add_node($store);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # First visit the value to allocate its temp
    $xs->visit($const_value);

    my $xs_node = $xs->visit($store);
    ok(defined $xs_node, 'FieldStore visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'FieldStore emits code');
    like($code, qr/ObjectFIELDS\s*\(\s*self\s*\)\s*\[\s*0\s*\]/, 'FieldStore uses ObjectFIELDS[0]');
    like($code, qr/SvREFCNT_dec/, 'FieldStore decrefs old value to prevent memory leak');
    like($code, qr/newSVsv/, 'FieldStore uses newSVsv to copy value');
};

subtest 'FieldStore with different index' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_obj = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $const_field = Chalk::IR::Node::Constant->new(
        value => 'count',
        type  => Chalk::IR::Type::String->constant('count'),
    );
    my $const_value = Chalk::IR::Node::Constant->new(
        value => 99,
        type  => Chalk::IR::Type::Integer->constant(99),
    );

    my $store = Chalk::IR::Node::FieldStore->new(
        inputs      => [$const_obj->id, $const_field->id, $const_value->id],
        object_id   => $const_obj->id,
        field_id    => $const_field->id,
        value_id    => $const_value->id,
        field_index => 3,
    );

    $graph->add_node($const_obj);
    $graph->add_node($const_field);
    $graph->add_node($const_value);
    $graph->add_node($store);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit the value first
    $xs->visit($const_value);

    my $xs_node = $xs->visit($store);
    my $code = $xs_node->emit();
    like($code, qr/ObjectFIELDS\s*\(\s*self\s*\)\s*\[\s*3\s*\]/, 'FieldStore uses ObjectFIELDS[3]');
};

done_testing();
