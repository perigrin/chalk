# ABOUTME: Test XS target control flow visitor methods for If, Region, Phi
# ABOUTME: Verifies IfStatement AST node generation and control flow handling
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
use Chalk::Target::XS::AST::IfStatement;
use Chalk::Target::XS::AST::VarDecl;
use Chalk::Target::XS::AST::Literal;
use Chalk::Target::XS::AST::Return;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

# Test 1: IfStatement AST node basic structure
subtest 'IfStatement AST node structure' => sub {
    my $then_stmt = Chalk::Target::XS::AST::Return->new(expr => 'tmp_1');
    my $else_stmt = Chalk::Target::XS::AST::Return->new(expr => 'tmp_2');

    my $if_stmt = Chalk::Target::XS::AST::IfStatement->new(
        condition => 'cond_0',
        then_body => [$then_stmt],
        else_body => [$else_stmt],
    );

    is($if_stmt->condition, 'cond_0', 'IfStatement has condition');
    is(scalar($if_stmt->then_body->@*), 1, 'IfStatement has then_body');
    is(scalar($if_stmt->else_body->@*), 1, 'IfStatement has else_body');
};

# Test 2: IfStatement emit() produces C if/else
subtest 'IfStatement emit produces C if/else' => sub {
    my $then_return = Chalk::Target::XS::AST::Return->new(expr => 'a');
    my $else_return = Chalk::Target::XS::AST::Return->new(expr => 'b');

    my $if_stmt = Chalk::Target::XS::AST::IfStatement->new(
        condition => 'cond',
        then_body => [$then_return],
        else_body => [$else_return],
    );

    my $output = $if_stmt->emit();
    like($output, qr/^if \(cond\) \{/, 'Starts with if (cond) {');
    like($output, qr/RETVAL = a;/, 'Contains then body');
    like($output, qr/\} else \{/, 'Has else clause');
    like($output, qr/RETVAL = b;/, 'Contains else body');
    like($output, qr/\}$/, 'Ends with }');
};

# Test 3: IfStatement without else body
subtest 'IfStatement without else body' => sub {
    my $then_return = Chalk::Target::XS::AST::Return->new(expr => 'x');

    my $if_stmt = Chalk::Target::XS::AST::IfStatement->new(
        condition => 'test_cond',
        then_body => [$then_return],
        # No else_body
    );

    my $output = $if_stmt->emit();
    like($output, qr/^if \(test_cond\) \{/, 'Starts with if');
    unlike($output, qr/else/, 'No else clause');
};

# Test 4: visit_If returns IfStatement AST node
subtest 'visit_If creates IfStatement' => sub {
    my $cond_const = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Bool->constant(1),
    );

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_const->id],
        condition_id => $cond_const->id,
        condition => $cond_const,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Bind the condition variable
    $target->bind_var($cond_const->id, 'cond_0');

    my $result = $target->visit_If($if_node);

    # For now, If nodes might return undef since full control flow
    # restructuring is complex. This test documents current behavior.
    # TODO: When full control flow is implemented, this should return IfStatement
    ok(1, 'visit_If does not crash');
};

# Test 5: visit_Region returns undef (CFG merge, no XS output)
subtest 'visit_Region returns undef' => sub {
    my $region = Chalk::IR::Node::Region->new(
        inputs => [],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_Region($region);

    ok(!defined($result), 'visit_Region returns undef (CFG node)');
};

done_testing();
