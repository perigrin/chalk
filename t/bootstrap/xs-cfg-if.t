# ABOUTME: Tests XS target emission for If/Region/Phi CFG node subgraphs.
# ABOUTME: Verifies C code output contains correct if/else structure with Phi variables.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::XS;

# --- Test 1: If/Region subgraph emits C if/else ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Build: if ($cond) { then_stmts } else { else_stmts }
    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'string', value => 'cond_sv');

    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    # Create a target with a dummy module name
    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgIf');

    # Test that the target can emit code for an If node
    my $code = $target->emit_cfg_if($if_node, $true_proj, $false_proj, {});
    ok(defined $code, 'emit_cfg_if returns code');
    like($code, qr/if\s*\(SvTRUE/, 'emitted code contains SvTRUE condition');
    like($code, qr/\}\s*else\s*\{/, 'emitted code contains else branch');
}

# --- Test 2: Phi node emits C variable declaration before if ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'string', value => 'cond_sv');
    my $val_a = $factory->make('Constant', const_type => 'integer', value => 2);
    my $val_b = $factory->make('Constant', const_type => 'integer', value => 3);

    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);
    my $phi        = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgPhi');

    my $code = $target->emit_cfg_phi_if($if_node, $phi, {});
    ok(defined $code, 'emit_cfg_phi_if returns code');
    like($code, qr/SV\s*\*/, 'declares SV* variable for Phi');
    like($code, qr/if\s*\(SvTRUE/, 'contains if condition');
    # Phi variable assigned in both branches
    like($code, qr/newSViv\(2\)/, 'true branch assigns value 2');
    like($code, qr/newSViv\(3\)/, 'false branch assigns value 3');
}

# --- Test 3: Loop/Phi subgraph emits C for loop ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start    = $factory->make('Start');
    my $loop     = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');

    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);
    my $region    = $factory->make('Region', controls => [$exit_proj]);

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgLoop');

    my $code = $target->emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj, {});
    ok(defined $code, 'emit_cfg_loop returns code');
    like($code, qr/while|for/, 'emitted code contains loop construct');
}

done_testing();
