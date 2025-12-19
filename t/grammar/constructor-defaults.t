# ABOUTME: Tests for constructor field default handling
# ABOUTME: Verifies defaults are evaluated for missing :param fields
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

# Test 1: Constructor uses default when arg is missing
{
    my $default_node = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Counter',
        fields => { '$count' => undef },
        param_fields => [
            { name => '$count', required => 0, default => $default_node },
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Counter', $class_type);

    # Create constructor without providing 'count' arg
    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Counter',
        args => {},  # No args provided
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

    my %node_values;
    $node_values{"node:" . $default_node->id} = 0;

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    ok(defined $heap_id, 'Constructor returns heap_id');
    is($heap{$heap_id}{'$count'}, 0, 'Default value used for missing arg');
}

# Test 2: Constructor uses provided arg over default
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    my $default_node = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Counter2',
        fields => { '$count' => undef },
        param_fields => [
            { name => '$count', required => 0, default => $default_node },
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('Counter2', $class_type);

    my $provided_value = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->TOP()
    );

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'Counter2',
        args => { '$count' => $provided_value },
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
    $node_values{"node:" . $provided_value->id} = 42;
    $node_values{"node:" . $default_node->id} = 0;

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return $node_values{$key};
    };

    my $heap_id = $constructor->execute($context);

    is($heap{$heap_id}{'$count'}, 42, 'Provided value takes precedence over default');
}

# Test 3: Constructor throws error for missing required param
{
    Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

    my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'RequiredField',
        fields => { '$x' => undef },
        param_fields => [
            { name => '$x', required => 1 },  # No default
        ],
    );
    Chalk::Grammar::Chalk::TypeRegistry->instance()->register('RequiredField', $class_type);

    my $constructor = Chalk::IR::Node::Constructor->new(
        class_name => 'RequiredField',
        args => {},  # Missing required $x
    );

    my $env = bless {}, 'MockEnv3';
    no strict 'refs';
    *MockEnv3::allocate_heap = sub { 1 };
    *MockEnv3::store_heap = sub { };

    my $context = sub {
        my ($key) = @_;
        return $env if $key eq 'env:';
        return undef;
    };

    my $died = 0;
    my $error_msg;
    eval {
        $constructor->execute($context);
    };
    if ($@) {
        $died = 1;
        $error_msg = $@;
    }

    ok($died, 'Constructor dies for missing required param');
    like($error_msg, qr/required|missing/i, 'Error message mentions required/missing');
}

done_testing();
