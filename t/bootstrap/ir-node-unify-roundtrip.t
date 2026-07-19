# ABOUTME: Round-trip guardrail over an effectful graph (sequenced statement
# ABOUTME: effects + loop memory-Phi): asserts to_json/from_json is a lossless inverse.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Scalar::Util qw(blessed);
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# =============================================================================
# Fixture: a real effectful graph built through the Chalk IR factory.
#
#   sub corpus_case {
#       print "go";                    # Print                  ) sequenced
#       my @unused = (1);              # Call(builtin,'unused')  ) statement
#       my @a = (10, 20, 30);          #                           effects,
#       my $i = 0;                    #                           control_in-
#       while ($i < 3) {              #                           chained
#           $a[$i] = $i + 1;          # loop-body element store -> memory-Phi
#           $i = $i + 1;              # loop-body value store   -> value-Phi
#       }
#       $a[0];
#   }
#
# Two sequenced statement-effects (Print, Call) precede the loop; the loop
# carries BOTH a value-Phi ($i) and a memory-Phi (merging MemStart with the
# element-store Assign on the backedge) -- exercising control threading AND
# memory-SSA merge in one fixture.
# =============================================================================
# NOTE ON SHAPE: control is threaded via GENUINE inputs[0] edges here (the
# same shape the real B::SoN producer emits: Print.inputs=[control,value],
# element-store Assign.inputs=[control,target,value]) rather than via
# Node::set_control_in(). set_control_in() is a from_json LOADER-ONLY
# reconstruction (grep confirms it is called nowhere in lib/ except
# Serialize/JSON.pm and the CFG nodes' own late-binding setters) -- a
# freshly-built graph threads control through inputs, and to_json's node
# walk (Graph::nodes / _all_nodes_topo) only follows inputs()/consumers(),
# never control_in. A fixture built via set_control_in alone would leave its
# effect nodes UNREACHABLE from to_json's walk and silently vanish from the
# serialized output -- this was caught building this fixture (see the
# session report) and is why this fixture instead mirrors B::SoN's own
# inputs[0]=control convention.
sub make_effectful_loop_graph {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');

    # --- two sequenced statement effects, chained via genuine input edges ---
    my $msg   = $f->make('Constant', value => 'go', const_type => 'string');
    my $print = $f->make('Print', inputs => [$start, $msg]);

    my $one  = $f->make('Constant', value => '1', const_type => 'integer');
    my $call = $f->make('Call', dispatch_kind => 'builtin', name => 'unused',
        inputs => [$print, $one]);

    # --- loop header: entry control is the Call (last sequenced effect) ---
    my $loop = $f->make_cfg('Loop', inputs => [$call]);

    # memory-Phi: merges MemStart (entry) with the loop-body element-store
    # Assign (backedge) -- the Assign is the Phi's INPUT (the Phi represents
    # "the memory version after the store"), matching the shape B::SoN emits
    # (probed live via B::SoN for `$a[$i]=$i+1` in a while loop) and
    # Target::LLVM::Context::_is_memory_phi's detection (an input is
    # MemStart, or an Assign over a Subscript).
    my $mem_start = $f->make('MemStart');
    my $mem_phi   = $f->make('Phi', region => $loop, values => [$mem_start]);

    # value-Phi: the induction variable $i, entry 0.
    my $zero   = $f->make('Constant', value => '0', const_type => 'integer');
    my $i_phi  = $f->make('Phi', region => $loop, values => [$zero]);

    # loop body entry control (Proj index=1 by B::SoN convention).
    my $body_proj = $f->make_cfg('Proj', inputs => [$loop], index => 1);

    # loop body: $a[$i] = $i + 1  (element store; control-threaded,
    # memory-producing -- its lvalue target is a 2-input Subscript, no
    # memory slot on the Assign itself; the Assign IS the new memory value).
    my $lvalue   = $f->make('Subscript', inputs => [$i_phi, $i_phi]);
    my $i_plus_1 = $f->make('Add', inputs => [$i_phi, $one]);
    my $store    = $f->make('Assign', inputs => [$body_proj, $lvalue, $i_plus_1]);
    $mem_phi->set_backedge($store);

    # loop body: $i = $i + 1 (control-threaded after the store)
    my $i_next = $f->make('Add', inputs => [$i_phi, $one]);
    $i_phi->set_backedge($i_next);

    # loop condition: $i < 3. Attaching this via set_control_in (mirroring
    # from_json's loop_control demotion) trips to_json's own GAP-not-
    # corruption guard (019f29ed-974a) UNLESS the condition is also captured
    # as a genuine input somewhere -- that guard's contract (per its comment
    # in Serialize/JSON.pm) is "a freshly-built graph... or its condition
    # captured as an input... round-trips". So thread the condition as a
    # real input on the exit Region (harmless extra input; keeps it
    # reachable via Graph::nodes' inputs walk) rather than via control_in,
    # which real Chalk-native construction never uses anyway (control_in is
    # a from_json loader-only reconstruction; see the note above
    # make_effectful_loop_graph).
    my $three = $f->make('Constant', value => '3', const_type => 'integer');
    my $cond  = $f->make('NumLt', inputs => [$i_phi, $three]);

    # loop exit
    my $exit_proj = $f->make_cfg('Proj', inputs => [$loop], index => 0);
    my $region    = $f->make_cfg('Region', inputs => [$exit_proj, $cond]);

    # post-loop read: $a[0], pinned to the merged (memory-Phi) heap.
    my $idx0  = $f->make('Constant', value => '0', const_type => 'integer');
    my $read  = $f->make('Subscript', inputs => [$i_phi, $idx0, $mem_phi]);

    my $ret = $f->make_cfg('Return', inputs => [$region, $read]);

    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
    return ($graph, {
        print => $print, call => $call, loop => $loop, mem_phi => $mem_phi,
        i_phi => $i_phi, cond => $cond, store => $store, region => $region,
        ret => $ret, mem_start => $mem_start,
    });
}

# _control_pred($node) — the node's control predecessor, however it is
# carried: a CFG node overrides control_in() to read inputs->[0] (Loop does
# this natively); a statement-effect node (Print/Call/Assign) carries its
# control as a genuine inputs->[0] edge with no override, so read it
# positionally there; a node with an explicit control_in DECORATION
# (set_control_in, e.g. a loop condition) takes that. Mirrors the union of
# shapes _deserialize_graph reconstructs.
my %_STMT_EFFECT_OP = map { $_ => 1 }
    qw(Print Call Assign RegexSubst TryCatch RegexMatch Match NotMatch BacktickExpr);
my %_CFG_OP = map { $_ => 1 } qw(Start Return Unwind If Proj Region Loop);

sub _control_pred {
    my ($node) = @_;
    return undef unless blessed($node);
    if ($node->can('control_in') && defined $node->control_in) {
        return $node->control_in;
    }
    # A Return whose leading input is itself a CFG node carries control
    # positionally (B::SoN's inputs=[control,value] shape; the loader's
    # _deserialize_graph splits exactly this leading CFG input off into
    # control_in). A freshly-built graph that has not been round-tripped
    # yet has this same positional shape with no control_in decoration set,
    # so recognize it here too -- otherwise a freshly-built Return's
    # structural key would include the control predecessor as a "value"
    # input while its round-tripped counterpart (control_in-demoted by the
    # loader) would not, making the two spuriously non-equivalent.
    if ($node->operation eq 'Return') {
        my $first = $node->inputs->[0];
        return $first if blessed($first) && $first->can('operation')
            && $_CFG_OP{ $first->operation };
    }
    if ($_STMT_EFFECT_OP{ $node->operation }) {
        my $first = $node->inputs->[0];
        return $first if blessed($first) && $first->can('operation');
    }
    return undef;
}

# =============================================================================
# Fixture self-assertion (AC bullet): >= 2 sequenced statement-effects AND a
# memory-Phi inside a loop, so a later refactor can't silently downgrade this
# to a vacuously-passing toy.
# =============================================================================
sub assert_fixture_shape {
    my ($graph, $parts) = @_;

    my @chained;
    my $c = $parts->{call};
    my %seen;
    while (defined $c && !$seen{ $c->id }++) {
        push @chained, $c if $_STMT_EFFECT_OP{ $c->operation };
        $c = _control_pred($c);
    }
    ok(@chained >= 2, 'fixture has >= 2 sequenced statement-effects on the control chain')
        or diag('found only ' . scalar(@chained) . ' chained statement effects');

    my $mem_phi = $parts->{mem_phi};
    ok(defined $mem_phi && $mem_phi->operation eq 'Phi',
        'fixture has a Phi node designated as the memory-Phi');
    ok(defined $mem_phi->region && $mem_phi->region->id eq $parts->{loop}->id,
        'the memory-Phi is inside (regioned by) the Loop');
    my @mem_inputs = grep { blessed($_) } $mem_phi->inputs->@*;
    ok((grep { $_->operation eq 'MemStart' || $_->operation eq 'Assign' } @mem_inputs) >= 1,
        'the memory-Phi merges MemStart/Assign memory versions (not scalar values)');
}

{
    my ($graph, $parts) = make_effectful_loop_graph();
    assert_fixture_shape($graph, $parts);
}

# =============================================================================
# equiv(g1, g2) — structural graph equality oracle.
#
# Compares:
#   - same node set by content_hash
#   - same input wiring (per-node, positional, INCLUDING array-of-array slots)
#   - same control_in chain, in ORDER (not just membership)
#   - same memory-input threading (memory value at the same POSITIONAL slot)
#   - consumer (use-def) bidirectional consistency: every node's registered
#     consumers are exactly the inverse of every other node's inputs/control_in
#     edges that reference it.
#
# _node_key($node, \%memo) — a STRUCTURAL fingerprint, recursively built from
# operation + fields + input fingerprints (never a literal node id).
#
# Raw content_hash is NOT usable as the cross-graph identity key here: CFG
# nodes (Start/Return/Loop/Region/Proj) and per-call statement-effect nodes
# (Print/Call/Assign/...) get fresh counter-suffixed ids per NodeFactory
# instance ("Loop#4" vs "Loop#2"), and content_hash's _serialize_inputs()
# embeds those LITERAL ids for any node that consumes them -- so a Loop
# built by one factory and an independently-reloaded structurally-identical
# Loop built by a different factory's counter get DIFFERENT content_hash
# strings even though the graphs are isomorphic. A structural key must
# recurse through fingerprints, not literal ids, cycle-guarded via memo (a
# loop backedge is a genuine data cycle: Phi -> Add -> Phi).
# _value_inputs($node) — this node's inputs() list with the leading CONTROL
# input stripped, when that input is the node's own control predecessor.
#
# Chalk's contract (per Serialize/JSON.pm's own commentary) is that control
# threading and value/data threading are DISTINCT concerns: a freshly-built
# graph carries control as a genuine inputs[0] edge on a statement-effect
# node (Print/Call/Assign/Return), while a from_json-LOADED graph demotes
# that same edge to the control_in decoration and drops it from inputs().
# Both representations are semantically the SAME graph -- the round-trip is
# expected to convert one into the other -- so the node-identity key must
# compare VALUE inputs only, with the control predecessor checked separately
# via the ordered control-chain comparison (equiv()'s step 3). Without this
# split, every statement-effect/Return node's structural key would differ
# solely because of WHICH representation the control edge is in, and the
# positive round-trip test would spuriously fail even on a perfectly lossless
# boundary.
sub _value_inputs {
    my ($node) = @_;
    my @in = $node->inputs->@*;
    my $ctrl = _control_pred($node);
    if (@in && defined $ctrl && blessed($in[0]) && $in[0]->id eq $ctrl->id) {
        shift @in;
    }
    return @in;
}

sub _node_key {
    my ($node, $memo) = @_;
    $memo //= {};
    return '<undef>' unless blessed($node);
    my $id = $node->id;
    return $memo->{$id} if exists $memo->{$id};
    # Cycle guard: seed a placeholder before recursing, so a backedge
    # (Phi's second input pointing through Add back to itself) terminates
    # instead of looping forever. The placeholder is the node's OWN
    # operation + a marker; this is sufficient because the cycle always
    # closes back through the SAME Phi, which both graphs traverse
    # identically (same recursion order) when isomorphic.
    $memo->{$id} = "<in-progress:$id>";

    my @parts = ($node->operation);
    if ($node->operation eq 'Constant') {
        push @parts, 'const_type=' . ($node->const_type // '');
        push @parts, 'value=' . ($node->value // '');
    }
    elsif ($node->operation eq 'Call') {
        push @parts, 'dispatch_kind=' . ($node->dispatch_kind // '');
        push @parts, 'name=' . ($node->name // '');
    }
    elsif ($node->operation eq 'Proj') {
        push @parts, 'index=' . ($node->index // '');
    }
    if ($node->operation eq 'Phi' && defined $node->region) {
        push @parts, 'region=' . _node_key($node->region, $memo);
    }
    for my $in (_value_inputs($node)) {
        if (!defined $in) {
            push @parts, 'undef';
        }
        elsif (ref($in) eq 'ARRAY') {
            push @parts, '[' . join(',', map { _node_key($_, $memo) } $in->@*) . ']';
        }
        else {
            push @parts, _node_key($in, $memo);
        }
    }
    my $key = join('|', @parts);
    $memo->{$id} = $key;
    return $key;
}

# Map every node in a graph to a stable structural key, and build the
# reverse key->node map. Two structurally-identical graphs must produce the
# same key set. $memo is an external hashref (caller-owned) so callers can
# reuse the SAME memo for later _input_signature/_control_in_chain calls on
# this graph's nodes, keeping fingerprints consistent and avoiding rework.
sub _index_graph_with_memo {
    my ($graph, $memo) = @_;
    my %by_key;
    for my $n ($graph->nodes->@*) {
        next unless blessed($n);
        $by_key{ _node_key($n, $memo) } = $n;
    }
    return \%by_key;
}

# Serialize one node's input list to a comparable string of structural keys,
# preserving POSITION (including nested array-of-arrayref slots) so a
# permutation is detectable. $memo is shared with the graph's _index_graph
# call so keys are consistent within one equiv() comparison.
sub _input_signature {
    my ($node, $memo) = @_;
    my @parts;
    for my $in (_value_inputs($node)) {
        if (!defined $in) {
            push @parts, 'undef';
        }
        elsif (ref($in) eq 'ARRAY') {
            push @parts, '[' . join(',', map { _node_key($_, $memo) } $in->@*) . ']';
        }
        else {
            push @parts, _node_key($in, $memo);
        }
    }
    return join('~', @parts);
}

# Walk a node's control predecessor chain (via _control_pred, which covers
# both a real inputs[0] control edge and a control_in decoration) and return
# the ordered list of structural keys. Bounded by a seen-set (defensive
# against an accidental cycle).
sub _control_in_chain {
    my ($node, $memo) = @_;
    my @chain;
    my %seen;
    my $c = _control_pred($node);
    while (defined $c && !$seen{ $c->id }++) {
        push @chain, _node_key($c, $memo);
        $c = _control_pred($c);
    }
    return @chain;
}

sub equiv {
    my ($g1, $g2) = @_;
    my @reasons;

    my (%memo1, %memo2);
    my $idx1 = _index_graph_with_memo($g1, \%memo1);
    my $idx2 = _index_graph_with_memo($g2, \%memo2);

    my @keys1 = sort keys %$idx1;
    my @keys2 = sort keys %$idx2;

    # 1. Same node set by structural key.
    if (join("\n", @keys1) ne join("\n", @keys2)) {
        my %in2 = map { $_ => 1 } @keys2;
        my %in1 = map { $_ => 1 } @keys1;
        push @reasons, "node set differs: only-in-g1=["
            . join(',', grep { !$in2{$_} } @keys1) . "] only-in-g2=["
            . join(',', grep { !$in1{$_} } @keys2) . "]";
        return (0, \@reasons);
    }

    # 2. Same input wiring, per node (positional).
    for my $key (@keys1) {
        my $n1 = $idx1->{$key};
        my $n2 = $idx2->{$key};
        my $sig1 = _input_signature($n1, \%memo1);
        my $sig2 = _input_signature($n2, \%memo2);
        if ($sig1 ne $sig2) {
            push @reasons, "input wiring differs for node [$key]: "
                . "g1=[$sig1] g2=[$sig2]";
        }
    }

    # 3. Same control chain, IN ORDER.
    for my $key (@keys1) {
        my $n1 = $idx1->{$key};
        my $n2 = $idx2->{$key};
        my @chain1 = _control_in_chain($n1, \%memo1);
        my @chain2 = _control_in_chain($n2, \%memo2);
        my $c1 = join('->', @chain1);
        my $c2 = join('->', @chain2);
        if ($c1 ne $c2) {
            push @reasons, "control chain differs for node [$key]: "
                . "g1=[$c1] g2=[$c2]";
        }
    }

    # 4. Consumer (use-def) bidirectional consistency, checked on BOTH graphs
    #    independently: for every node, its registered consumers must be
    #    exactly the inverse of every other node's inputs/control_in edges
    #    that reference it. This is the oracle for a silent
    #    Phi-consumer-registration seam: a consumer with no matching input
    #    edge, or an input edge whose target lacks back-registration, is
    #    flagged either way.
    for my $g_pair ([g1 => $idx1, \%memo1], [g2 => $idx2, \%memo2]) {
        my ($label, $idx, $memo) = @$g_pair;

        # Build the expected consumer set from every node's inputs + control_in.
        my %expected_consumers_of;   # key(producer) => { key(consumer) => 1 }
        for my $key (keys %$idx) {
            my $n = $idx->{$key};
            for my $in ($n->inputs->@*) {
                my @targets = ref($in) eq 'ARRAY' ? $in->@* : ($in);
                for my $t (@targets) {
                    next unless blessed($t);
                    $expected_consumers_of{ _node_key($t, $memo) }{$key} = 1;
                }
            }
            if ($n->can('control_in') && defined $n->control_in) {
                $expected_consumers_of{ _node_key($n->control_in, $memo) }{$key} = 1;
            }
            # Phi's region is also a use-def edge (NodeFactory registers it).
            if ($n->operation eq 'Phi' && defined $n->region) {
                $expected_consumers_of{ _node_key($n->region, $memo) }{$key} = 1;
            }
        }

        for my $key (keys %$idx) {
            my $n = $idx->{$key};
            next unless $n->can('consumers');
            my %actual_consumers = map { _node_key($_, $memo) => 1 }
                grep { blessed($_) } $n->consumers->@*;
            my %expected = ($expected_consumers_of{$key} // {})->%*;

            for my $ck (keys %expected) {
                next if $actual_consumers{$ck};
                push @reasons, "[$label] node [$key] is an input of [$ck] "
                    . "but [$ck] is not registered in [$key]'s consumers "
                    . "(missing back-registration)";
            }
            for my $ck (keys %actual_consumers) {
                next if $expected{$ck};
                push @reasons, "[$label] node [$key] lists consumer [$ck], "
                    . "but [$ck] has no matching input/control_in edge to it "
                    . "(consumer with no matching input edge)";
            }
        }
    }

    return (scalar(@reasons) == 0, \@reasons);
}

# =============================================================================
# POSITIVE: from_json(to_json(g)) equiv g, over the effectful+loop+memory-Phi
# fixture built above.
#
# KNOWN GAP (not fixed here — this issue is test-only, GAP-not-corruption):
# Chalk::IR::NodeFactory::make's Phi branch only registers consumers from a
# `values =>` argument, but Chalk::IR::Serialize::JSON::_deserialize_graph
# calls make('Phi', %args) with `inputs =>` (never `values =>`), so every
# from_json-reconstructed Phi's non-backedge input (the loop-entry/init
# value) is missing its back-registration as that input's consumer — the
# backedge input alone is repaired separately, via the explicit
# set_backedge() patch in _deserialize_graph, which does call add_consumer.
# This is reproducible on a minimal single-Phi graph with no memory
# involved, so it is a general property of the from_json boundary, not an
# artifact of this fixture's size. equiv()'s consumer bidirectional-
# consistency check (step 4) is precisely the oracle built to catch this
# class of seam, and it does: this subtest is expected to FAIL on current
# head until that Phi-registration gap is fixed in a follow-up issue.
# =============================================================================
{
    my ($graph, $parts) = make_effectful_loop_graph();
    my $json    = to_json({ corpus_case => $graph });
    my $loaded  = from_json($json);
    ok(exists $loaded->{corpus_case}, 'round-trip: graph present after from_json');

    my ($ok, $reasons) = equiv($graph, $loaded->{corpus_case});
    ok($ok, 'round-trip is a lossless inverse over the effectful graph (equiv holds)')
        or diag(join("\n", @$reasons));
}

# =============================================================================
# NEGATIVE subtests: each corrupts the DESERIALIZED graph and asserts equiv
# REJECTS it, proving the predicate is non-tautological.
# =============================================================================

# Helper: build the reference (original) + a fresh round-tripped copy to mutate.
sub _roundtripped_pair {
    my ($graph, $parts) = make_effectful_loop_graph();
    my $json   = to_json({ corpus_case => $graph });
    my $loaded = from_json($json);
    return ($graph, $loaded->{corpus_case});
}

subtest 'negative: drop one memory-input edge -> equiv rejects' => sub {
    my ($orig, $copy) = _roundtripped_pair();

    # Find the memory-Phi in the copy (region is a Loop; inputs include a
    # MemStart-descended value). Locate via the same structural test the
    # backend uses: a Phi whose region is a Loop and whose input traces to
    # MemStart.
    my ($mem_phi) = grep {
        blessed($_) && $_->operation eq 'Phi'
            && defined $_->region && $_->region->operation eq 'Loop'
            && grep { blessed($_) && ($_->operation eq 'MemStart' || $_->operation eq 'Assign') }
               $_->inputs->@*
    } $copy->nodes->@*;
    ok(defined $mem_phi, 'located the memory-Phi in the round-tripped copy') or return;

    # Drop the memory input edge: splice the memory value out of the Phi's
    # inputs array (simulating a lost memory-input edge), WITHOUT fixing up
    # consumers -- a corruption, not a valid graph transform.
    my @before = $mem_phi->inputs->@*;
    ok(@before >= 1, 'memory-Phi has at least one input to drop') or return;
    splice($mem_phi->inputs->@*, 0, 1);   # drop the first (entry/MemStart) input

    my ($ok, $reasons) = equiv($orig, $copy);
    ok(!$ok, 'equiv rejects a graph with a dropped memory-input edge')
        or diag('equiv incorrectly accepted the corrupted graph');
};

subtest 'negative: permute a memory value position -> equiv rejects' => sub {
    my ($orig, $copy) = _roundtripped_pair();

    my ($store) = grep {
        blessed($_) && $_->operation eq 'Assign'
            && grep { blessed($_) && $_->operation eq 'Subscript' } $_->inputs->@*
    } $copy->nodes->@*;
    ok(defined $store, 'located the element-store Assign in the round-tripped copy') or return;

    my @in = $store->inputs->@*;
    ok(@in >= 2, 'store has at least 2 inputs to permute') or return;
    # Swap the last two positional inputs (the memory value is the last
    # positional input per the fixture's Assign(target, value, memory) shape).
    @in[-1, -2] = @in[-2, -1];
    $store->inputs->@* = @in;

    my ($ok, $reasons) = equiv($orig, $copy);
    ok(!$ok, 'equiv rejects a graph with a permuted memory-input position')
        or diag('equiv incorrectly accepted the corrupted graph');
};

subtest 'negative: swap two sequenced statement-effects -> equiv rejects' => sub {
    my ($orig, $copy) = _roundtripped_pair();

    # Find the Print and Call statement effects directly (they are the only
    # two Print/Call nodes in this fixture; the fixture builds them chained
    # in program order Print -> Call via a genuine inputs[0] control edge).
    my ($print) = grep { blessed($_) && $_->operation eq 'Print' } $copy->nodes->@*;
    my ($call)  = grep { blessed($_) && $_->operation eq 'Call'  } $copy->nodes->@*;
    ok(defined $print && defined $call, 'located Print and Call in the round-tripped copy') or return;

    # Swap their order: re-point Call's control predecessor to whatever
    # Print's predecessor was, and vice versa (an order-swap corruption).
    # Print/Call carry control positionally (inputs->[0]) on a Chalk-native
    # round-trip -- mutate that slot directly rather than via
    # set_control_in, which would set the DECORATION but leave the stale
    # inputs->[0] edge in place (not a faithful "swap").
    my $print_pred = _control_pred($print);
    my $call_pred  = _control_pred($call);
    ok(defined $print_pred && defined $call_pred, 'both effects have predecessors to swap') or return;

    for my $pair ([$print, $call_pred], [$call, $print_pred]) {
        my ($node, $new_pred) = @$pair;
        if ($node->can('control_in') && defined $node->control_in) {
            $node->set_control_in($new_pred);
        }
        else {
            $node->inputs->[0] = $new_pred;
        }
    }

    my ($ok, $reasons) = equiv($orig, $copy);
    ok(!$ok, 'equiv rejects a graph with swapped sequenced statement-effect order')
        or diag('equiv incorrectly accepted the corrupted graph');
};

subtest 'negative: consumer with no matching input edge -> equiv rejects' => sub {
    my ($orig, $copy) = _roundtripped_pair();

    my @nodes = grep { blessed($_) } $copy->nodes->@*;
    ok(@nodes >= 2, 'copy has at least 2 nodes') or return;

    # Pick two unrelated nodes and register a bogus consumer edge that has NO
    # matching input/control_in edge pointing the other way.
    my ($a) = grep { $_->operation eq 'Constant' } @nodes;
    my ($b) = grep { $_->operation eq 'Return' } @nodes;
    ok(defined $a && defined $b, 'located a Constant and the Return to forge an edge between') or return;

    $a->add_consumer($b);   # $b now falsely listed as $a's consumer

    my ($ok, $reasons) = equiv($orig, $copy);
    ok(!$ok, 'equiv rejects a consumer edge with no matching input edge')
        or diag('equiv incorrectly accepted the corrupted graph');
};

subtest 'negative: input edge whose target lacks back-registration -> equiv rejects' => sub {
    my ($orig, $copy) = _roundtripped_pair();

    # The element-store Assign's lvalue-target input (a Subscript over the
    # induction Phi) is a genuine input edge: Assign.inputs includes the
    # Subscript, and the Subscript's consumers should include the Assign.
    my ($store) = grep {
        blessed($_) && $_->operation eq 'Assign'
            && grep { blessed($_) && $_->operation eq 'Subscript' } $_->inputs->@*
    } $copy->nodes->@*;
    ok(defined $store, 'located the element-store Assign') or return;

    my ($lvalue) = grep { blessed($_) && $_->operation eq 'Subscript' } $store->inputs->@*;
    ok(defined $lvalue, 'located the lvalue-target Subscript feeding the store') or return;

    # Remove the store from the lvalue's consumer list WITHOUT removing the
    # input edge -- the input edge now points at a producer (the Subscript)
    # that has no matching back-registration for this consumer.
    $lvalue->remove_consumer($store);

    my ($ok, $reasons) = equiv($orig, $copy);
    ok(!$ok, 'equiv rejects an input edge whose target lacks back-registration')
        or diag('equiv incorrectly accepted the corrupted graph');
};

done_testing();
