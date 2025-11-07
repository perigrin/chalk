use 5.42.0;
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::ArrayStore;
use Chalk::IR::Node::ArrayLoad;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test 1: NewArray allocates a heap ID
my $graph1 = Chalk::IR::Graph->new();
my $new_array = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $return1 = Chalk::IR::Node::Return->new(id => 'node_2', inputs => ['node_1'], value_id => 'node_1', control_id => 'node_1');
$graph1->add_node($new_array);
$graph1->add_node($return1);

my $interp1 = Chalk::Interpreter::CEKDataflow->new(graph => $graph1);
my $result1 = $interp1->execute();
is($result1, 1, "NewArray should allocate heap ID 1");

# Test 2: ArrayStore stores a value and returns heap ID
my $graph2 = Chalk::IR::Graph->new();
my $new_array2 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $index = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 0, type => 'int');
my $value = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 42, type => 'int');
my $store = Chalk::IR::Node::ArrayStore->new(
    id => 'node_4',
    inputs => ['node_1', 'node_2', 'node_3'],
    array_id => 'node_1',
    index_id => 'node_2',
    value_id => 'node_3'
);
my $return2 = Chalk::IR::Node::Return->new(id => 'node_5', inputs => ['node_4'], value_id => 'node_4', control_id => 'node_4');
$graph2->add_node($new_array2);
$graph2->add_node($index);
$graph2->add_node($value);
$graph2->add_node($store);
$graph2->add_node($return2);

my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph2);
my $result2 = $interp2->execute();
is($result2, 1, "ArrayStore should return the heap ID");

# Test 3: ArrayLoad retrieves stored value
my $graph3 = Chalk::IR::Graph->new();
my $new_array3 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $index3 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 0, type => 'int');
my $value3 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 99, type => 'int');
my $store3 = Chalk::IR::Node::ArrayStore->new(
    id => 'node_4',
    inputs => ['node_1', 'node_2', 'node_3'],
    array_id => 'node_1',
    index_id => 'node_2',
    value_id => 'node_3'
);
my $load3 = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_5',
    inputs => ['node_4', 'node_2'],
    array_id => 'node_4',
    index_id => 'node_2'
);
my $return3 = Chalk::IR::Node::Return->new(id => 'node_6', inputs => ['node_5'], value_id => 'node_5', control_id => 'node_5');
$graph3->add_node($new_array3);
$graph3->add_node($index3);
$graph3->add_node($value3);
$graph3->add_node($store3);
$graph3->add_node($load3);
$graph3->add_node($return3);

my $interp3 = Chalk::Interpreter::CEKDataflow->new(graph => $graph3);
my $result3 = $interp3->execute();
is($result3, 99, "ArrayLoad should retrieve stored value");

# Test 4: Array with multiple indices
my $graph4 = Chalk::IR::Graph->new();
my $new_array4 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $idx0 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 0, type => 'int');
my $val10 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 10, type => 'int');
my $idx1 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 1, type => 'int');
my $val20 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 20, type => 'int');

my $store4a = Chalk::IR::Node::ArrayStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_2', 'node_3'],
    array_id => 'node_1',
    index_id => 'node_2',
    value_id => 'node_3'
);
my $store4b = Chalk::IR::Node::ArrayStore->new(
    id => 'node_7',
    inputs => ['node_6', 'node_4', 'node_5'],
    array_id => 'node_6',
    index_id => 'node_4',
    value_id => 'node_5'
);
my $load4 = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_4'],
    array_id => 'node_7',
    index_id => 'node_4'
);
my $return4 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph4->add_node($new_array4);
$graph4->add_node($idx0);
$graph4->add_node($val10);
$graph4->add_node($idx1);
$graph4->add_node($val20);
$graph4->add_node($store4a);
$graph4->add_node($store4b);
$graph4->add_node($load4);
$graph4->add_node($return4);

my $interp4 = Chalk::Interpreter::CEKDataflow->new(graph => $graph4);
my $result4 = $interp4->execute();
is($result4, 20, "Should load value from index 1");

# Test 5: Load earlier index from multi-index array
my $graph5 = Chalk::IR::Graph->new();
my $new_array5 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $idx0_5 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 0, type => 'int');
my $val10_5 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 10, type => 'int');
my $idx1_5 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 1, type => 'int');
my $val20_5 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 20, type => 'int');

my $store5a = Chalk::IR::Node::ArrayStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_2', 'node_3'],
    array_id => 'node_1',
    index_id => 'node_2',
    value_id => 'node_3'
);
my $store5b = Chalk::IR::Node::ArrayStore->new(
    id => 'node_7',
    inputs => ['node_6', 'node_4', 'node_5'],
    array_id => 'node_6',
    index_id => 'node_4',
    value_id => 'node_5'
);
my $load5 = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_2'],
    array_id => 'node_7',
    index_id => 'node_2'
);
my $return5 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph5->add_node($new_array5);
$graph5->add_node($idx0_5);
$graph5->add_node($val10_5);
$graph5->add_node($idx1_5);
$graph5->add_node($val20_5);
$graph5->add_node($store5a);
$graph5->add_node($store5b);
$graph5->add_node($load5);
$graph5->add_node($return5);

my $interp5 = Chalk::Interpreter::CEKDataflow->new(graph => $graph5);
my $result5 = $interp5->execute();
is($result5, 10, "Should load value from index 0");

# Test 6: Multiple arrays are isolated
my $graph6 = Chalk::IR::Graph->new();
my $array1 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $array2 = Chalk::IR::Node::NewArray->new(id => 'node_2', inputs => []);
my $idx_6 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 0, type => 'int');
my $val1 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 100, type => 'int');
my $val2 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 200, type => 'int');

my $store6a = Chalk::IR::Node::ArrayStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_3', 'node_4'],
    array_id => 'node_1',
    index_id => 'node_3',
    value_id => 'node_4'
);
my $store6b = Chalk::IR::Node::ArrayStore->new(
    id => 'node_7',
    inputs => ['node_2', 'node_3', 'node_5'],
    array_id => 'node_2',
    index_id => 'node_3',
    value_id => 'node_5'
);
my $load6a = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_8',
    inputs => ['node_6', 'node_3'],
    array_id => 'node_6',
    index_id => 'node_3'
);
my $return6 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph6->add_node($array1);
$graph6->add_node($array2);
$graph6->add_node($idx_6);
$graph6->add_node($val1);
$graph6->add_node($val2);
$graph6->add_node($store6a);
$graph6->add_node($store6b);
$graph6->add_node($load6a);
$graph6->add_node($return6);

my $interp6 = Chalk::Interpreter::CEKDataflow->new(graph => $graph6);
my $result6 = $interp6->execute();
is($result6, 100, "Array 1 should have value 100 at index 0");

# Test 7: Load from second array
my $graph7 = Chalk::IR::Graph->new();
my $array1_7 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $array2_7 = Chalk::IR::Node::NewArray->new(id => 'node_2', inputs => []);
my $idx_7 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 0, type => 'int');
my $val1_7 = Chalk::IR::Node::Constant->new(id => 'node_4', inputs => [], value => 100, type => 'int');
my $val2_7 = Chalk::IR::Node::Constant->new(id => 'node_5', inputs => [], value => 200, type => 'int');

my $store7a = Chalk::IR::Node::ArrayStore->new(
    id => 'node_6',
    inputs => ['node_1', 'node_3', 'node_4'],
    array_id => 'node_1',
    index_id => 'node_3',
    value_id => 'node_4'
);
my $store7b = Chalk::IR::Node::ArrayStore->new(
    id => 'node_7',
    inputs => ['node_2', 'node_3', 'node_5'],
    array_id => 'node_2',
    index_id => 'node_3',
    value_id => 'node_5'
);
my $load7b = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_8',
    inputs => ['node_7', 'node_3'],
    array_id => 'node_7',
    index_id => 'node_3'
);
my $return7 = Chalk::IR::Node::Return->new(id => 'node_9', inputs => ['node_8'], value_id => 'node_8', control_id => 'node_8');

$graph7->add_node($array1_7);
$graph7->add_node($array2_7);
$graph7->add_node($idx_7);
$graph7->add_node($val1_7);
$graph7->add_node($val2_7);
$graph7->add_node($store7a);
$graph7->add_node($store7b);
$graph7->add_node($load7b);
$graph7->add_node($return7);

my $interp7 = Chalk::Interpreter::CEKDataflow->new(graph => $graph7);
my $result7 = $interp7->execute();
is($result7, 200, "Array 2 should have value 200 at index 0");

# Test 8: ArrayLoad on uninitialized index returns undef
my $graph8 = Chalk::IR::Graph->new();
my $new_array8 = Chalk::IR::Node::NewArray->new(id => 'node_1', inputs => []);
my $idx8 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 99, type => 'int');
my $load8 = Chalk::IR::Node::ArrayLoad->new(
    id => 'node_3',
    inputs => ['node_1', 'node_2'],
    array_id => 'node_1',
    index_id => 'node_2'
);
my $return8 = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_3'], value_id => 'node_3', control_id => 'node_3');
$graph8->add_node($new_array8);
$graph8->add_node($idx8);
$graph8->add_node($load8);
$graph8->add_node($return8);

my $interp8 = Chalk::Interpreter::CEKDataflow->new(graph => $graph8);
my $result8 = $interp8->execute();
is($result8, undef, "ArrayLoad on uninitialized index should return undef");
