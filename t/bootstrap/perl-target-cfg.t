# ABOUTME: Tests Perl target emission for If/Region/Phi/Loop CFG node subgraphs.
# ABOUTME: Verifies Perl code output contains correct if/else and loop structures.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::Perl;

# --- Test 1: If/Region subgraph emits Perl if/else ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'string', value => '$x');

    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();

    my $then_node = $factory->make('Constant', const_type => 'integer', value => 42);
    my $else_node = $factory->make('Constant', const_type => 'integer', value => 99);
    my $code = $target->emit_cfg_if($if_node, $true_proj, $false_proj,
                                     [$then_node], [$else_node]);
    ok(defined $code, 'emit_cfg_if returns code');
    like($code, qr/if\s*\(/, 'emitted code contains if');
    like($code, qr/\}\s*else\s*\{/, 'emitted code contains else branch');
}

# --- Test 2: Phi node emits Perl my variable with conditional assignment ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'string', value => '$flag');
    my $val_a = $factory->make('Constant', const_type => 'integer', value => 42);
    my $val_b = $factory->make('Constant', const_type => 'integer', value => 99);

    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);
    my $phi        = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();

    my $code = $target->emit_cfg_phi_if($if_node, $phi);
    ok(defined $code, 'emit_cfg_phi_if returns code');
    like($code, qr/my\s+\$/, 'declares my variable for Phi');
    like($code, qr/if\s*\(/, 'contains if condition');
    like($code, qr/42/, 'true branch has value 42');
    like($code, qr/99/, 'false branch has value 99');
}

# --- Test 3: Loop subgraph emits Perl while loop ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start     = $factory->make('Start');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '$continue');

    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();

    my $code = $target->emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj, []);
    ok(defined $code, 'emit_cfg_loop returns code');
    like($code, qr/while\s*\(/, 'emitted code contains while');
}

done_testing();
