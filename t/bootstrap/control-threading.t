# ABOUTME: Control predecessor threading tests - verifies the during-parse lateral-seed channel.
# ABOUTME: With rebuild disabled, statement N+1 must see statement N as its control predecessor.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr blessed);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use TestPipeline qw(parse_perl_source);

# Parse a method body and return its IR statement nodes in source order.
sub method_body_stmts ($src) {
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    return unless defined $ctx;
    my ($cls) = grep { $_->name ne 'main' } $mop->classes;
    return unless defined $cls;
    my ($m) = $cls->methods;
    return unless defined $m && $m->can('body');
    my $body = $m->body;
    return unless ref($body) eq 'ARRAY';
    return grep { ref $_ } $body->@*;
}

my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        my $y = 2;
    }
}
PERL

# With the Block rebuild ACTIVE, the control chain is correct: statement 2's
# control input is statement 1's node. This is the chain any during-parse
# threading must reproduce (the Step A differential target).
{
    my @stmts = method_body_stmts($src);
    is(scalar(@stmts), 2, 'method body has two statements (rebuild active)');

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        is(
            refaddr($s2->control_in), refaddr($s1),
            'rebuild active: second statement control input is the first statement node'
        );
    }
}

# With the lateral-seed channel implemented, the second statement's control
# predecessor is the first statement (VarDecl), not the bare Start seed.
# This test confirms the channel is active (rebuild disabled).
{
    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 2, 'method body has two statements (rebuild disabled)');

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        my $ctrl2 = $s2->control_in;
        is(
            ( blessed($ctrl2) && $ctrl2->can('operation') ? $ctrl2->operation : 'undef' ),
            'VarDecl',
            'rebuild disabled: lateral-seed channel delivers VarDecl as second statement predecessor'
        );
    }
}

# Target 1 (capstone): during-parse lateral-seed channel. With the rebuild
# DISABLED, the during-parse control_head seeding at Earley prediction must
# deliver statement N's node as statement N+1's control predecessor. The
# lateral-seed channel — seeding predicted StatementItem items with the
# preceding statement's control_head from the completing StatementList —
# makes this possible without the post-parse rebuild.
{
    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        is(
            refaddr($s2->control_in), refaddr($s1),
            'target 1 (rebuild disabled): during-parse lateral seed delivers stmt1 as stmt2 control predecessor'
        );
    }
}

# Step (b): the side-effect statement actions must consume $ctx->control_head
# into their control input AT CONSTRUCTION, like VarDecl/Return/Unwind already
# do. This step does NOT fix cross-statement chaining (the lateral-seed gap) —
# it only makes the action READ whatever control_head is present at fire time.
#
# For a single statement-position Call whose predecessor IS Start (the seed),
# control_head is correct at construction, so the action — with the rebuild
# DISABLED — must set the Call's control_in to that Start. Today it is undef:
# the action layer is structurally incapable of consuming control. This test
# pins that the action now sets it on its own.
{
    my $single = <<'PERL';
class T {
    method m($self) {
        foo();
    }
}
PERL

    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($single);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 1, 'single side-effect statement (rebuild disabled)');

  SKIP: {
        skip 'parse did not yield one statement', 1 unless @stmts == 1;
        my ($call) = @stmts;
        my $ctrl = $call->can('control_in') ? $call->control_in : undef;
        is(
            ( blessed($ctrl) && $ctrl->can('operation') ? $ctrl->operation : 'undef' ),
            'Start',
            'rebuild disabled: statement-position Call consumes control_head (Start) at construction'
        );
    }
}

# Test 8: data-position (nested arg) Call must NOT carry control_in.
# With rebuild disabled, parse `bar(foo())`. The outer bar() Call is at
# statement position — its control_in must be Start. The inner foo() Call
# is in data position (an argument) — it must NOT receive control_in.
# Before the fix, _thread_control_head is called inside CallExpression,
# which fires for BOTH the outer and inner calls, so foo() incorrectly
# gets control_in=Start. This test pins that data-position calls stay undef.
{
    my $nested = <<'PERL';
class T {
    method m($self) {
        bar(foo());
    }
}
PERL

    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($nested);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 1, 'test 8: nested call: one statement (rebuild disabled)');

  SKIP: {
        skip 'parse did not yield one statement', 2 unless @stmts == 1;
        my ($outer) = @stmts;

        # Outer call (bar) is statement-position: must have control_in=Start
        my $outer_ctrl = $outer->can('control_in') ? $outer->control_in : undef;
        is(
            ( blessed($outer_ctrl) && $outer_ctrl->can('operation') ? $outer_ctrl->operation : 'undef' ),
            'Start',
            'test 8: outer statement-position Call (bar) has control_in=Start'
        );

        # Inner call (foo) is data-position (argument): must NOT have control_in
        # inputs->[1] is the args arrayref for a Call node
        my $args = $outer->inputs->[1];
        my $inner = ref($args) eq 'ARRAY' ? $args->[0] : undef;
        ok(
            defined($inner) && $inner->can('control_in') && !defined($inner->control_in),
            'test 8: inner data-position Call (foo) control_in is undef'
        );
    }
}

# Target 2 (if/else-join): with the rebuild DISABLED, the post-if Call's
# control_in must be the If's Region node (operation 'Region'), and the
# Return's control_in must be that Call. Verified by the spike (2026-06-04)
# to have a single determinate predecessor at the post-if frontier.
{
    my $ifelse_src = <<'PERL';
class T {
    method m($self) {
        if ($c) { $x = 1; } else { $x = 2; }
        foo();
        return $x;
    }
}
PERL

    # With rebuild ON: verify the expected chain holds (oracle).
    {
        my @stmts = method_body_stmts($ifelse_src);
        is(scalar(@stmts), 3, 'target 2 oracle: if/else method has three statements (rebuild on)');
      SKIP: {
            skip 'parse did not yield three statements', 2 unless @stmts == 3;
            my ($if_stmt, $foo_call, $ret) = @stmts;
            is(
                ( blessed($if_stmt) ? $if_stmt->operation : 'undef' ),
                'If',
                'target 2 oracle: first stmt is If (rebuild on)'
            );
            my $foo_ctrl = $foo_call->can('control_in') ? $foo_call->control_in : undef;
            is(
                ( blessed($foo_ctrl) && $foo_ctrl->can('operation') ? $foo_ctrl->operation : 'undef' ),
                'Region',
                'target 2 oracle: post-if foo() control_in is Region (rebuild on)'
            );
        }
    }

    # With rebuild OFF: the during-parse seed must deliver Region as the
    # control predecessor for the post-if Call, exactly as the rebuild does.
    {
        Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
        my @stmts = method_body_stmts($ifelse_src);
        Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

        is(scalar(@stmts), 3, 'target 2 (rebuild off): if/else method has three statements');
      SKIP: {
            skip 'parse did not yield three statements', 4 unless @stmts == 3;
            my ($if_stmt, $foo_call, $ret) = @stmts;

            # Post-if foo() call: control_in must be the Region (not Start).
            my $foo_ctrl = $foo_call->can('control_in') ? $foo_call->control_in : undef;
            is(
                ( blessed($foo_ctrl) && $foo_ctrl->can('operation') ? $foo_ctrl->operation : 'undef' ),
                'Region',
                'target 2 (rebuild off): post-if foo() control_in is Region from lateral seed'
            );

            # Return's control_in must be the foo() Call.
            my $ret_ctrl = $ret->can('control_in') ? $ret->control_in : undef;
            is(
                refaddr($ret_ctrl // 0), refaddr($foo_call),
                'target 2 (rebuild off): Return control_in is foo() Call'
            );

            # The Region id from the rebuild-off parse must match the Region id
            # from the rebuild-on parse (determinism: same position counter).
            my @on_stmts;
            {
                my @s = method_body_stmts($ifelse_src);
                @on_stmts = @s;
            }
            if (@on_stmts == 3) {
                my $on_foo_ctrl = $on_stmts[1]->can('control_in') ? $on_stmts[1]->control_in : undef;
                my $off_id = blessed($foo_ctrl) && $foo_ctrl->can('id') ? $foo_ctrl->id : '?';
                my $on_id  = blessed($on_foo_ctrl) && $on_foo_ctrl->can('id') ? $on_foo_ctrl->id : '??';
                is(
                    $off_id, $on_id,
                    'target 2: rebuild-off and rebuild-on Region have the same deterministic id'
                );
            } else {
                pass('target 2: rebuild-on parse skipped (not 3 stmts)');
            }
        }
    }
}

# Target 3 (falsification guard): two back-to-back if/else blocks each
# followed by a call must give DISTINCT Region predecessors (Region for
# first if/else != Region for second if/else). This catches the collision
# scenario the spike characterised as GREEN (per-position counter ids ensure
# distinct Regions). Also verifies parse determinism: two parses of the same
# source give byte-identical control chains (same refaddrs within one parse,
# same operations across parses).
{
    my $two_ifelse_src = <<'PERL';
class T {
    method m($self) {
        if ($c) { $x = 1; } else { $x = 2; }
        foo();
        if ($d) { $y = 3; } else { $y = 4; }
        bar();
    }
}
PERL

    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($two_ifelse_src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 4, 'target 3: two if/else blocks yield four statements (rebuild off)');
  SKIP: {
        skip 'parse did not yield four statements', 3 unless @stmts == 4;
        my ($if1, $foo_call, $if2, $bar_call) = @stmts;

        my $foo_ctrl = $foo_call->can('control_in') ? $foo_call->control_in : undef;
        my $bar_ctrl = $bar_call->can('control_in') ? $bar_call->control_in : undef;

        # Both post-if calls must have a Region as their control predecessor.
        is(
            ( blessed($foo_ctrl) && $foo_ctrl->can('operation') ? $foo_ctrl->operation : 'undef' ),
            'Region',
            'target 3: post-first-if foo() control_in is Region'
        );
        is(
            ( blessed($bar_ctrl) && $bar_ctrl->can('operation') ? $bar_ctrl->operation : 'undef' ),
            'Region',
            'target 3: post-second-if bar() control_in is Region'
        );

        # The two Regions must be distinct nodes (different ids / different refaddrs).
        my $foo_region_id = blessed($foo_ctrl) ? $foo_ctrl->id : undef;
        my $bar_region_id = blessed($bar_ctrl) ? $bar_ctrl->id : undef;
        isnt(
            $foo_region_id, $bar_region_id,
            'target 3: the two if/else Regions are distinct nodes'
        );
    }
}

# Target 4 (inner-block-tail-leak: if with body): with rebuild DISABLED,
# the If node's own control_in must be the VarDecl (the statement BEFORE the
# if), NOT any node produced inside the if body. The inner body's
# update_control_head calls must not escape the block to pollute the
# enclosing chain. Also assert the guard: bar()'s control_in is the If's
# Region (already correct per target 2; kept here as a regression guard).
{
    my $if_body_src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        if ($c) { qux(); }
        bar();
    }
}
PERL

    # Oracle (rebuild ON): If's control_in must be the VarDecl.
    {
        my @stmts = method_body_stmts($if_body_src);
        is(scalar(@stmts), 3, 'target 4 oracle: if-with-body method has three statements (rebuild on)');
      SKIP: {
            skip 'parse did not yield three statements', 1 unless @stmts == 3;
            my ($vardecl, $if_stmt, $bar_call) = @stmts;
            is(
                refaddr($if_stmt->control_in // 0), refaddr($vardecl),
                'target 4 oracle: If control_in is VarDecl (rebuild on)'
            );
        }
    }

    # Rebuild OFF: inner body must NOT leak its control_head out.
    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($if_body_src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 3, 'target 4: if-with-body method has three statements (rebuild off)');
  SKIP: {
        skip 'parse did not yield three statements', 3 unless @stmts == 3;
        my ($vardecl, $if_stmt, $bar_call) = @stmts;

        # If's own control_in must be the VarDecl, not the inner qux() Call.
        is(
            refaddr($if_stmt->control_in // 0), refaddr($vardecl),
            'target 4 (rebuild off): If control_in is VarDecl, not inner body tail'
        );

        # Guard: bar()'s control_in must be the If's Region (not the If node itself).
        my $bar_ctrl = $bar_call->can('control_in') ? $bar_call->control_in : undef;
        is(
            ( blessed($bar_ctrl) && $bar_ctrl->can('operation') ? $bar_ctrl->operation : 'undef' ),
            'Region',
            'target 4 (rebuild off): post-if bar() control_in is Region (guard)'
        );

        # ON vs OFF: the If node's control_in must be the same operation in both modes.
        {
            my @on_stmts = method_body_stmts($if_body_src);
            if (@on_stmts == 3) {
                my $on_if_ctrl  = $on_stmts[1]->control_in;
                my $off_if_ctrl = $if_stmt->control_in;
                is(
                    ( blessed($off_if_ctrl) ? $off_if_ctrl->operation : 'undef' ),
                    ( blessed($on_if_ctrl)  ? $on_if_ctrl->operation  : 'undef' ),
                    'target 4: ON-vs-OFF: If control_in operation is identical'
                );
            } else {
                pass('target 4: ON parse skipped (not 3 stmts)');
            }
        }
    }
}

# Target 5 (inner-block-tail-leak: loop with body): with rebuild DISABLED,
# the Loop node's own control_in (entry_ctrl) must be the VarDecl (the
# statement before the while), NOT any node produced inside the loop body.
{
    my $loop_body_src = <<'PERL';
class T {
    method m($self) {
        my $x = 0;
        while ($c) { $x = $x + 1; }
        foo();
        return $x;
    }
}
PERL

    # Oracle (rebuild ON): Loop's entry_ctrl must be the VarDecl.
    {
        my @stmts = method_body_stmts($loop_body_src);
        is(scalar(@stmts), 4, 'target 5 oracle: loop-with-body method has four statements (rebuild on)');
      SKIP: {
            skip 'parse did not yield four statements', 1 unless @stmts == 4;
            my ($vardecl, $loop_stmt, $foo_call, $ret) = @stmts;
            is(
                refaddr($loop_stmt->control_in // 0), refaddr($vardecl),
                'target 5 oracle: Loop control_in is VarDecl (rebuild on)'
            );
        }
    }

    # Rebuild OFF: loop body must NOT leak its control_head out.
    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($loop_body_src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 4, 'target 5: loop-with-body method has four statements (rebuild off)');
  SKIP: {
        skip 'parse did not yield four statements', 3 unless @stmts == 4;
        my ($vardecl, $loop_stmt, $foo_call, $ret) = @stmts;

        # Loop's own control_in must be the VarDecl, not the inner body Assign.
        is(
            refaddr($loop_stmt->control_in // 0), refaddr($vardecl),
            'target 5 (rebuild off): Loop control_in is VarDecl, not inner body tail'
        );

        # Guard: foo()'s control_in must be the Region (not the Loop node itself).
        my $foo_ctrl = $foo_call->can('control_in') ? $foo_call->control_in : undef;
        is(
            ( blessed($foo_ctrl) && $foo_ctrl->can('operation') ? $foo_ctrl->operation : 'undef' ),
            'Region',
            'target 5 (rebuild off): post-loop foo() control_in is Region (guard)'
        );

        # ON vs OFF: Loop's control_in operation must match.
        {
            my @on_stmts = method_body_stmts($loop_body_src);
            if (@on_stmts == 4) {
                my $on_loop_ctrl  = $on_stmts[1]->control_in;
                my $off_loop_ctrl = $loop_stmt->control_in;
                is(
                    ( blessed($off_loop_ctrl) ? $off_loop_ctrl->operation : 'undef' ),
                    ( blessed($on_loop_ctrl)  ? $on_loop_ctrl->operation  : 'undef' ),
                    'target 5: ON-vs-OFF: Loop control_in operation is identical'
                );
            } else {
                pass('target 5: ON parse skipped (not 4 stmts)');
            }
        }
    }
}

# ON==OFF equivalence suite: for each of the 6 canonical shapes, parse once
# with rebuild ENABLED (oracle) and once with rebuild DISABLED. Extract the
# control_in chain (op names in source order) and assert they are byte-identical.
# This is the precondition for eventually deleting the Block rebuild: the during-
# parse channel must produce the SAME chain as the rebuild, for every shape.
{
    # Helper: parse src with rebuild state, return arrayref of
    # { op, ctrl_op } records for each method-body statement (in source order).
    my sub chain_for ($src, $rebuild_enabled) {
        Chalk::Bootstrap::Perl::Actions->disable_control_rebuild unless $rebuild_enabled;
        my @stmts = method_body_stmts($src);
        Chalk::Bootstrap::Perl::Actions->enable_control_rebuild unless $rebuild_enabled;
        my @chain;
        for my $s (@stmts) {
            my $op   = blessed($s) && $s->can('operation') ? $s->operation : ref($s) || '?';
            my $ctrl = $s->can('control_in') ? $s->control_in : undef;
            my $ctrl_op = defined($ctrl) ? (blessed($ctrl) && $ctrl->can('operation')
                ? $ctrl->operation : 'scalar') : 'undef';
            push @chain, "$op<=$ctrl_op";
        }
        return join(',', @chain);
    }

    # shape 1: flat vardecl-seq
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        my $a = 1;
        my $b = 2;
        my $c = 3;
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 1: flat vardecl-seq');
    }

    # shape 2: mixed (vardecl then call then return)
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        foo();
        return $x;
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 2: mixed (vardecl, call, return)');
    }

    # shape 3: call-seq (pure calls, no vardecl)
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        foo();
        bar();
        baz();
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 3: call-seq (pure calls)');
    }

    # shape 4: loop (vardecl + while + call + return)
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 0;
        while ($c) { $x = $x + 1; }
        foo();
        return $x;
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 4: loop (vardecl + while + call + return)');
    }

    # shape 5: nested-block (if containing if, followed by call)
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        if ($c) { if ($d) { qux(); } }
        bar();
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 5: nested-block (if inside if, then call)');
    }

    # shape 6: if/else-join (if with else, followed by call and return)
    {
        my $src = <<'PERL';
class T {
    method m($self) {
        if ($c) { $x = 1; } else { $x = 2; }
        foo();
        return $x;
    }
}
PERL
        my $on  = chain_for($src, 1);
        my $off = chain_for($src, 0);
        is($off, $on, 'ON==OFF shape 6: if/else-join (if/else then call and return)');
    }
}

done_testing;
