use 5.42.0;
use Test::More tests => 12;
use Chalk::Interpreter::Environment;

# Test 1: Heap ID allocation returns unique IDs
my $env = Chalk::Interpreter::Environment->new();
my $id1 = $env->allocate_heap_id();
my $id2 = $env->allocate_heap_id();
my $id3 = $env->allocate_heap_id();

isnt($id1, $id2, "First and second heap IDs should be different");
isnt($id2, $id3, "Second and third heap IDs should be different");
isnt($id1, $id3, "First and third heap IDs should be different");

# Test 2: Heap IDs start at 1 and increment
is($id1, 1, "First heap ID should be 1");
is($id2, 2, "Second heap ID should be 2");
is($id3, 3, "Third heap ID should be 3");

# Test 3: lookup_heap on newly allocated heap returns undef
my $env2 = Chalk::Interpreter::Environment->new();
my $heap_id = $env2->allocate_heap_id();
my $val = $env2->lookup_heap($heap_id, "key");
is($val, undef, "Lookup on new heap should return undef for unknown key");

# Test 4: set_heap stores values correctly
$env2->set_heap($heap_id, "x", 42);
my $stored = $env2->lookup_heap($heap_id, "x");
is($stored, 42, "Should retrieve stored value from heap");

# Test 5: Multiple keys in same heap
$env2->set_heap($heap_id, "y", 99);
my $x_val = $env2->lookup_heap($heap_id, "x");
my $y_val = $env2->lookup_heap($heap_id, "y");
is($x_val, 42, "First key should still have correct value");
is($y_val, 99, "Second key should have correct value");

# Test 6: Different heaps are isolated
my $heap_id2 = $env2->allocate_heap_id();
$env2->set_heap($heap_id2, "x", 777);
my $heap1_val = $env2->lookup_heap($heap_id, "x");
my $heap2_val = $env2->lookup_heap($heap_id2, "x");
is($heap1_val, 42, "First heap should retain its value");
is($heap2_val, 777, "Second heap should have its own value");
