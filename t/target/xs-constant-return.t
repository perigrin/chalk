#!/usr/bin/env perl
# ABOUTME: Tests for XS Target visitor methods: visit_Start, visit_Stop, visit_Constant, visit_Return
# ABOUTME: Verifies correct AST generation for basic IR nodes
use 5.42.0;
use Test::More;
use experimental qw(class);
use FindBin qw($Bin);
use lib "$Bin/../../lib";

use Chalk::Target::XS;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Stop;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;

# Test visit_Start - should return undef (no XS output for Start node)
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $start = Chalk::IR::Node::Start->new(
        function_name => 'test_func',
    );

    my $result = $target->visit_Start($start);
    is($result, undef, 'visit_Start returns undef');
}

# Test visit_Stop - should return undef (no XS output for Stop node)
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $stop = Chalk::IR::Node::Stop->new(
        inputs => [],
        returns => [],
    );

    my $result = $target->visit_Stop($stop);
    is($result, undef, 'visit_Stop returns undef');
}

# Test visit_Constant with integer value
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $result = $target->visit_Constant($const);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Constant returns VarDecl');

    my $emitted = $result->emit();
    like($emitted, qr/IV tmp_0 = 42;/, 'Integer constant creates IV VarDecl with literal init');
}

# Test visit_Constant with float value
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $const = Chalk::IR::Node::Constant->new(
        value => 3.14,
        type => Chalk::IR::Type::Float->constant(3.14),
    );

    my $result = $target->visit_Constant($const);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Constant returns VarDecl for float');

    my $emitted = $result->emit();
    like($emitted, qr/NV tmp_0 = 3\.14;/, 'Float constant creates NV VarDecl with literal init');
}

# Test visit_Constant with Grammar type
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $const = Chalk::IR::Node::Constant->new(
        value => 99,
        type => Chalk::Grammar::Chalk::Type::Int->new(),
    );

    my $result = $target->visit_Constant($const);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Constant works with Grammar types');

    my $emitted = $result->emit();
    like($emitted, qr/IV tmp_0 = 99;/, 'Grammar Int type creates IV VarDecl');
}

# Test visit_Return - gets input value from context
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    # Create a constant that will be the return value
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    # Bind the constant to a variable in the target's context
    $target->bind_var($const->id, 'tmp_0');

    # Create a Return node with control and value inputs
    my $return = Chalk::IR::Node::Return->new(
        control => undef,  # Control not needed for this test
        value => $const,
    );

    my $result = $target->visit_Return($return);
    isa_ok($result, 'Chalk::Target::XS::AST::Return', 'visit_Return returns Return AST node');

    my $emitted = $result->emit();
    is($emitted, 'RETVAL = tmp_0;', 'Return emits RETVAL assignment with correct variable');
}

# Test visit_Return with unbound variable (should allocate temp)
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'Test::Module',
    );

    my $const = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::IR::Type::Integer->constant(100),
    );

    # Do NOT bind the constant - let get_var allocate a temp

    my $return = Chalk::IR::Node::Return->new(
        control => undef,
        value => $const,
    );

    my $result = $target->visit_Return($return);
    isa_ok($result, 'Chalk::Target::XS::AST::Return', 'visit_Return allocates temp for unbound value');

    my $emitted = $result->emit();
    like($emitted, qr/RETVAL = tmp_\d+;/, 'Return emits RETVAL with auto-allocated temp variable');
}

done_testing();
