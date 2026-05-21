# ABOUTME: Tests Phi and Loop backedge mutation — the only mutable operations in the IR
# ABOUTME: Verifies set_backedge on Phi and set_backedge_ctrl on Loop wire correctly
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;

my $factory = Chalk::IR::NodeFactory->new();

# --- Phi set_backedge ---
{
    my $start = $factory->make('Start');
    my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $pre_value = $factory->make('Constant', const_type => 'integer', value => '0');
    my $phi = $factory->make('Phi', region => $loop, values => [$pre_value, undef]);

    # Before wiring: backedge is undef
    ok(!defined $phi->inputs()->[1], 'Phi backedge starts as undef');

    # Wire backedge
    my $backedge_value = $factory->make('Constant', const_type => 'integer', value => '1');
    $phi->set_backedge($backedge_value);

    is($phi->inputs()->[1], $backedge_value, 'Phi backedge wired to value');
    is($phi->inputs()->[0], $pre_value, 'Phi pre-value unchanged');
    is($phi->region(), $loop, 'Phi region unchanged');
}

# --- Loop set_backedge_ctrl ---
{
    my $start = $factory->make('Start');
    my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);

    # Before wiring: backedge_ctrl is undef
    is($loop->inputs()->[1], undef, 'Loop backedge_ctrl starts as undef');

    # Wire backedge control
    my $body_ctrl = $factory->make('Region', controls => [$start]);
    $loop->set_backedge_ctrl($body_ctrl);

    is($loop->inputs()->[1], $body_ctrl, 'Loop backedge_ctrl wired');
    is($loop->inputs()->[0], $start, 'Loop entry_ctrl unchanged');
}

done_testing();
