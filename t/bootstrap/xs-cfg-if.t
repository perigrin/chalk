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
    # With true_stmts and false_stmts both populated, else block should appear
    my $then_node = $factory->make('Constant', const_type => 'string', value => 'then_val');
    my $else_node = $factory->make('Constant', const_type => 'string', value => 'else_val');
    my $code = $target->emit_cfg_if($if_node, $true_proj, $false_proj, {},
        [$then_node], [$else_node]);
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

# --- Test 4: XS foreach loop emits C-style AV iteration, not Perl syntax ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $loop  = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    my $iterator = $factory->make('Constant', const_type => 'string', value => '$x');
    my $list_items = [
        $factory->make('Constant', const_type => 'integer', value => 1),
        $factory->make('Constant', const_type => 'integer', value => 2),
        $factory->make('Constant', const_type => 'integer', value => 3),
    ];

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgForeach');
    my $code = $target->emit_cfg_loop(
        $loop, $loop_if, $body_proj, $exit_proj, {},
        [], $iterator, $list_items,
    );
    ok(defined $code, 'XS emit_cfg_loop with iterator/list returns code');
    unlike($code, qr/for my/, 'XS foreach does NOT emit Perl syntax');
    like($code, qr/av_fetch|av_len|for\s*\(/, 'XS foreach emits C-style iteration');
}

# --- Test 5: XS foreach with single node (variable) emits AV iteration ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $loop  = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    my $iterator = $factory->make('Constant', const_type => 'string', value => '$item');
    my $list_node = $factory->make('Constant', const_type => 'string', value => '@array');

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgForeachVar');
    my $code = $target->emit_cfg_loop(
        $loop, $loop_if, $body_proj, $exit_proj, {},
        [], $iterator, $list_node,
    );
    ok(defined $code, 'XS emit_cfg_loop with variable list returns code');
    unlike($code, qr/for my/, 'XS foreach with variable does NOT emit Perl syntax');
    like($code, qr/av_fetch|av_len/, 'XS foreach with variable uses AV API');
}

# --- Test 6: XS foreach literal list uses sv_2mortal for exception safety ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $loop  = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    my $iterator = $factory->make('Constant', const_type => 'string', value => '$x');
    my $list_items = [
        $factory->make('Constant', const_type => 'integer', value => 1),
    ];

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgMortal');
    my $code = $target->emit_cfg_loop(
        $loop, $loop_if, $body_proj, $exit_proj, {},
        [], $iterator, $list_items,
    );
    # The temp AV itself must be mortalized for exception safety
    like($code, qr/sv_2mortal\(\(SV\*\)newAV\(\)\)/, 'XS literal list foreach mortalizes temp AV');
}

# --- Test 7: XS foreach variable list guards with SvROK ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $loop  = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    my $iterator = $factory->make('Constant', const_type => 'string', value => '$item');
    my $list_node = $factory->make('Constant', const_type => 'string', value => '@array');

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgROK');
    my $code = $target->emit_cfg_loop(
        $loop, $loop_if, $body_proj, $exit_proj, {},
        [], $iterator, $list_node,
    );
    like($code, qr/SvROK/, 'XS variable list foreach guards with SvROK check');
}

# --- Test 8: XS emit_cfg_if elsif chain emits } else if (not nested) ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond1 = $factory->make('Constant', const_type => 'string', value => 'cond1_sv');
    my $cond2 = $factory->make('Constant', const_type => 'string', value => 'cond2_sv');

    # Outer if
    my $outer_if   = $factory->make('If', control => $start, condition => $cond1);
    my $outer_true = $factory->make('Proj', source => $outer_if, index => 0);
    my $outer_false = $factory->make('Proj', source => $outer_if, index => 1);

    # Inner if (elsif branch)
    my $inner_if   = $factory->make('If', control => $outer_false, condition => $cond2);
    my $inner_true = $factory->make('Proj', source => $inner_if, index => 0);
    my $inner_false = $factory->make('Proj', source => $inner_if, index => 1);

    my $then1 = $factory->make('Constant', const_type => 'string', value => 'then1_val');
    my $then2 = $factory->make('Constant', const_type => 'string', value => 'then2_val');
    my $else_val = $factory->make('Constant', const_type => 'string', value => 'else_val');

    # Set up cfg_lookup so elsif detection finds inner_if
    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CfgElsif');

    # Populate cfg_lookup by calling _build_cfg_lookup with a mock SemanticAction
    # Instead, directly call emit_cfg_if with inner If as false_stmts
    # and register it in cfg_lookup via the target's internal hash
    # We need to use the target's emit_cfg_if — but elsif detection requires cfg_lookup.
    # For a unit test, just test the prefix parameter directly:
    my $code = $target->emit_cfg_if(
        $inner_if, $inner_true, $inner_false, {},
        [$then2], [$else_val],
        '} else if',
    );
    ok(defined $code, 'XS emit_cfg_if with elsif prefix returns code');
    like($code, qr/^\}\s*else\s*if\s*\(SvTRUE/, 'XS elsif starts with } else if');
    like($code, qr/else\s*\{/, 'XS elsif chain has final else');
}

# --- Test 9: emit_cfg_loop body stmts pass is_last=false for return ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start     = $factory->make('Start');
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => 'cond_sv');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

    # Body contains a ReturnStmt — must emit 'goto xsreturn' (is_last=false)
    my $ret_val  = $factory->make('Constant', const_type => 'integer', value => 42);
    my $ret_stmt = $factory->make('Constructor',
        'class' => 'ReturnStmt',
        value   => $ret_val,
    );

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::LoopReturn');
    my $code = $target->emit_cfg_loop(
        $loop, $loop_if, $body_proj, $exit_proj, {},
        [$ret_stmt],
    );
    ok(defined $code, 'emit_cfg_loop with return in body produces code');
    like($code, qr/goto xsreturn/, 'return inside loop body emits goto xsreturn');
}

# --- Test: loop_jump emits C continue statement ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    # Condition: !($x > 0) — PostfixModifier negated for 'unless'
    my $x_var = $factory->make('Constant', const_type => 'string', value => '$x');
    my $zero  = $factory->make('Constant', const_type => 'integer', value => 0);
    my $gt_op = $factory->make('Constant', const_type => 'string', value => '>');
    my $gt_expr = $factory->make('Constructor',
        'class' => 'BinaryExpr',
        op    => $gt_op,
        left  => $x_var,
        right => $zero,
    );
    my $not_op = $factory->make('Constant', const_type => 'string', value => '!');
    my $negated = $factory->make('Constructor',
        'class'  => 'UnaryExpr',
        op       => $not_op,
        operand  => $gt_expr,
    );

    my $if_node    = $factory->make('If', control => $start, condition => $negated);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::LoopJump');

    # Simulate cfg_state with loop_jump by calling _emit_xs_loop_jump
    my $code = $target->_emit_xs_loop_jump('next', $if_node, {});
    ok(defined $code, 'XS loop_jump next produces code');
    like($code, qr/continue/, 'XS loop_jump next emits continue');
    like($code, qr/SvTRUE/, 'XS loop_jump next tests condition with SvTRUE');

    # Verify 'last' maps to C 'break'
    my $code_last = $target->_emit_xs_loop_jump('last', $if_node, {});
    ok(defined $code_last, 'XS loop_jump last produces code');
    like($code_last, qr/break/, 'XS loop_jump last emits break');
    unlike($code_last, qr/continue/, 'XS loop_jump last does NOT emit continue');
}

# --- Test: av_fetch with lval=1 for array subscript ---
# av_fetch with lval=1 auto-vivifies missing slots, making it safe for
# both read and write (assignment target) contexts.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Build: SubscriptExpr($arr, $idx, 'array')
    my $arr = $factory->make('Constant', const_type => 'string', value => 'arr_sv');
    my $idx = $factory->make('Constant', const_type => 'string', value => 'idx_sv');
    my $subscript = $factory->make('Constructor',
        'class' => 'SubscriptExpr',
        target  => $arr,
        index   => $idx,
        style   => $factory->make('Constant', const_type => 'string', value => 'array'),
    );

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::AvGuard');
    my $code = $target->_emit_xs_expr($subscript, {});
    ok(defined $code, 'array subscript emits code');
    # Must use lval=1 to auto-vivify missing slots (safe for assignment targets)
    like($code, qr/av_fetch\([^,]+,[^,]+,\s*1\)/, 'array subscript uses lval=1 for auto-vivification');
}

done_testing();
