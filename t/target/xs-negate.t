# ABOUTME: Test XS target visitor for unary negation (Negate)
# ABOUTME: Verifies XS code generation for -$x expressions
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
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

# Test 1: visit_Negate creates VarDecl with negation
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $negate = Chalk::IR::Node::Negate->new(
        operand => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Pre-bind the constant's temp variable
    $target->bind_var($const->id, 'tmp_0');

    my $result = $target->visit_Negate($negate);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Negate returns VarDecl');
    like($result->name, qr/^tmp_\d+$/, 'visit_Negate allocates temp variable');
}

# Test 2: visit_Negate emits negation expression
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );

    my $negate = Chalk::IR::Node::Negate->new(
        operand => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_0');
    my $result = $target->visit_Negate($negate);

    like($result->emit(), qr/-\s*tmp_0/, 'visit_Negate emits negation of operand');
}

# Test 3: visit_Negate with float constant type
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 3.14,
        type => Chalk::IR::Type::Float->constant(3.14),
    );

    my $negate = Chalk::IR::Node::Negate->new(
        operand => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_float');
    my $result = $target->visit_Negate($negate);

    # Negate's compute() returns Integer for constant folding, so type is IV
    # For non-constant float operands, it would fall back to SV*
    is($result->type, 'IV', 'visit_Negate uses IV type (constant folding)');
    like($result->emit(), qr/-\s*tmp_float/, 'visit_Negate emits negation of float');
}

# Test 4: visit dispatch includes Negate
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );

    my $negate = Chalk::IR::Node::Negate->new(
        operand => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'tmp_0');

    my $result = $target->visit($negate);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches Negate');
}

# Test 5: Negate emits complete C declaration
{
    my $const = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::IR::Type::Integer->constant(100),
    );

    my $negate = Chalk::IR::Node::Negate->new(
        operand => $const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const->id, 'x');
    my $result = $target->visit_Negate($negate);

    like($result->emit(), qr/IV\s+tmp_\d+\s*=\s*-\s*x;/, 'Negate emits complete IV declaration');
}

done_testing();
