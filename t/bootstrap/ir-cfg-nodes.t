# ABOUTME: Tests for CFG IR nodes - If, Proj, Region, Phi, Loop
# ABOUTME: Verifies control flow graph construction with hash consing
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Test 1: Create If node with control and condition inputs
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');

    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    is($if_node->operation(), 'If', 'If node has correct operation');
    is(scalar($if_node->inputs()->@*), 2, 'If node has 2 inputs');
    is($if_node->inputs()->[0], $start, 'If control input is start node');
    is($if_node->inputs()->[1], $cond, 'If condition input is condition node');
}

# Test 2: If node appears in consumers of its inputs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');

    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    is(scalar($start->consumers()->@*), 1, 'start has 1 consumer');
    is($start->consumers()->[0], $if_node, 'start consumer is if node');
    is(scalar($cond->consumers()->@*), 1, 'condition has 1 consumer');
    is($cond->consumers()->[0], $if_node, 'condition consumer is if node');
}

# Test 3: Create Proj node with source input and index attribute
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    my $proj_true = $factory->make('Proj',
        source => $if_node,
        index => 0
    );

    is($proj_true->operation(), 'Proj', 'Proj node has correct operation');
    is(scalar($proj_true->inputs()->@*), 1, 'Proj node has 1 input');
    is($proj_true->inputs()->[0], $if_node, 'Proj source input is if node');
}

# Test 4: Proj nodes with different indices are different
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    my $proj_0 = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_1 = $factory->make('Proj', source => $if_node, index => 1);

    isnt($proj_0, $proj_1, 'Proj nodes with different indices are different');
    isnt(refaddr($proj_0), refaddr($proj_1), 'Proj reference addresses differ');
}

# Test 5: Proj nodes with same source and index are distinct (CFG nodes not hash-consed)
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    my $proj_a = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_b = $factory->make('Proj', source => $if_node, index => 0);

    isnt(refaddr($proj_a), refaddr($proj_b), 'Proj nodes with same inputs are distinct');
    is($proj_a->operation(), 'Proj', 'first Proj has correct operation');
}

# Test 6: Create Region node with array of control inputs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );

    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);

    my $region = $factory->make('Region',
        controls => [$proj_true, $proj_false]
    );

    is($region->operation(), 'Region', 'Region node has correct operation');
    is(scalar($region->inputs()->@*), 1, 'Region has 1 input (the controls array)');
    is(ref($region->inputs()->[0]), 'ARRAY', 'Region input is an array');
    is(scalar($region->inputs()->[0]->@*), 2, 'Region controls array has 2 elements');
    is($region->inputs()->[0]->[0], $proj_true, 'Region first control is proj_true');
    is($region->inputs()->[0]->[1], $proj_false, 'Region second control is proj_false');
}

# Test 7: Region node appears in consumers of its control inputs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If',
        control => $start,
        condition => $cond
    );
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);

    my $region = $factory->make('Region',
        controls => [$proj_true, $proj_false]
    );

    is(scalar($proj_true->consumers()->@*), 1, 'proj_true has 1 consumer');
    is($proj_true->consumers()->[0], $region, 'proj_true consumer is region');
    is(scalar($proj_false->consumers()->@*), 1, 'proj_false has 1 consumer');
    is($proj_false->consumers()->[0], $region, 'proj_false consumer is region');
}

# Test 8: Region nodes with same controls are distinct (CFG nodes not hash-consed)
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);

    my $region_a = $factory->make('Region', controls => [$proj_true, $proj_false]);
    my $region_b = $factory->make('Region', controls => [$proj_true, $proj_false]);

    isnt(refaddr($region_a), refaddr($region_b), 'Region nodes with same controls are distinct');
    is($region_a->operation(), 'Region', 'first Region has correct operation');
}

# Test 9: Create Phi node with region and values array
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$proj_true, $proj_false]);

    my $val_1 = $factory->make('Constant', const_type => 'int', value => '1');
    my $val_2 = $factory->make('Constant', const_type => 'int', value => '2');

    my $phi = $factory->make('Phi',
        region => $region,
        values => [$val_1, $val_2]
    );

    is($phi->operation(), 'Phi', 'Phi node has correct operation');
    is(scalar($phi->inputs()->@*), 2, 'Phi has 2 value inputs');
    is($phi->region(), $region, 'Phi region() is the region node');
    is($phi->inputs()->[0], $val_1, 'Phi first value is val_1');
    is($phi->inputs()->[1], $val_2, 'Phi second value is val_2');
}

# Test 10: Phi node appears in consumers of region and values
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$proj_true, $proj_false]);

    my $val_1 = $factory->make('Constant', const_type => 'int', value => '1');
    my $val_2 = $factory->make('Constant', const_type => 'int', value => '2');

    my $phi = $factory->make('Phi',
        region => $region,
        values => [$val_1, $val_2]
    );

    is(scalar($region->consumers()->@*), 1, 'region has 1 consumer');
    is($region->consumers()->[0], $phi, 'region consumer is phi');
    is(scalar($val_1->consumers()->@*), 1, 'val_1 has 1 consumer');
    is($val_1->consumers()->[0], $phi, 'val_1 consumer is phi');
    is(scalar($val_2->consumers()->@*), 1, 'val_2 has 1 consumer');
    is($val_2->consumers()->[0], $phi, 'val_2 consumer is phi');
}

# Test 11: Phi nodes with same inputs are distinct (CFG nodes not hash-consed)
# CFG nodes represent control flow positions, not data values, so each
# creation site must produce a unique node for cfg_state mapping.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);
    my $region = $factory->make('Region', controls => [$proj_true, $proj_false]);

    my $val_1 = $factory->make('Constant', const_type => 'int', value => '1');
    my $val_2 = $factory->make('Constant', const_type => 'int', value => '2');

    my $phi_a = $factory->make('Phi', region => $region, values => [$val_1, $val_2]);
    my $phi_b = $factory->make('Phi', region => $region, values => [$val_1, $val_2]);

    isnt(refaddr($phi_a), refaddr($phi_b), 'Phi nodes with same inputs are distinct');
    is($phi_a->operation(), 'Phi', 'first Phi has correct operation');
    is($phi_b->operation(), 'Phi', 'second Phi has correct operation');
}

# Test 12: Create Loop node with entry and backedge controls
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $backedge = $factory->make('Constant', const_type => 'control', value => 'placeholder');

    my $loop = $factory->make('Loop',
        entry_ctrl => $start,
        backedge_ctrl => $backedge
    );

    is($loop->operation(), 'Loop', 'Loop node has correct operation');
    is(scalar($loop->inputs()->@*), 2, 'Loop has 2 inputs');
    is($loop->inputs()->[0], $start, 'Loop first input is entry control');
    is($loop->inputs()->[1], $backedge, 'Loop second input is backedge control');
}

# Test 13: Loop node appears in consumers of its inputs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $backedge = $factory->make('Constant', const_type => 'control', value => 'placeholder');

    my $loop = $factory->make('Loop',
        entry_ctrl => $start,
        backedge_ctrl => $backedge
    );

    is(scalar($start->consumers()->@*), 1, 'entry control has 1 consumer');
    is($start->consumers()->[0], $loop, 'entry control consumer is loop');
    is(scalar($backedge->consumers()->@*), 1, 'backedge control has 1 consumer');
    is($backedge->consumers()->[0], $loop, 'backedge control consumer is loop');
}

# Test 14: Loop nodes with same inputs are distinct (CFG nodes not hash-consed)
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $start = $factory->make('Start');
    my $backedge = $factory->make('Constant', const_type => 'control', value => 'placeholder');

    my $loop_a = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => $backedge);
    my $loop_b = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => $backedge);

    isnt(refaddr($loop_a), refaddr($loop_b), 'Loop nodes with same inputs are distinct');
    is($loop_a->operation(), 'Loop', 'first Loop has correct operation');
    is($loop_b->operation(), 'Loop', 'second Loop has correct operation');
}

# Test 15: Complete if-then-else pattern with Region and Phi
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Entry control
    my $start = $factory->make('Start');

    # Condition
    my $cond = $factory->make('Constant', const_type => 'bool', value => 'true');

    # If node
    my $if_node = $factory->make('If', control => $start, condition => $cond);

    # True and false branches
    my $proj_true = $factory->make('Proj', source => $if_node, index => 0);
    my $proj_false = $factory->make('Proj', source => $if_node, index => 1);

    # Values produced on each branch
    my $then_val = $factory->make('Constant', const_type => 'int', value => '42');
    my $else_val = $factory->make('Constant', const_type => 'int', value => '99');

    # Merge point
    my $region = $factory->make('Region', controls => [$proj_true, $proj_false]);

    # Select value based on which branch taken
    my $phi = $factory->make('Phi', region => $region, values => [$then_val, $else_val]);

    # Return result
    my $ret = $factory->make('Return', value => $phi);

    is($ret->operation(), 'Return', 'complete pattern has Return node');
    is($ret->inputs()->[0], $phi, 'Return value is Phi node');
    is($phi->region(), $region, 'Phi region is Region node');
    is($region->inputs()->[0]->[0], $proj_true, 'Region first control is true branch');
    is($region->inputs()->[0]->[1], $proj_false, 'Region second control is false branch');
}

done_testing;
