# ABOUTME: Test XS target variable visitor methods for Store and Load
# ABOUTME: Verifies variable assignment and reading XS code generation
use 5.42.0;
use Test::More;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Target::XS;
use Chalk::IR::Node::Store;
use Chalk::IR::Node::Load;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Start;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::String;

# Test 1: visit_Store creates VarDecl for variable assignment
{
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$x',
        value => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Pre-bind the constant's temp variable
    $target->bind_var($const->id, 'tmp_0');

    my $result = $target->visit_Store($store);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Store returns VarDecl');
    is($result->name, 'x', 'visit_Store uses variable name without sigil');
    is($result->init, 'tmp_0', 'visit_Store init references value temp');
}

# Test 2: visit_Store binds variable name for later use
{
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::IR::Type::Integer->constant(100),
    );

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$myvar',
        value => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_0');
    $target->visit_Store($store);

    # After visiting Store, the Store node should be bound to the variable name
    my $bound_var = $target->get_var($store->id);
    is($bound_var, 'myvar', 'visit_Store binds Store node to variable name');
}

# Test 3: visit_Load binds to underlying value's temp
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 77,
        type => Chalk::IR::Type::Integer->constant(77),
    );

    my $load = Chalk::IR::Node::Load->new(
        name => '$y',
        value => $const,
        inputs => [],  # Base class requires inputs
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Pre-bind the constant
    $target->bind_var($const->id, 'tmp_0');

    my $result = $target->visit_Load($load);

    # Load should return undef (no statement) but bind the Load node
    is($result, undef, 'visit_Load returns undef (binding only)');

    my $bound_var = $target->get_var($load->id);
    is($bound_var, 'tmp_0', 'visit_Load binds Load node to value temp');
}

# Test 4: visit_Load with named variable binding
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 99,
        type => Chalk::IR::Type::Integer->constant(99),
    );

    # Simulate a variable that's already been stored
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Create a Store first to establish the variable
    my $start = Chalk::IR::Node::Start->new();
    $target->bind_var($const->id, 'tmp_0');

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$z',
        value => $const,
    );
    $target->visit_Store($store);

    # Now create a Load that references the stored variable
    # The Load's value should bind to the same variable
    my $load = Chalk::IR::Node::Load->new(
        name => '$z',
        value => $const,  # Same underlying constant
        inputs => [],
    );

    $target->visit_Load($load);

    my $bound_var = $target->get_var($load->id);
    is($bound_var, 'tmp_0', 'visit_Load binds to same temp as underlying value');
}

# Test 5: Store emits complete C declaration
{
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$count',
        value => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_0');
    my $result = $target->visit_Store($store);

    like($result->emit(), qr/IV\s+count\s*=\s*tmp_0;/, 'Store emits IV declaration for integer');
}

# Test 6: Store with string value
{
    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 'hello',
        type => Chalk::IR::Type::String->new(),
    );

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$msg',
        value => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_str');
    my $result = $target->visit_Store($store);

    is($result->type, 'SV*', 'Store with string uses SV* type');
}

# Test 7: visit dispatch includes Store and Load
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    my $start = Chalk::IR::Node::Start->new();
    my $const = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    $target->bind_var($const->id, 'tmp_0');

    my $store = Chalk::IR::Node::Store->new(
        control => $start,
        var => '$a',
        value => $const,
    );

    my $load = Chalk::IR::Node::Load->new(
        name => '$b',
        value => $const,
        inputs => [],
    );

    # Test that visit() dispatches correctly
    my $store_result = $target->visit($store);
    isa_ok($store_result, 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches Store');

    my $load_result = $target->visit($load);
    is($load_result, undef, 'visit() dispatches Load (returns undef)');
}

done_testing();
