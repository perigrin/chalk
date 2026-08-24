# ABOUTME: Tests for TypedInvariant's control-chain leg (unbroken effect chain).
# ABOUTME: Verifies Print/Assign/Return/Call/Unwind nodes with undef control_in are flagged.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph::TypedInvariant;

# CC-1: a Print node with control_in set passes the invariant.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $msg = $f->make('Constant', value => 'hi', const_type => 'string');
    $msg->set_representation('Str');
    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$msg]);
    $print->set_control_in($start);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$start, $msg, $print]);
    ok($result->{ok}, 'Print with control_in set passes the control-chain leg');
    is(scalar @{ $result->{violations} }, 0,
        'no violations when Print is pinned to control');
}

# CC-2 (NOT VACUOUS): a Print node with undef control_in FAILS the invariant.
# This is the leg's core proof of life: an effectful node dropped off the
# control chain (the F3/F4 miscompile shape) must be reported, not waved
# through silently.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $msg = $f->make('Constant', value => 'hi', const_type => 'string');
    $msg->set_representation('Str');
    my $print = $f->make('Print', inputs => [$msg]);
    # No set_control_in call -- control_in stays undef.

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$msg, $print]);
    ok(!$result->{ok}, 'Print with undef control_in FAILS the control-chain leg');
    ok(scalar @{ $result->{violations} } > 0,
        'a violation is reported for the unpinned Print');
    my $v = $result->{violations}[0];
    ok(defined $v->{node_id}, 'violation has node_id');
    ok(defined $v->{message}, 'violation has message');
}

# CC-3: Assign with control_in set passes.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $target = $f->make('Constant', value => '0', const_type => 'integer');
    $target->set_representation('Int');
    my $value = $f->make('Constant', value => '1', const_type => 'integer');
    $value->set_representation('Int');
    my $start = $f->make_cfg('Start');
    my $assign = $f->make('Assign', inputs => [$target, $value]);
    $assign->set_control_in($start);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$start, $target, $value, $assign]);
    ok($result->{ok}, 'Assign with control_in set passes the control-chain leg');
}

# CC-4: Assign with undef control_in FAILS.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $target = $f->make('Constant', value => '0', const_type => 'integer');
    $target->set_representation('Int');
    my $value = $f->make('Constant', value => '1', const_type => 'integer');
    $value->set_representation('Int');
    my $assign = $f->make('Assign', inputs => [$target, $value]);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$target, $value, $assign]);
    ok(!$result->{ok}, 'Assign with undef control_in FAILS the control-chain leg');
    ok(scalar @{ $result->{violations} } > 0,
        'a violation is reported for the unpinned Assign');
}

# CC-5: Return with control_in set passes.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $value = $f->make('Constant', value => '1', const_type => 'integer');
    $value->set_representation('Int');
    my $start = $f->make_cfg('Start');
    my $ret = $f->make_cfg('Return', inputs => [$value]);
    $ret->set_control_in($start);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$start, $value, $ret]);
    ok($result->{ok}, 'Return with control_in set passes the control-chain leg');
}

# CC-6: Return with undef control_in FAILS.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $value = $f->make('Constant', value => '1', const_type => 'integer');
    $value->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$value]);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$value, $ret]);
    ok(!$result->{ok}, 'Return with undef control_in FAILS the control-chain leg');
    ok(scalar @{ $result->{violations} } > 0,
        'a violation is reported for the unpinned Return');
}

# CC-7: Call with control_in set passes.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $arg = $f->make('Constant', value => '1', const_type => 'integer');
    $arg->set_representation('Int');
    my $start = $f->make_cfg('Start');
    my $call = $f->make('Call', inputs => [$arg], dispatch_kind => 'direct', name => 'main::foo');
    $call->set_control_in($start);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$start, $arg, $call]);
    ok($result->{ok}, 'Call with control_in set passes the control-chain leg');
}

# CC-8: Call with undef control_in FAILS (the F3/F4 miscompile shape).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $arg = $f->make('Constant', value => '1', const_type => 'integer');
    $arg->set_representation('Int');
    my $call = $f->make('Call', inputs => [$arg], dispatch_kind => 'direct', name => 'main::foo');

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$arg, $call]);
    ok(!$result->{ok}, 'Call with undef control_in FAILS the control-chain leg');
    ok(scalar @{ $result->{violations} } > 0,
        'a violation is reported for the unpinned Call');
}

# CC-9: Unwind with control_in set passes.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $msg = $f->make('Constant', value => 'died', const_type => 'string');
    $msg->set_representation('Str');
    my $start = $f->make_cfg('Start');
    my $unwind = $f->make_cfg('Unwind', inputs => [$msg]);
    $unwind->set_control_in($start);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$start, $msg, $unwind]);
    ok($result->{ok}, 'Unwind with control_in set passes the control-chain leg');
}

# CC-10: Unwind with undef control_in FAILS.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $msg = $f->make('Constant', value => 'died', const_type => 'string');
    $msg->set_representation('Str');
    my $unwind = $f->make_cfg('Unwind', inputs => [$msg]);

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$msg, $unwind]);
    ok(!$result->{ok}, 'Unwind with undef control_in FAILS the control-chain leg');
    ok(scalar @{ $result->{violations} } > 0,
        'a violation is reported for the unpinned Unwind');
}

# CC-11: a bare RegexMatch with undef control_in does NOT trip the leg -- the
# match family is deliberately exempt (see TypedInvariant.pm comment).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $subject = $f->make('Constant', value => 'x', const_type => 'string');
    $subject->set_representation('Str');
    my $match = $f->make('RegexMatch', inputs => [$subject], pattern => 'x', flags => '');

    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$subject, $match]);
    ok($result->{ok}, 'RegexMatch with undef control_in is exempt from the control-chain leg');
}

done_testing;
