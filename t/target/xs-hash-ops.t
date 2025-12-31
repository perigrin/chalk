# ABOUTME: Test XS visitors for hash operations (NewHash, HashLoad, HashStore)
# ABOUTME: Verifies correct HV* operations in generated XS code
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::Target::XS;
use Chalk::IR::Graph;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::HashLoad;
use Chalk::IR::Node::HashStore;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::String;

# Test 1: NewHash visitor
subtest 'NewHash generates newHV()' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $new_hash = Chalk::IR::Node::NewHash->new(inputs => []);
    $graph->add_node($new_hash);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );
    my $xs_node = $xs->visit($new_hash);

    ok(defined $xs_node, 'NewHash visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'NewHash emits code');
    like($code, qr/HV\s*\*/, 'NewHash declares HV* type');
    like($code, qr/newHV\s*\(\s*\)/, 'NewHash uses newHV()');
};

# Test 2: HashLoad visitor
subtest 'HashLoad generates hv_fetch' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create hash and key nodes
    my $hash = Chalk::IR::Node::NewHash->new(inputs => []);
    $graph->add_node($hash);

    my $key = Chalk::IR::Node::Constant->new(
        value => 'foo',
        type  => Chalk::IR::Type::String->new(),
    );
    $graph->add_node($key);

    my $load = Chalk::IR::Node::HashLoad->new(
        inputs  => [],
        hash_id => $hash->id,
        key_id  => $key->id,
    );
    $graph->add_node($load);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit hash first to bind it
    $xs->visit($hash);
    # Visit key to bind it
    $xs->visit($key);

    my $xs_node = $xs->visit($load);
    ok(defined $xs_node, 'HashLoad visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'HashLoad emits code');
    like($code, qr/hv_fetch/, 'HashLoad uses hv_fetch');
    like($code, qr/PL_sv_undef/, 'HashLoad handles missing key with undef fallback');
    like($code, qr/SvUTF8/, 'HashLoad checks UTF-8 flag for key');
};

# Test 3: HashStore visitor
subtest 'HashStore generates hv_store' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $hash = Chalk::IR::Node::NewHash->new(inputs => []);
    $graph->add_node($hash);

    my $key = Chalk::IR::Node::Constant->new(
        value => 'bar',
        type  => Chalk::IR::Type::String->new(),
    );
    $graph->add_node($key);

    my $value = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );
    $graph->add_node($value);

    my $store = Chalk::IR::Node::HashStore->new(
        inputs   => [],
        hash_id  => $hash->id,
        key_id   => $key->id,
        value_id => $value->id,
    );
    $graph->add_node($store);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    # Visit dependencies first
    $xs->visit($hash);
    $xs->visit($key);
    $xs->visit($value);

    my $xs_node = $xs->visit($store);
    ok(defined $xs_node, 'HashStore visitor returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'HashStore emits code');
    like($code, qr/hv_store/, 'HashStore uses hv_store');
    like($code, qr/newSVsv/, 'HashStore uses newSVsv to copy value');
    like($code, qr/SvUTF8/, 'HashStore checks UTF-8 flag for key');
};

done_testing();
