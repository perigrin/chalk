use 5.42.0;
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::HashStore;
use Chalk::IR::Node::HashLoad;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test 1: NewHash allocates a heap ID
my $graph1 = Chalk::IR::Graph->new();
my $new_hash = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $return1 = Chalk::IR::Node::Return->new(id => 'node_2', inputs => ['node_1'], value_id => 'node_1', control_id => 'node_1');
$graph1->add_node($new_hash);
$graph1->add_node($return1);

my $interp1 = Chalk::Interpreter::CEKDataflow->new(graph => $graph1);
my $result1 = $interp1->execute();
is($result1, 1, "NewHash should allocate heap ID 1");

# Test 2: HashStore stores a value and returns heap ID
my $graph2 = Chalk::IR::Graph->new();
my $new_hash2 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $key = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 'name', type => 'string');
my $value = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 'Alice', type => 'string');
my $store = Chalk::IR::Node::HashStore->new(
    id => 'node_4',
    inputs => ['node_1', 'node_2', 'node_3'],
    hash_id => 'node_1',
    key_id => 'node_2',
    value_id => 'node_3'
);
my $return2 = Chalk::IR::Node::Return->new(id => 'node_5', inputs => ['node_4'], value_id => 'node_4', control_id => 'node_4');
$graph2->add_node($new_hash2);
$graph2->add_node($key);
$graph2->add_node($value);
$graph2->add_node($store);
$graph2->add_node($return2);

my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph2);
my $result2 = $interp2->execute();
is($result2, 1, "HashStore should return the heap ID");

# Test 3: HashLoad retrieves stored value
my $graph3 = Chalk::IR::Graph->new();
my $new_hash3 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $key3 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 'age', type => 'string');
my $value3 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 42, type => 'int');
my $store3 = Chalk::IR::Node::HashStore->new(
    id => 'node_4',
    inputs => ['node_1', 'node_2', 'node_3'],
    hash_id => 'node_1',
    key_id => 'node_2',
    value_id => 'node_3'
);
my $load3 = Chalk::IR::Node::HashLoad->new(
    id => 'node_5',
    inputs => ['node_4', 'node_2'],
    hash_id => 'node_4',
    key_id => 'node_2'
);
my $return3 = Chalk::IR::Node::Return->new(id => 'node_6', inputs => ['node_5'], value_id => 'node_5', control_id => 'node_5');
$graph3->add_node($new_hash3);
$graph3->add_node($key3);
$graph3->add_node($value3);
$graph3->add_node($store3);
$graph3->add_node($load3);
$graph3->add_node($return3);

my $interp3 = Chalk::Interpreter::CEKDataflow->new(graph => $graph3);
my $result3 = $interp3->execute();
is($result3, 42, "HashLoad should retrieve stored value");

# Test 4: Hash with multiple keys
my $graph4 = Chalk::IR::Graph->new();
my $new_hash4 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $key4a = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 'x', type => 'string');
my $val4a = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 10, type => 'int');
my $key4b = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 'y', type => 'string');
my $val4b = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 20, type => 'int');

my $store4a = Chalk::IR::Node::HashStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_2', 'node_3'],
    hash_id => 'node_1',
    key_id => 'node_2',
    value_id => 'node_3'
);
my $store4b = Chalk::IR::Node::HashStore->new(
    id => 'node_7',
    inputs => ['node_6', 'node_4', 'node_5'],
    hash_id => 'node_6',
    key_id => 'node_4',
    value_id => 'node_5'
);
my $load4 = Chalk::IR::Node::HashLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_4'],
    hash_id => 'node_7',
    key_id => 'node_4'
);
my $return4 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph4->add_node($new_hash4);
$graph4->add_node($key4a);
$graph4->add_node($val4a);
$graph4->add_node($key4b);
$graph4->add_node($val4b);
$graph4->add_node($store4a);
$graph4->add_node($store4b);
$graph4->add_node($load4);
$graph4->add_node($return4);

my $interp4 = Chalk::Interpreter::CEKDataflow->new(graph => $graph4);
my $result4 = $interp4->execute();
is($result4, 20, "Should load value from key 'y'");

# Test 5: Load earlier key from multi-key hash
my $graph5 = Chalk::IR::Graph->new();
my $new_hash5 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $key5a = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 'x', type => 'string');
my $val5a = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 10, type => 'int');
my $key5b = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 'y', type => 'string');
my $val5b = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 20, type => 'int');

my $store5a = Chalk::IR::Node::HashStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_2', 'node_3'],
    hash_id => 'node_1',
    key_id => 'node_2',
    value_id => 'node_3'
);
my $store5b = Chalk::IR::Node::HashStore->new(
    id => 'node_7',
    inputs => ['node_6', 'node_4', 'node_5'],
    hash_id => 'node_6',
    key_id => 'node_4',
    value_id => 'node_5'
);
my $load5 = Chalk::IR::Node::HashLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_2'],
    hash_id => 'node_7',
    key_id => 'node_2'
);
my $return5 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph5->add_node($new_hash5);
$graph5->add_node($key5a);
$graph5->add_node($val5a);
$graph5->add_node($key5b);
$graph5->add_node($val5b);
$graph5->add_node($store5a);
$graph5->add_node($store5b);
$graph5->add_node($load5);
$graph5->add_node($return5);

my $interp5 = Chalk::Interpreter::CEKDataflow->new(graph => $graph5);
my $result5 = $interp5->execute();
is($result5, 10, "Should load value from key 'x'");

# Test 6: Multiple hashes are isolated
my $graph6 = Chalk::IR::Graph->new();
my $hash1 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $hash2 = Chalk::IR::Node::NewHash->new(id => 'node_2', inputs => []);
my $key_6 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 'name', type => 'string');
my $val1 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 'Alice', type => 'string');
my $val2 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 'Bob', type => 'string');

my $store6a = Chalk::IR::Node::HashStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_3', 'node_4'],
    hash_id => 'node_1',
    key_id => 'node_3',
    value_id => 'node_4'
);
my $store6b = Chalk::IR::Node::HashStore->new(
    id => 'node_7',
    inputs => ['node_2', 'node_3', 'node_5'],
    hash_id => 'node_2',
    key_id => 'node_3',
    value_id => 'node_5'
);
my $load6a = Chalk::IR::Node::HashLoad->new(
    id => 'node_8',
    inputs => ['node_6', 'node_3'],
    hash_id => 'node_6',
    key_id => 'node_3'
);
my $return6 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph6->add_node($hash1);
$graph6->add_node($hash2);
$graph6->add_node($key_6);
$graph6->add_node($val1);
$graph6->add_node($val2);
$graph6->add_node($store6a);
$graph6->add_node($store6b);
$graph6->add_node($load6a);
$graph6->add_node($return6);

my $interp6 = Chalk::Interpreter::CEKDataflow->new(graph => $graph6);
my $result6 = $interp6->execute();
is($result6, 'Alice', "Hash 1 should have value 'Alice' at key 'name'");

# Test 7: Load from second hash
my $graph7 = Chalk::IR::Graph->new();
my $hash1_7 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $hash2_7 = Chalk::IR::Node::NewHash->new(id => 'node_2', inputs => []);
my $key_7 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 'name', type => 'string');
my $val1_7 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 'Alice', type => 'string');
my $val2_7 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 'Bob', type => 'string');

my $store7a = Chalk::IR::Node::HashStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_3', 'node_4'],
    hash_id => 'node_1',
    key_id => 'node_3',
    value_id => 'node_4'
);
my $store7b = Chalk::IR::Node::HashStore->new(
    id => 'node_7',
    inputs => ['node_2', 'node_3', 'node_5'],
    hash_id => 'node_2',
    key_id => 'node_3',
    value_id => 'node_5'
);
my $load7b = Chalk::IR::Node::HashLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_3'],
    hash_id => 'node_7',
    key_id => 'node_3'
);
my $return7 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph7->add_node($hash1_7);
$graph7->add_node($hash2_7);
$graph7->add_node($key_7);
$graph7->add_node($val1_7);
$graph7->add_node($val2_7);
$graph7->add_node($store7a);
$graph7->add_node($store7b);
$graph7->add_node($load7b);
$graph7->add_node($return7);

my $interp7 = Chalk::Interpreter::CEKDataflow->new(graph => $graph7);
my $result7 = $interp7->execute();
is($result7, 'Bob', "Hash 2 should have value 'Bob' at key 'name'");

# Test 8: HashLoad on uninitialized key returns undef
my $graph8 = Chalk::IR::Graph->new();
my $new_hash8 = Chalk::IR::Node::NewHash->new(id => 'node_1', inputs => []);
my $key8 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 'missing', type => 'string');
my $load8 = Chalk::IR::Node::HashLoad->new(
    id => 'node_3',
    inputs => ['node_1', 'node_2'],
    hash_id => 'node_1',
    key_id => 'node_2'
);
my $return8 = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_3'], value_id => 'node_3', control_id => 'node_3');
$graph8->add_node($new_hash8);
$graph8->add_node($key8);
$graph8->add_node($load8);
$graph8->add_node($return8);

my $interp8 = Chalk::Interpreter::CEKDataflow->new(graph => $graph8);
my $result8 = $interp8->execute();
is($result8, undef, "HashLoad on uninitialized key should return undef");
