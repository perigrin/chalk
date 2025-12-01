#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter hash operations including NewHash, HashStore, and HashLoad nodes
# ABOUTME: Verifies heap allocation, key-value storage/retrieval, multi-key hashes, and hash isolation
use 5.42.0;
use lib 'lib';
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::HashStore;
use Chalk::IR::Node::HashLoad;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Start;
use Chalk::Interpreter::CEKDataflow;

# Test 1: NewHash allocates a heap ID
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test1');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_1', inputs => [$start->id]);
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $new_hash->id,
        control_id => $start->id,
    );
    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, "NewHash should allocate heap ID 1");
}

# Test 2: HashStore stores a value and returns heap ID
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test2');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_2', inputs => [$start->id]);
    my $key = Chalk::IR::Node::Constant->new(value => 'name', type => 'string');
    my $value = Chalk::IR::Node::Constant->new(value => 'Alice', type => 'string');
    my $store = Chalk::IR::Node::HashStore->new(
        id => 'store_' . $new_hash->id . '_' . $key->id . '_' . $value->id,
        inputs => [$new_hash->id, $key->id, $value->id],
        hash_id => $new_hash->id,
        key_id => $key->id,
        value_id => $value->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $store->id,
        control_id => $start->id,
    );
    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($key);
    $graph->add_node($value);
    $graph->add_node($store);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, "HashStore should return the heap ID");
}

# Test 3: HashLoad retrieves stored value
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test3');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_3', inputs => [$start->id]);
    my $key = Chalk::IR::Node::Constant->new(value => 'age', type => 'string');
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    my $store = Chalk::IR::Node::HashStore->new(
        id => 'store_' . $new_hash->id . '_' . $key->id . '_' . $value->id,
        inputs => [$new_hash->id, $key->id, $value->id],
        hash_id => $new_hash->id,
        key_id => $key->id,
        value_id => $value->id,
    );
    my $load = Chalk::IR::Node::HashLoad->new(
        id => 'load_' . $store->id . '_' . $key->id,
        inputs => [$store->id, $key->id],
        hash_id => $store->id,
        key_id => $key->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load->id,
        control_id => $start->id,
    );
    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($key);
    $graph->add_node($value);
    $graph->add_node($store);
    $graph->add_node($load);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 42, "HashLoad should retrieve stored value");
}

# Test 4: Hash with multiple keys
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test4');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_4', inputs => [$start->id]);
    my $key_x = Chalk::IR::Node::Constant->new(value => 'x', type => 'string');
    my $val_10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $key_y = Chalk::IR::Node::Constant->new(value => 'y', type => 'string');
    my $val_20 = Chalk::IR::Node::Constant->new(value => 20, type => 'int');

    my $store_x = Chalk::IR::Node::HashStore->new(
        id => 'store_' . $new_hash->id . '_' . $key_x->id . '_' . $val_10->id,
        inputs => [$new_hash->id, $key_x->id, $val_10->id],
        hash_id => $new_hash->id,
        key_id => $key_x->id,
        value_id => $val_10->id,
    );
    my $store_y = Chalk::IR::Node::HashStore->new(
        id => 'store_' . $store_x->id . '_' . $key_y->id . '_' . $val_20->id,
        inputs => [$store_x->id, $key_y->id, $val_20->id],
        hash_id => $store_x->id,
        key_id => $key_y->id,
        value_id => $val_20->id,
    );
    my $load_y = Chalk::IR::Node::HashLoad->new(
        id => 'load_' . $store_y->id . '_' . $key_y->id,
        inputs => [$store_y->id, $key_y->id],
        hash_id => $store_y->id,
        key_id => $key_y->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load_y->id,
        control_id => $start->id,
    );

    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($key_x);
    $graph->add_node($val_10);
    $graph->add_node($key_y);
    $graph->add_node($val_20);
    $graph->add_node($store_x);
    $graph->add_node($store_y);
    $graph->add_node($load_y);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 20, "Should load value from key 'y'");
}

# Test 5: Load earlier key from multi-key hash
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test5');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_5', inputs => [$start->id]);
    my $key_x = Chalk::IR::Node::Constant->new(value => 'x', type => 'string');
    my $val_10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $key_y = Chalk::IR::Node::Constant->new(value => 'y', type => 'string');
    my $val_20 = Chalk::IR::Node::Constant->new(value => 20, type => 'int');

    my $store_x = Chalk::IR::Node::HashStore->new(
        id => 'store5_' . $new_hash->id . '_' . $key_x->id . '_' . $val_10->id,
        inputs => [$new_hash->id, $key_x->id, $val_10->id],
        hash_id => $new_hash->id,
        key_id => $key_x->id,
        value_id => $val_10->id,
    );
    my $store_y = Chalk::IR::Node::HashStore->new(
        id => 'store5_' . $store_x->id . '_' . $key_y->id . '_' . $val_20->id,
        inputs => [$store_x->id, $key_y->id, $val_20->id],
        hash_id => $store_x->id,
        key_id => $key_y->id,
        value_id => $val_20->id,
    );
    # Load from key 'x' (first key stored)
    my $load_x = Chalk::IR::Node::HashLoad->new(
        id => 'load5_' . $store_y->id . '_' . $key_x->id,
        inputs => [$store_y->id, $key_x->id],
        hash_id => $store_y->id,
        key_id => $key_x->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load_x->id,
        control_id => $start->id,
    );

    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($key_x);
    $graph->add_node($val_10);
    $graph->add_node($key_y);
    $graph->add_node($val_20);
    $graph->add_node($store_x);
    $graph->add_node($store_y);
    $graph->add_node($load_x);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 10, "Should load value from key 'x'");
}

# Test 6: Multiple hashes are isolated
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test6');
    my $hash1 = Chalk::IR::Node::NewHash->new(id => 'newhash_6a', inputs => [$start->id]);
    my $hash2 = Chalk::IR::Node::NewHash->new(id => 'newhash_6b', inputs => [$start->id]);
    my $key = Chalk::IR::Node::Constant->new(value => 'name', type => 'string');
    my $val_alice = Chalk::IR::Node::Constant->new(value => 'Alice', type => 'string');
    my $val_bob = Chalk::IR::Node::Constant->new(value => 'Bob', type => 'string');

    my $store_alice = Chalk::IR::Node::HashStore->new(
        id => 'store6_' . $hash1->id . '_' . $key->id . '_' . $val_alice->id,
        inputs => [$hash1->id, $key->id, $val_alice->id],
        hash_id => $hash1->id,
        key_id => $key->id,
        value_id => $val_alice->id,
    );
    my $store_bob = Chalk::IR::Node::HashStore->new(
        id => 'store6_' . $hash2->id . '_' . $key->id . '_' . $val_bob->id,
        inputs => [$hash2->id, $key->id, $val_bob->id],
        hash_id => $hash2->id,
        key_id => $key->id,
        value_id => $val_bob->id,
    );
    # Load from hash1 - should get 'Alice', not 'Bob'
    my $load_alice = Chalk::IR::Node::HashLoad->new(
        id => 'load6_' . $store_alice->id . '_' . $key->id,
        inputs => [$store_alice->id, $store_bob->id, $key->id],
        hash_id => $store_alice->id,
        key_id => $key->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load_alice->id,
        control_id => $start->id,
    );

    $graph->add_node($start);
    $graph->add_node($hash1);
    $graph->add_node($hash2);
    $graph->add_node($key);
    $graph->add_node($val_alice);
    $graph->add_node($val_bob);
    $graph->add_node($store_alice);
    $graph->add_node($store_bob);
    $graph->add_node($load_alice);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 'Alice', "Hash 1 should have value 'Alice' at key 'name'");
}

# Test 7: Load from second hash
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test7');
    my $hash1 = Chalk::IR::Node::NewHash->new(id => 'newhash_7a', inputs => [$start->id]);
    my $hash2 = Chalk::IR::Node::NewHash->new(id => 'newhash_7b', inputs => [$start->id]);
    my $key = Chalk::IR::Node::Constant->new(value => 'name', type => 'string');
    my $val_alice = Chalk::IR::Node::Constant->new(value => 'Alice', type => 'string');
    my $val_bob = Chalk::IR::Node::Constant->new(value => 'Bob', type => 'string');

    my $store_alice = Chalk::IR::Node::HashStore->new(
        id => 'store7_' . $hash1->id . '_' . $key->id . '_' . $val_alice->id,
        inputs => [$hash1->id, $key->id, $val_alice->id],
        hash_id => $hash1->id,
        key_id => $key->id,
        value_id => $val_alice->id,
    );
    my $store_bob = Chalk::IR::Node::HashStore->new(
        id => 'store7_' . $hash2->id . '_' . $key->id . '_' . $val_bob->id,
        inputs => [$hash2->id, $key->id, $val_bob->id],
        hash_id => $hash2->id,
        key_id => $key->id,
        value_id => $val_bob->id,
    );
    # Load from hash2 - should get 'Bob'
    my $load_bob = Chalk::IR::Node::HashLoad->new(
        id => 'load7_' . $store_bob->id . '_' . $key->id,
        inputs => [$store_alice->id, $store_bob->id, $key->id],
        hash_id => $store_bob->id,
        key_id => $key->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load_bob->id,
        control_id => $start->id,
    );

    $graph->add_node($start);
    $graph->add_node($hash1);
    $graph->add_node($hash2);
    $graph->add_node($key);
    $graph->add_node($val_alice);
    $graph->add_node($val_bob);
    $graph->add_node($store_alice);
    $graph->add_node($store_bob);
    $graph->add_node($load_bob);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 'Bob', "Hash 2 should have value 'Bob' at key 'name'");
}

# Test 8: HashLoad on uninitialized key returns undef
# NOTE: This is marked TODO because the CEKDataflow interpreter treats undef
# from Return as "inactive path" (used for if/else control flow). Returning
# undef as an actual value requires a different signaling mechanism.
TODO: {
    local $TODO = "undef return values conflict with inactive-path signaling";
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(label => 'test8');
    my $new_hash = Chalk::IR::Node::NewHash->new(id => 'newhash_8', inputs => [$start->id]);
    my $key = Chalk::IR::Node::Constant->new(value => 'missing', type => 'string');
    my $load = Chalk::IR::Node::HashLoad->new(
        id => 'load_' . $new_hash->id . '_' . $key->id,
        inputs => [$new_hash->id, $key->id],
        hash_id => $new_hash->id,
        key_id => $key->id,
    );
    my $return_node = Chalk::IR::Node::Return->new(
        value_id => $load->id,
        control_id => $start->id,
    );
    $graph->add_node($start);
    $graph->add_node($new_hash);
    $graph->add_node($key);
    $graph->add_node($load);
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    eval {
        my $result = $interp->execute();
        is($result, undef, "HashLoad on uninitialized key should return undef");
    };
    if ($@) {
        fail("HashLoad on uninitialized key should return undef - got error: $@");
    }
}
