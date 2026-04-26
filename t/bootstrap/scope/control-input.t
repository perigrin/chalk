# ABOUTME: Tests that Scope carries a control input alongside variable bindings.
# ABOUTME: Verifies with_control returns a new Scope with control replaced.
use 5.42.0;
use utf8;
use Test::More;
use experimental 'class';

use lib 'lib';
use Chalk::Bootstrap::Scope;

# We use plain hashref objects as mock IR nodes since we only test identity,
# not IR semantics.
my $start_node  = { op => 'Start'  };
my $if_node     = { op => 'If'     };
my $region_node = { op => 'Region' };

subtest 'Scope has a control method' => sub {
    my $scope = Chalk::Bootstrap::Scope->new();
    can_ok($scope, 'control');
    is($scope->control, undef, 'control defaults to undef');
};

subtest 'Scope has a with_control method' => sub {
    my $scope = Chalk::Bootstrap::Scope->new();
    can_ok($scope, 'with_control');
};

subtest 'with_control returns a new Scope with the control replaced' => sub {
    my $scope  = Chalk::Bootstrap::Scope->new();
    my $scoped = $scope->with_control($start_node);

    isnt(refaddr($scope), refaddr($scoped),
        'with_control returns a distinct Scope object (immutable)');
    is($scoped->control, $start_node, 'with_control sets control to provided node');
    is($scope->control, undef, 'original Scope control unchanged (immutable)');
};

subtest 'with_control preserves existing bindings' => sub {
    my $scope  = Chalk::Bootstrap::Scope->new()->define('$x', 'some_node');
    my $scoped = $scope->with_control($if_node);

    is($scoped->lookup('$x'), 'some_node',
        'bindings preserved after with_control');
    is($scoped->control, $if_node, 'control set correctly');
};

subtest 'multiple with_control calls chain correctly' => sub {
    my $scope = Chalk::Bootstrap::Scope->new()
        ->with_control($start_node)
        ->with_control($if_node)
        ->with_control($region_node);

    is($scope->control, $region_node, 'last with_control wins');
};

subtest 'define preserves control' => sub {
    my $scope  = Chalk::Bootstrap::Scope->new()->with_control($start_node);
    my $scoped = $scope->define('$y', 'another_node');

    is($scoped->control, $start_node, 'define preserves control field');
    is($scoped->lookup('$y'), 'another_node', 'new binding accessible');
};

subtest 'merge preserves control from self (left side wins)' => sub {
    my $scope_a = Chalk::Bootstrap::Scope->new()->with_control($start_node);
    my $scope_b = Chalk::Bootstrap::Scope->new()->with_control($region_node)->define('$z', 'z_node');

    my $merged = $scope_a->merge($scope_b);

    # merge() produces scope with all bindings; control comes from left (self)
    is($merged->control, $start_node, 'merge: control from self (left)');
    is($merged->lookup('$z'), 'z_node', 'merge: bindings from other present');
};

done_testing;
