# ABOUTME: Tests for CFG subgraph patterns (if/else and while loop control flow)
# ABOUTME: Verifies that If/Region/Phi/Loop nodes compose into expected graph shapes
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::IR::NodeFactory;

# Test 1: If/Else Pattern - Build `if ($cond) { $x = 2 } else { $x = 3 }`
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Build: if ($cond) { $x = 2 } else { $x = 3 }
    my $start   = $factory->make('Start');
    my $cond    = $factory->make('Constant', const_type => 'integer', value => 1);
    my $val_a   = $factory->make('Constant', const_type => 'integer', value => 2);
    my $val_b   = $factory->make('Constant', const_type => 'integer', value => 3);

    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);
    my $phi        = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);
    my $return     = $factory->make('Return', value => $phi);

    # Verify graph shape
    is($if_node->inputs()->[0], $start, 'If controlled by Start');
    is($if_node->inputs()->[1], $cond, 'If condition is cond');
    is($true_proj->inputs()->[0], $if_node, 'TrueProj from If');
    is($false_proj->inputs()->[0], $if_node, 'FalseProj from If');
    is($region->inputs()->[0]->[0], $true_proj, 'Region control 0 is TrueProj');
    is($region->inputs()->[0]->[1], $false_proj, 'Region control 1 is FalseProj');
    is($phi->inputs()->[0], $region, 'Phi at Region merge');
    is($phi->inputs()->[1]->[0], $val_a, 'Phi value 0 is val_a');
    is($phi->inputs()->[1]->[1], $val_b, 'Phi value 1 is val_b');
    is($return->inputs()->[0], $phi, 'Return uses Phi result');

    # Verify use-def: If is consumer of Start and cond
    ok(scalar(grep { $_ == $if_node } $start->consumers()->@*), 'Start -> If');
    ok(scalar(grep { $_ == $if_node } $cond->consumers()->@*), 'cond -> If');

    # Verify use-def: Region is consumer of both projections
    ok(scalar(grep { $_ == $region } $true_proj->consumers()->@*), 'TrueProj -> Region');
    ok(scalar(grep { $_ == $region } $false_proj->consumers()->@*), 'FalseProj -> Region');

    # Verify use-def: Phi is consumer of both values
    ok(scalar(grep { $_ == $phi } $val_a->consumers()->@*), 'val_a -> Phi');
    ok(scalar(grep { $_ == $phi } $val_b->consumers()->@*), 'val_b -> Phi');

    # Verify use-def: Return is consumer of Phi
    ok(scalar(grep { $_ == $return } $phi->consumers()->@*), 'Phi -> Return');
}

# Test 2: While Loop Pattern - Build `while ($x < 10) { $x = $x + 1 }`
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $init_x   = $factory->make('Constant', const_type => 'integer', value => 0);
    my $limit    = $factory->make('Constant', const_type => 'integer', value => 10);
    my $one      = $factory->make('Constant', const_type => 'integer', value => 1);

    # Loop header: initially controlled by Start, backedge filled later
    my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);

    # Phi for loop counter: entry value is 0, backedge value filled later
    my $phi_x = $factory->make('Phi', region => $loop, values => [$init_x, undef]);

    # Condition: phi_x < 10
    my $less = $factory->make('Constructor', class => 'BinaryExpr',
        op => $factory->make('Constant', const_type => 'string', value => '<'),
        left => $phi_x, right => $limit);

    # If based on condition
    my $loop_if = $factory->make('If', control => $loop, condition => $less);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    # Body: phi_x + 1
    my $add = $factory->make('Constructor', class => 'BinaryExpr',
        op => $factory->make('Constant', const_type => 'string', value => '+'),
        left => $phi_x, right => $one);

    # Verify graph shape
    is($loop->inputs()->[0], $start, 'Loop entry from Start');
    ok(!defined $loop->inputs()->[1], 'Loop backedge initially undef');
    is($phi_x->inputs()->[0], $loop, 'Phi_x at Loop header');
    is($phi_x->inputs()->[1]->[0], $init_x, 'Phi_x entry value is 0');
    ok(!defined $phi_x->inputs()->[1]->[1], 'Phi_x backedge value initially undef');
    is($loop_if->inputs()->[0], $loop, 'If controlled by Loop');
    is($loop_if->inputs()->[1], $less, 'If condition is less-than comparison');
    is($body_proj->inputs()->[0], $loop_if, 'BodyProj from If');
    is($exit_proj->inputs()->[0], $loop_if, 'ExitProj from If');

    # Verify use-def: Loop is consumer of Start
    ok(scalar(grep { $_ == $loop } $start->consumers()->@*), 'Start -> Loop');

    # Verify use-def: Phi_x is consumer of init_x
    ok(scalar(grep { $_ == $phi_x } $init_x->consumers()->@*), 'init_x -> Phi_x');

    # Verify use-def: BinaryExpr consumers
    ok(scalar(grep { $_ == $less } $phi_x->consumers()->@*), 'Phi_x -> less');
    ok(scalar(grep { $_ == $less } $limit->consumers()->@*), 'limit -> less');
    ok(scalar(grep { $_ == $add } $phi_x->consumers()->@*), 'Phi_x -> add');
    ok(scalar(grep { $_ == $add } $one->consumers()->@*), 'one -> add');

    # Exit path: Region merges exit projection
    my $exit_region = $factory->make('Region', controls => [$exit_proj]);
    my $return = $factory->make('Return', value => $phi_x);

    is($exit_region->inputs()->[0]->[0], $exit_proj, 'Exit Region from ExitProj');
    is($return->inputs()->[0], $phi_x, 'Return uses phi_x');

    # Verify use-def: exit path consumers
    ok(scalar(grep { $_ == $exit_region } $exit_proj->consumers()->@*), 'ExitProj -> exit_region');
    ok(scalar(grep { $_ == $return } $phi_x->consumers()->@*), 'Phi_x -> Return');
}

done_testing();
