# ABOUTME: Test XS target visitor for string operations (StrConcat, InterpolatedString)
# ABOUTME: Verifies XS code generation for string concatenation and interpolation
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
use Chalk::IR::Node::StrConcat;
use Chalk::IR::Node::InterpolatedString;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::String;

# Test 1: visit_StrConcat creates VarDecl with concatenation
{
    my $left = Chalk::IR::Node::Constant->new(
        value => "Hello",
        type => Chalk::IR::Type::String->new(),
    );

    my $right = Chalk::IR::Node::Constant->new(
        value => " World",
        type => Chalk::IR::Type::String->new(),
    );

    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Pre-bind the operand temp variables
    $target->bind_var($left->id, 'tmp_left');
    $target->bind_var($right->id, 'tmp_right');

    my $result = $target->visit_StrConcat($concat);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_StrConcat returns VarDecl');
    like($result->name, qr/^tmp_\d+$/, 'visit_StrConcat allocates temp variable');
}

# Test 2: visit_StrConcat emits sv_catsv concatenation
{
    my $left = Chalk::IR::Node::Constant->new(
        value => "foo",
        type => Chalk::IR::Type::String->new(),
    );

    my $right = Chalk::IR::Node::Constant->new(
        value => "bar",
        type => Chalk::IR::Type::String->new(),
    );

    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'str_a');
    $target->bind_var($right->id, 'str_b');
    my $result = $target->visit_StrConcat($concat);

    my $emitted = $result->emit();
    like($emitted, qr/sv_catsv/, 'visit_StrConcat emits sv_catsv');
    like($emitted, qr/str_a/, 'visit_StrConcat references left operand');
    like($emitted, qr/str_b/, 'visit_StrConcat references right operand');
}

# Test 3: visit_StrConcat returns SV* type
{
    my $left = Chalk::IR::Node::Constant->new(
        value => "a",
        type => Chalk::IR::Type::String->new(),
    );

    my $right = Chalk::IR::Node::Constant->new(
        value => "b",
        type => Chalk::IR::Type::String->new(),
    );

    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'x');
    $target->bind_var($right->id, 'y');
    my $result = $target->visit_StrConcat($concat);

    is($result->type, 'SV*', 'visit_StrConcat uses SV* type');
}

# Test 4: visit dispatch includes StrConcat
{
    my $left = Chalk::IR::Node::Constant->new(
        value => "test",
        type => Chalk::IR::Type::String->new(),
    );

    my $right = Chalk::IR::Node::Constant->new(
        value => "ing",
        type => Chalk::IR::Type::String->new(),
    );

    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'tmp_0');
    $target->bind_var($right->id, 'tmp_1');

    my $result = $target->visit($concat);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches StrConcat');
}

# Test 5: visit_InterpolatedString creates VarDecl
{
    my $part1 = Chalk::IR::Node::Constant->new(
        value => "Hello ",
        type => Chalk::IR::Type::String->new(),
    );

    my $part2 = Chalk::IR::Node::Constant->new(
        value => "World",
        type => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($part1->id, 'part_0');
    $target->bind_var($part2->id, 'part_1');

    my $result = $target->visit_InterpolatedString($interp);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_InterpolatedString returns VarDecl');
    like($result->name, qr/^tmp_\d+$/, 'visit_InterpolatedString allocates temp variable');
}

# Test 6: visit_InterpolatedString emits concatenation for all parts
{
    my $part1 = Chalk::IR::Node::Constant->new(
        value => "Hi ",
        type => Chalk::IR::Type::String->new(),
    );

    my $part2 = Chalk::IR::Node::Constant->new(
        value => "there",
        type => Chalk::IR::Type::String->new(),
    );

    my $part3 = Chalk::IR::Node::Constant->new(
        value => "!",
        type => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2, $part3],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($part1->id, 'p0');
    $target->bind_var($part2->id, 'p1');
    $target->bind_var($part3->id, 'p2');

    my $result = $target->visit_InterpolatedString($interp);
    my $emitted = $result->emit();

    # Should reference all parts in the concatenation
    like($emitted, qr/p0/, 'visit_InterpolatedString references part 0');
    like($emitted, qr/p1/, 'visit_InterpolatedString references part 1');
    like($emitted, qr/p2/, 'visit_InterpolatedString references part 2');
}

# Test 7: visit_InterpolatedString returns SV* type
{
    my $part = Chalk::IR::Node::Constant->new(
        value => "text",
        type => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($part->id, 'str');
    my $result = $target->visit_InterpolatedString($interp);

    is($result->type, 'SV*', 'visit_InterpolatedString uses SV* type');
}

# Test 8: visit dispatch includes InterpolatedString
{
    my $part = Chalk::IR::Node::Constant->new(
        value => "test",
        type => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($part->id, 'tmp_0');

    my $result = $target->visit($interp);
    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches InterpolatedString');
}

# Test 9: visit_InterpolatedString with empty parts
{
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_InterpolatedString($interp);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_InterpolatedString handles empty parts');
    my $emitted = $result->emit();
    like($emitted, qr/newSVpvn\("", 0\)|newSVpvs\(""\)/, 'Empty InterpolatedString creates empty string');
}

done_testing();
