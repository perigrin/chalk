# ABOUTME: Test file for Chalk::IR::Node::LEF (Float Less-Than-or-Equal comparison)
# ABOUTME: Validates constant folding, self-comparison, and type computation
use 5.42.0;
use Test::More;
use Chalk::IR::Node::LEF;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Integer;

# Test 1: Basic LEF node creation
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    ok($lef, 'LEF node created');
    is($lef->op, 'LEF', 'op returns LEF');
    ok($lef->id, 'node has an id');
    is_deeply($lef->inputs, [$left->id, $right->id], 'inputs returns left and right ids');
}

# Test 2: Constant folding - less than case (2.5 <= 3.0 = 1)
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    # compute() should return constant Integer type with value 1
    my $type = $lef->compute();
    ok($type->is_constant, 'compute returns constant type for constant inputs');
    is($type->value, 1, 'compute returns 1 for 2.5 <= 3.0');

    # peephole() should fold to Constant node
    my $optimized = $lef->peephole();
    isa_ok($optimized, 'Chalk::IR::Node::Constant', 'peephole folds to Constant');
    is($optimized->value, 1, 'peephole constant has value 1');
    is($optimized->type, 'Integer', 'peephole constant is Integer type');
}

# Test 3: Constant folding - equal case (2.5 <= 2.5 = 1)
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    # compute() should return constant Integer type with value 1
    my $type = $lef->compute();
    ok($type->is_constant, 'compute returns constant type for equal values');
    is($type->value, 1, 'compute returns 1 for 2.5 <= 2.5');

    # peephole() should fold to Constant node
    my $optimized = $lef->peephole();
    isa_ok($optimized, 'Chalk::IR::Node::Constant', 'peephole folds to Constant');
    is($optimized->value, 1, 'peephole constant has value 1');
    is($optimized->type, 'Integer', 'peephole constant is Integer type');
}

# Test 4: Constant folding - greater than case (3.0 <= 2.5 = 0)
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    # compute() should return constant Integer type with value 0
    my $type = $lef->compute();
    ok($type->is_constant, 'compute returns constant type for constant inputs');
    is($type->value, 0, 'compute returns 0 for 3.0 <= 2.5');

    # peephole() should fold to Constant node
    my $optimized = $lef->peephole();
    isa_ok($optimized, 'Chalk::IR::Node::Constant', 'peephole folds to Constant');
    is($optimized->value, 0, 'peephole constant has value 0');
    is($optimized->type, 'Integer', 'peephole constant is Integer type');
}

# Test 5: Self-comparison optimization (x <= x = 1)
{
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $lef = Chalk::IR::Node::LEF->new(left => $x, right => $x);

    # idealize() should detect self-comparison
    my $idealized = $lef->idealize();
    isa_ok($idealized, 'Chalk::IR::Node::Constant', 'idealize detects self-comparison');
    is($idealized->value, 1, 'self-comparison returns 1');
    is($idealized->type, 'Integer', 'self-comparison returns Integer');

    # peephole() should optimize to constant 1
    my $optimized = $lef->peephole();
    isa_ok($optimized, 'Chalk::IR::Node::Constant', 'peephole optimizes self-comparison');
    is($optimized->value, 1, 'peephole returns 1 for x <= x');
}

# Test 6: Execute method
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    my $context = sub {
        my $key = shift;
        return 2.5 if $key eq "node:" . $left->id;
        return 3.0 if $key eq "node:" . $right->id;
        die "Unknown key: $key";
    };

    my $result = $lef->execute($context);
    is($result, 1, 'execute returns 1 for 2.5 <= 3.0');
}

# Test 7: Execute method - greater than case
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.0);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    my $context = sub {
        my $key = shift;
        return 3.5 if $key eq "node:" . $left->id;
        return 2.0 if $key eq "node:" . $right->id;
        die "Unknown key: $key";
    };

    my $result = $lef->execute($context);
    is($result, 0, 'execute returns 0 for 3.5 <= 2.0');
}

# Test 8: Execute method - equal values
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    my $context = sub {
        my $key = shift;
        return 2.5 if $key eq "node:" . $left->id;
        return 2.5 if $key eq "node:" . $right->id;
        die "Unknown key: $key";
    };

    my $result = $lef->execute($context);
    is($result, 1, 'execute returns 1 for 2.5 <= 2.5');
}

# Test 9: to_hash method
{
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $lef = Chalk::IR::Node::LEF->new(left => $left, right => $right);

    my $hash = $lef->to_hash();
    is($hash->{op}, 'LEF', 'to_hash contains LEF op');
    is($hash->{id}, $lef->id, 'to_hash contains node id');
    is_deeply($hash->{inputs}, [$left->id, $right->id], 'to_hash contains inputs');
    is($hash->{attributes}{left_id}, $left->id, 'to_hash contains left_id attribute');
    is($hash->{attributes}{right_id}, $right->id, 'to_hash contains right_id attribute');
}

done_testing();
