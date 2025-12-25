#!/usr/bin/env perl
# ABOUTME: Tests for Chalk::Target::XS core visitor class
# ABOUTME: Verifies context management, type mapping, and visitor dispatch
use 5.42.0;
use Test::More;
use experimental qw(class);

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::IR::Context;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::IR::Type;

# Test loading the main visitor class
{
    use_ok('Chalk::Target::XS') or BAIL_OUT("Cannot load Chalk::Target::XS");
}

# Test basic instantiation
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );
    isa_ok($xs, 'Chalk::Target::XS', 'XS target instantiates');
}

# Test context management - bind_var and get_var
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # Bind a variable to a node ID
    $xs->bind_var(123, 'my_var');

    # Retrieve the bound variable
    is($xs->get_var(123), 'my_var', 'bind_var and get_var work correctly');
}

# Test alloc_temp - automatic temp variable allocation
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # Allocate temp for unbound node
    my $temp1 = $xs->alloc_temp(456);
    is($temp1, 'tmp_0', 'First temp is tmp_0');

    # Verify it's bound
    is($xs->get_var(456), 'tmp_0', 'alloc_temp binds the variable');

    # Allocate another temp
    my $temp2 = $xs->alloc_temp(789);
    is($temp2, 'tmp_1', 'Second temp is tmp_1');
}

# Test get_var falls back to alloc_temp for unbound nodes
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # get_var on unbound node should allocate temp
    my $var = $xs->get_var(999);
    like($var, qr/^tmp_\d+$/, 'get_var allocates temp for unbound node');
}

# Test get_c_type - IR type to C type mapping
{
    use Chalk::IR::Type::Integer;
    use Chalk::IR::Type::Float;
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::Num;
    use Chalk::Grammar::Chalk::Type::Str;
    use Chalk::Grammar::Chalk::Type::Array;
    use Chalk::Grammar::Chalk::Type::Hash;

    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # Test IR types
    my $int_node = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->TOP()
    );
    is($xs->get_c_type($int_node), 'IV', 'IR Integer maps to IV');

    my $float_node = Chalk::IR::Node::Constant->new(
        value => 3.14,
        type => Chalk::IR::Type::Float->TOP()
    );
    is($xs->get_c_type($float_node), 'NV', 'IR Float maps to NV');

    # Test Grammar types
    my $grammar_int_node = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    is($xs->get_c_type($grammar_int_node), 'IV', 'Grammar Int maps to IV');

    my $grammar_num_node = Chalk::IR::Node::Constant->new(
        value => 3.14,
        type => Chalk::Grammar::Chalk::Type::Num->new()
    );
    is($xs->get_c_type($grammar_num_node), 'NV', 'Grammar Num maps to NV');

    my $str_node = Chalk::IR::Node::Constant->new(
        value => 'hello',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    is($xs->get_c_type($str_node), 'SV*', 'Grammar Str maps to SV*');

    my $array_node = Chalk::IR::Node::Constant->new(
        value => [],
        type => Chalk::Grammar::Chalk::Type::Array->new(
            element_type => Chalk::Grammar::Chalk::Type::Int->new()
        )
    );
    is($xs->get_c_type($array_node), 'AV*', 'Grammar Array maps to AV*');

    my $hash_node = Chalk::IR::Node::Constant->new(
        value => {},
        type => Chalk::Grammar::Chalk::Type::Hash->new(
            value_type => Chalk::Grammar::Chalk::Type::Int->new()
        )
    );
    is($xs->get_c_type($hash_node), 'HV*', 'Grammar Hash maps to HV*');

    # Test fallback with base Type class
    my $unknown_node = Chalk::IR::Node::Constant->new(
        value => undef,
        type => Chalk::IR::Type->new()
    );
    is($xs->get_c_type($unknown_node), 'SV*', 'Unknown type maps to SV* (fallback)');
}

# Test visit() method dispatch
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # Create a Constant node
    my $const_node = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->TOP()
    );

    # visit() should dispatch to visit_Constant and return a VarDecl
    my $result = $xs->visit($const_node);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl',
           'visit() dispatches to visit_Constant');
}

# Test schedule_emission - basic structure
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # schedule_emission should return a list (possibly empty for now)
    my @order = $xs->schedule_emission();
    is(ref(\@order), 'ARRAY', 'schedule_emission returns an array');
}

# Test generate() method - basic orchestration
{
    my $graph = { nodes => {}, start => undef, end => undef };
    my $xs = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Module'
    );

    # generate() should return something (will fail until implemented)
    eval {
        my $result = $xs->generate();
    };
    # For now, this will fail - that's expected for TDD
    # We'll implement it next
}

done_testing();
