# ABOUTME: Tests for immutable Scope class - verifies variable name to IR node bindings
# ABOUTME: Ensures scope immutability, proper lookup/define, snapshot, and diff operations
use 5.42.0;
use utf8;

use Test2::V0;
use Scalar::Util 'refaddr';

use lib 'lib';
use Chalk::Bootstrap::Scope;
use Chalk::IR::NodeFactory;

# Reset factory to ensure clean test state

my $factory = Chalk::IR::NodeFactory->new;

# Test 1: Empty scope - lookup returns undef
{
    my $scope = Chalk::Bootstrap::Scope->new();
    is($scope->lookup('$x'), undef, 'empty scope lookup returns undef');
}

# Test 2: Define and lookup - define $x → Constant(0), lookup returns it
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node = $factory->make('Constant', const_type => 'int', value => 0);

    my $scope2 = $scope->define('$x', $node);
    is($scope2->lookup('$x'), $node, 'lookup returns defined node');
    is(refaddr($scope2->lookup('$x')), refaddr($node), 'lookup returns exact node reference');
}

# Test 3: Immutability - defining on scope2 doesn't change scope1
{
    my $scope1 = Chalk::Bootstrap::Scope->new();
    my $node = $factory->make('Constant', const_type => 'int', value => 1);

    my $scope2 = $scope1->define('$x', $node);

    is($scope1->lookup('$x'), undef, 'original scope unchanged after define');
    is($scope2->lookup('$x'), $node, 'new scope has the binding');
}

# Test 4: Overwrite - defining $x again returns new value, previous scope unchanged
{
    my $scope1 = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'int', value => 10);
    my $node_b = $factory->make('Constant', const_type => 'int', value => 20);

    my $scope2 = $scope1->define('$x', $node_a);
    my $scope3 = $scope2->define('$x', $node_b);

    is($scope1->lookup('$x'), undef, 'scope1 unchanged');
    is($scope2->lookup('$x'), $node_a, 'scope2 has first value');
    is($scope3->lookup('$x'), $node_b, 'scope3 has new value');
}

# Test 5: Multiple variables - define $x and $y, both look up correctly
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x = $factory->make('Constant', const_type => 'int', value => 100);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 200);

    my $scope2 = $scope->define('$x', $node_x);
    my $scope3 = $scope2->define('$y', $node_y);

    is($scope3->lookup('$x'), $node_x, 'first variable lookup works');
    is($scope3->lookup('$y'), $node_y, 'second variable lookup works');
}

# Test 6: Snapshot - returns hashref of current bindings
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x = $factory->make('Constant', const_type => 'int', value => 5);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 10);

    my $scope2 = $scope->define('$x', $node_x)->define('$y', $node_y);
    my $snapshot = $scope2->snapshot();

    is(ref($snapshot), 'HASH', 'snapshot returns hashref');
    is($snapshot->{'$x'}, $node_x, 'snapshot contains $x binding');
    is($snapshot->{'$y'}, $node_y, 'snapshot contains $y binding');
    is(scalar keys $snapshot->%*, 2, 'snapshot has correct number of bindings');
}

# Test 7: Diff - modified variable shows in diff
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_b = $factory->make('Constant', const_type => 'int', value => 2);

    my $scope2 = $scope->define('$x', $node_a);
    my $snapshot = $scope2->snapshot();

    my $scope3 = $scope2->define('$x', $node_b);
    my $diff = $scope3->diff($snapshot);

    is($diff->{'$x'}, $node_b, 'diff shows modified variable with new value');
    is(scalar keys $diff->%*, 1, 'diff contains only modified variable');
}

# Test 8: Diff - new variable shows in diff
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 2);

    my $scope2 = $scope->define('$x', $node_x);
    my $snapshot = $scope2->snapshot();

    my $scope3 = $scope2->define('$y', $node_y);
    my $diff = $scope3->diff($snapshot);

    is($diff->{'$y'}, $node_y, 'diff shows new variable');
    ok(!exists $diff->{'$x'}, 'diff does not show unchanged variable');
}

# Test 9: Diff - unchanged variable not in diff
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node = $factory->make('Constant', const_type => 'int', value => 42);

    my $scope2 = $scope->define('$x', $node);
    my $snapshot = $scope2->snapshot();

    my $diff = $scope2->diff($snapshot);

    is(scalar keys $diff->%*, 0, 'diff is empty when nothing changed');
}

# Test 10: Diff - multiple changes (both modified and new variables)
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x1 = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_x2 = $factory->make('Constant', const_type => 'int', value => 2);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 3);
    my $node_z = $factory->make('Constant', const_type => 'int', value => 4);

    my $scope2 = $scope->define('$x', $node_x1)->define('$z', $node_z);
    my $snapshot = $scope2->snapshot();

    my $scope3 = $scope2->define('$x', $node_x2)->define('$y', $node_y);
    my $diff = $scope3->diff($snapshot);

    is($diff->{'$x'}, $node_x2, 'diff shows modified variable');
    is($diff->{'$y'}, $node_y, 'diff shows new variable');
    ok(!exists $diff->{'$z'}, 'diff does not show unchanged variable');
    is(scalar keys $diff->%*, 2, 'diff has correct number of changes');
}

# Test 11: variable_names - returns all bound names
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_x = $factory->make('Constant', const_type => 'int', value => 1);
    my $node_y = $factory->make('Constant', const_type => 'int', value => 2);
    my $node_z = $factory->make('Constant', const_type => 'int', value => 3);

    my $scope2 = $scope->define('$x', $node_x)
                      ->define('@arr', $node_y)
                      ->define('%hash', $node_z);

    my @names = $scope2->variable_names();
    my @sorted = sort @names;

    is(\@sorted, ['$x', '%hash', '@arr'], 'variable_names returns all bound names');
}

done_testing();
