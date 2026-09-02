# ABOUTME: Proves _mut_read_memo (Context.pm _reads_mutable_location) is keyed by
# ABOUTME: node string id, so cross-graph inlining can collide a caller mutable-read
# ABOUTME: with a callee pure node sharing that id, mis-serving a stale cached value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Return;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# A direct Call carries its callee METAOBJECT (step 1d), not a bare graph --
# the backend reads target->graph.
sub mk_target {
    my ($graph) = @_;
    require Chalk::MOP;
    my $mop = Chalk::MOP->new;
    return $mop->for_class('main')->declare_sub('f', graph => $graph);
}

# Print the returned value on stdout, bracketed, instead of relying on a
# type-tag epilogue: rebuild the Return so the value flows through
# Coerce->Str into Prints hung off the graph's existing control chain.
# Three Prints (not a Concat) because Concat needs tracked lengths on both
# operands, which a Coerce'd Int does not have.
sub print_returned_value {
    my ($f, $ret_node) = @_;

    my $v = $ret_node->inputs->[0];
    my $s = $v;
    if (($v->representation // '') ne 'Str') {
        $s = $f->make('Coerce', inputs => [$v],
            from_repr => $v->representation, to_repr => 'Str');
        $s->set_representation('Str');
    }

    my $open = $f->make('Constant', value => '[', const_type => 'string');
    $open->set_representation('Str');
    my $close = $f->make('Constant', value => "]\n", const_type => 'string');
    $close->set_representation('Str');

    my $ctrl = $ret_node->control_in // $f->make_cfg('Start');
    for my $part ($open, $s, $close) {
        my $p = $f->make('Print', inputs => [$part]);
        $p->set_control_in($ctrl);
        $ctrl = $p;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_representation('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}


sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# The bug (git-zhi 019fbe27): _reads_mutable_location memoizes its answer in
# $self->{_mut_read_memo}{$id}, keyed by the node's STRING id (Context.pm
# ~276-303). Cross-graph inlining (_lower_call_direct) lowers a CALLEE
# graph's nodes in the CALLER's Context. Each graph numbers/hashes its own
# nodes independently, so a callee PURE node can collide, by id, with an
# unrelated caller MUTABLE-READ node. Whichever is classified first wins the
# memo entry for that id -- forever, for the rest of this lowering.
#
# The memo is only ever CONSULTED (and thus only ever populated) from
# lower_value's cache-gated check (Context.pm ~353: `exists cache{$id} &&
# !_reads_mutable_location($node)`) -- short-circuit evaluation means
# _reads_mutable_location never runs on a node's FIRST lowering (no cache
# entry yet to gate). So the collision needs the callee's pure node looked
# up via lower_value TWICE within the callee's own subgraph (e.g. a shared
# subexpression `$a - $a`) to force the cache-gated memo check to actually
# run and memoize PURE (0) under the colliding id.
#
# Scenario: `sub f { my $a = 1 + 2; $a - $a } my $x = 1; f(); $x = 2;
# return $x;` where f() is inlined. Its inner `1+2` Add is hand-forced to
# the SAME string id as the caller's PadAccess($x) node, and referenced
# twice (Subtract(add,add)) so the memo gets populated PURE for that id
# during the inline -- BEFORE the caller's own PadAccess is ever consulted.
# Per program order:
#   my $x = 1;      -- VarDecl, var_table{x}=1
#   f();            -- inlined call; the callee's doubly-referenced Add is
#                      cached, THEN its second lookup runs
#                      _reads_mutable_location and memoizes 0 (pure) under
#                      the COLLIDING id -- poisoning it before the caller
#                      ever asks
#   $x = 2;         -- Assign updates var_table{x}=2 (NOT cache{collision_id})
#   return $x;      -- PadAccess($x), SAME colliding id, and the callee's Add
#                      is ALSO still in {cache} under that id (from the
#                      inline). lower_value's cache check sees cache_exists=1
#                      AND the POISONED memo (0/pure), so it wrongly serves
#                      the callee's stale cached Add value instead of
#                      re-reading var_table -- a stale-value miscompile.
#
# perl: 2 (the post-reassignment value of $x). A pre-fix run instead prints
# the callee's leaked 1+2=3 (Context.pm's own cache, not var_table) --
# proving the poisoned memo makes a genuine mutable read (PadAccess) get
# served from the cache like a pure node.
subtest 'callee pure node id-collides with caller mutable-read: memo must not leak' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Build the caller's PadAccess($x) first so we know its (content-hashed)
    # id, then force the callee's Add to share that EXACT string id --
    # mirroring how two independent NodeFactory/graph instances (one per
    # compiled sub) can coin the same id string (counter-based CFG ids reset
    # per graph; content-hash ids depend on operand ids that also reset).
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$nx, int_const($f, 1)]);
    $vx->set_representation('Int');

    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $collision_id = $rx->id;

    # Callee graph: sub f { my $a = 1 + 2; $a - $a } -- pure, no args, one
    # Return. The inner Add is hand-constructed (bypassing hash-consing) so
    # its id is forced to collide with the caller's PadAccess id above, and
    # is referenced TWICE (Subtract(add,add)) so its second lookup forces
    # the cache-gated _reads_mutable_location check to run and memoize it
    # PURE under the colliding id.
    my $c1 = int_const($f, 1);
    my $c2 = int_const($f, 2);
    my $callee_add = Chalk::IR::Node::Add->new(
        id     => $collision_id,
        inputs => [$c1, $c2],
    );
    $callee_add->set_representation('Int');
    my $callee_top = Chalk::IR::Node::Subtract->new(
        id     => 'CalleeTop#collision-test',
        inputs => [$callee_add, $callee_add],
    );
    $callee_top->set_representation('Int');
    my $callee_start = $f->make('Start');
    my $callee_ret = $f->make_cfg('Return', inputs => [$callee_top]);
    $callee_ret->set_control_in($callee_start);
    my $callee_graph = Chalk::IR::Graph->new(start => $callee_start, returns => [$callee_ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        target         => mk_target($callee_graph),
    );
    $call->set_control_in($vx);

    my $asg = $f->make('Assign', inputs => [$rx, int_const($f, 2)]);
    $asg->set_representation('Int');
    $asg->set_control_in($call);

    my $rxF = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    is($rxF->id, $collision_id, 'precondition: final PadAccess($x) shares the forced collision id');
    my $ret = $f->make_cfg('Return', inputs => [$rxF]);
    $ret->set_control_in($asg);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(print_returned_value($f, $ret), program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[2]', 'post-reassignment read of $x sees 2 (perl: 2), not the '
        . 'memo-poisoned callee value or a stale pre-assign cache hit');
};

done_testing;
