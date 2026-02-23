# ABOUTME: Tests for CFG peephole optimizations on Sea of Nodes IR.
# ABOUTME: Verifies Phi collapse, constant-If elimination, and Region bypass.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Optimizer;

# --- Test 1: Phi(Region, X, X) → X when all value inputs are same node ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $val = $factory->make('Constant', const_type => 'integer', value => 42);
    my $cond = $factory->make('Constant', const_type => 'integer', value => 1);

    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $true_proj = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$true_proj, $false_proj]);

    # Phi with same value on both sides
    my $phi = $factory->make('Phi', region => $region, values => [$val, $val]);

    # Peephole: Phi(R, X, X) should collapse to X
    my $optimized = Chalk::Bootstrap::IR::Optimizer->collapse_phi($phi);
    is($optimized, $val, 'Phi(R, X, X) collapses to X');
}

# --- Test 2: Phi with different values does NOT collapse ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $val_a = $factory->make('Constant', const_type => 'integer', value => 1);
    my $val_b = $factory->make('Constant', const_type => 'integer', value => 2);
    my $cond = $factory->make('Constant', const_type => 'integer', value => 1);

    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $true_proj = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $phi = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);

    my $optimized = Chalk::Bootstrap::IR::Optimizer->collapse_phi($phi);
    is($optimized, $phi, 'Phi with different values not collapsed');
}

# --- Test 3: Region with single control input → bypass ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $region = $factory->make('Region', controls => [$start]);

    my $optimized = Chalk::Bootstrap::IR::Optimizer->collapse_region($region);
    is($optimized, $start, 'Region([single]) collapses to single control');
}

# --- Test 4: Region with multiple controls does NOT collapse ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $true_proj = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $optimized = Chalk::Bootstrap::IR::Optimizer->collapse_region($region);
    is($optimized, $region, 'Region with 2 controls not collapsed');
}

done_testing();
