# ABOUTME: Tests for field_index in FieldLoad and FieldStore nodes
# ABOUTME: Verifies field_index support for XS ObjectFIELDS access

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Node::FieldLoad;
use Chalk::IR::Node::FieldStore;

subtest 'FieldLoad with field_index' => sub {
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs      => [1, 2],
        object_id   => 1,
        field_id    => 2,
        field_index => 0,
    );

    ok(defined $load, 'FieldLoad created');
    ok($load->can('field_index'), 'FieldLoad has field_index method');
    is($load->field_index, 0, 'field_index value correct');
};

subtest 'FieldLoad to_hash includes field_index' => sub {
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs      => [1, 2],
        object_id   => 1,
        field_id    => 2,
        field_index => 3,
    );

    my $hash = $load->to_hash;
    ok(exists $hash->{attributes}{field_index}, 'to_hash has field_index');
    is($hash->{attributes}{field_index}, 3, 'field_index value correct in to_hash');
};

subtest 'FieldLoad without field_index' => sub {
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs    => [1, 2],
        object_id => 1,
        field_id  => 2,
    );

    ok(!defined $load->field_index, 'field_index is undef by default');

    my $hash = $load->to_hash;
    ok(!exists $hash->{attributes}{field_index}, 'to_hash omits undefined field_index');
};

subtest 'FieldStore with field_index' => sub {
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs      => [1, 2, 3],
        object_id   => 1,
        field_id    => 2,
        value_id    => 3,
        field_index => 1,
    );

    ok(defined $store, 'FieldStore created');
    ok($store->can('field_index'), 'FieldStore has field_index method');
    is($store->field_index, 1, 'field_index value correct');
};

subtest 'FieldStore to_hash includes field_index' => sub {
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs      => [1, 2, 3],
        object_id   => 1,
        field_id    => 2,
        value_id    => 3,
        field_index => 2,
    );

    my $hash = $store->to_hash;
    ok(exists $hash->{attributes}{field_index}, 'to_hash has field_index');
    is($hash->{attributes}{field_index}, 2, 'field_index value correct in to_hash');
};

subtest 'FieldStore without field_index' => sub {
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs   => [1, 2, 3],
        object_id => 1,
        field_id  => 2,
        value_id  => 3,
    );

    ok(!defined $store->field_index, 'field_index is undef by default');

    my $hash = $store->to_hash;
    ok(!exists $hash->{attributes}{field_index}, 'to_hash omits undefined field_index');
};

done_testing();
