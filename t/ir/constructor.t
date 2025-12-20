# ABOUTME: Tests for Constructor IR node
# ABOUTME: Verifies constructor execution and field initialization
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Constructor;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::TypeRegistry;

# Reset registry
Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

# Test 1: Constructor node creation
{
    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { '$x' => undef, '$y' => undef },
        param_fields => [
            { name => '$x', required => 1 },
            { name => '$y', required => 0 },
        ],
    );

    # Register the class
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Point', $class_type);

    my $x_val = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->TOP()
    );
    my $y_val = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Point',
        args => { '$x' => $x_val, '$y' => $y_val },
    );

    ok($constructor, 'Constructor node created');
    is($constructor->op, 'Constructor', 'op is Constructor');
    is($constructor->class_name, 'Point', 'class_name is Point');
}

# Test 2: Constructor to_hash
{
    my $x_val = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Point',
        args => { '$x' => $x_val },
    );

    my $hash = $constructor->to_hash;
    is($hash->{op}, 'Constructor', 'to_hash op is Constructor');
    is($hash->{attributes}{class_name}, 'Point', 'to_hash has class_name');
    ok(exists $hash->{attributes}{args}, 'to_hash has args');
}

# Test 3: Constructor execution allocates object
{
    # Create a mock environment for execution
    my %heap;
    my $next_heap_id = 1;
    my $env = bless {}, 'MockEnv';

    no strict 'refs';
    *MockEnv::allocate_heap = sub {
        my ($self) = @_;
        my $id = $next_heap_id++;
        $heap{$id} = {};
        return $id;
    };
    *MockEnv::store_heap = sub {
        my ($self, $id, $field, $value) = @_;
        $heap{$id}{$field} = $value;
    };
    *MockEnv::lookup_heap = sub {
        my ($self, $id, $field) = @_;
        return $heap{$id}{$field};
    };

    my $x_val = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Point',
        args => { '$x' => $x_val },
    );

    # Create context function
    my %node_values = (
        "node:" . $x_val->id => 42,
    );
    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    ok(defined $heap_id, 'Constructor returns heap_id');
    is($heap{$heap_id}{'$x'}, 42, 'Field $x initialized correctly');
}

# Test 4: Constructor compute_type returns class type
{
    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Point',
        args => {},
    );

    my $type = $constructor->compute_type;
    ok($type, 'compute_type returns a type');
    like($type->name, qr/Point/, 'type name contains Point');
}

done_testing();
