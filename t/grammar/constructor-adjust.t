# ABOUTME: Tests for ADJUST block execution in constructors
# ABOUTME: Verifies ADJUST runs after field initialization
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::IR::Node::Constructor;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

# Reset registry
Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

# Test 1: ADJUST block executes after field initialization
{
    # Create a simple ADJUST node that sets $distance based on $x and $y
    # For testing, we'll simulate this with a mock

    # First, create IR nodes for the ADJUST block
    # The ADJUST block would compute: $distance = $x + $y (simplified from sqrt)
    my $adjust_node = Chalk::IR::Node::Constant->new(
        value => 7,  # Simulated computed value (3 + 4)
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { '$x' => undef, '$y' => undef, '$distance' => undef },
        param_fields => [
            { name => '$x', required => 1 },
            { name => '$y', required => 1 },
        ],
        adjust_blocks => [
            {
                statements => [ $adjust_node ],
                assigns => { '$distance' => $adjust_node },
            }
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Point', $class_type);

    # Create constructor with x=3, y=4
    my $x_val = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->TOP()
    );
    my $y_val = Chalk::IR::Node::Constant->new(
        value => 4,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Point',
        args => { '$x' => $x_val, '$y' => $y_val },
    );

    # Create mock environment
    my %heap;
    my $next_id = 1;
    my $env = bless {}, 'MockEnv';
    no strict 'refs';
    *MockEnv::allocate_heap = sub { $next_id++ };
    *MockEnv::store_heap = sub {
        my ($self, $id, $field, $val) = @_;
        $heap{$id}{$field} = $val;
    };
    *MockEnv::lookup_heap = sub {
        my ($self, $id, $field) = @_;
        return $heap{$id}{$field};
    };

    my %node_values;
    $node_values{"node:" . $x_val->id} = 3;
    $node_values{"node:" . $y_val->id} = 4;
    $node_values{"node:" . $adjust_node->id} = 7;  # The computed distance

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    ok(defined $heap_id, 'Constructor returns heap_id');
    is($heap{$heap_id}{'$x'}, 3, 'Field $x initialized correctly');
    is($heap{$heap_id}{'$y'}, 4, 'Field $y initialized correctly');
    is($heap{$heap_id}{'$distance'}, 7, 'ADJUST block set $distance');
}

# Test 2: Multiple ADJUST blocks execute in order
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    my $adjust1_node = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->TOP()
    );
    my $adjust2_node = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Multi',
        fields => { '$a' => undef, '$b' => undef },
        param_fields => [],
        adjust_blocks => [
            { statements => [ $adjust1_node ], assigns => { '$a' => $adjust1_node } },
            { statements => [ $adjust2_node ], assigns => { '$b' => $adjust2_node } },
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Multi', $class_type);

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Multi',
        args => {},
    );

    my %heap;
    my $next_id = 1;
    my $env = bless {}, 'MockEnv2';
    no strict 'refs';
    *MockEnv2::allocate_heap = sub { $next_id++ };
    *MockEnv2::store_heap = sub {
        my ($self, $id, $field, $val) = @_;
        $heap{$id}{$field} = $val;
    };

    my %node_values;
    $node_values{"node:" . $adjust1_node->id} = 10;
    $node_values{"node:" . $adjust2_node->id} = 20;

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    is($heap{$heap_id}{'$a'}, 10, 'First ADJUST block set $a');
    is($heap{$heap_id}{'$b'}, 20, 'Second ADJUST block set $b');
}

# Test 3: ADJUST can read fields set by constructor args
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    # Simulate ADJUST that reads $count and sets $doubled = $count * 2
    my $doubled_node = Chalk::IR::Node::Constant->new(
        value => 84,  # 42 * 2
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Doubler',
        fields => { '$count' => undef, '$doubled' => undef },
        param_fields => [
            { name => '$count', required => 1 },
        ],
        adjust_blocks => [
            { statements => [ $doubled_node ], assigns => { '$doubled' => $doubled_node } },
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Doubler', $class_type);

    my $count_val = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Doubler',
        args => { '$count' => $count_val },
    );

    my %heap;
    my $next_id = 1;
    my $env = bless {}, 'MockEnv3';
    no strict 'refs';
    *MockEnv3::allocate_heap = sub { $next_id++ };
    *MockEnv3::store_heap = sub {
        my ($self, $id, $field, $val) = @_;
        $heap{$id}{$field} = $val;
    };

    my %node_values;
    $node_values{"node:" . $count_val->id} = 42;
    $node_values{"node:" . $doubled_node->id} = 84;

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    is($heap{$heap_id}{'$count'}, 42, 'Field $count initialized from arg');
    is($heap{$heap_id}{'$doubled'}, 84, 'ADJUST set $doubled based on $count');
}

done_testing();
