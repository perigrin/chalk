# ABOUTME: Serialize/deserialize Chalk::IR::Graph instances to/from JSON.
# ABOUTME: Provides to_json(\%named_graphs) and from_json($json_string) as exportable subs.

package Chalk::IR::Serialize::JSON;

use 5.42.0;
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(to_json from_json);

use JSON::PP ();
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Analysis;   # from_json still runs it; see the note at its call
use Chalk::IR::Node::Coerce;   # _insert_str_coercions builds these directly
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype: the join lattice
use Chalk::IR::Value;   # for `isa Chalk::IR::Value`

# CFG node operations — these carry control tokens and are never hash-consed.
my %CFG_OPS = map { $_ => 1 } qw(Start Return Unwind If Proj Region Loop);

# B::SoN carries type info as a `stamp` drawn from the shared lattice (see
# Chalk::Grammar::Perl::TypeLibrary, which is canonical); Chalk's backend
# requires an explicit `representation`. The names agree, so the only question
# at this boundary is which stamps the backend can lower.
# THIS SET IS A T2 FACT SITTING IN A T1 FILE, and that is a layering defect,
# not just an awkward home. T1 models perl; T2 decides what a given target can
# lower. "Which stamps the backend can lower" is entirely the second question,
# and answering it here means the LOADER -- shared by every target -- is gated
# on one target's capabilities. A second backend with different gaps would
# have no say, and would silently inherit LLVM's.
#
# It exists only because `stamp` and `representation` are ONE field under the
# transitional alias, so admitting a name to the type axis simultaneously
# claims it as a machine encoding. Split the fields and this set dissolves:
# `stamp` takes every lattice type unconditionally, and `representation` is
# written by T2 alone, where _repr_to_llvm_type and %_REPR_NO_MACHINE_TYPE
# already do the refusing at the right layer.
# See docs/plans/2026-08-24-loader-analysis-pipeline.md (slice 3).
#
# The whitelist itself, until then: the stamp names that are also
# representation names. A WHITELIST, not a translation -- the two vocabularies
# agree name-for-name, and what this set carries is which stamps the backend
# can actually lower. A stamp outside it
# (Scalar, List, DualVar, a ref type) leaves the representation unset so
# _require_repr reports an honest GAP instead of mislowering.
# The wire stamps that may enter the representation field. This is a filter on a
# SHARED field, not a statement about the lattice: `stamp` and `representation`
# are one field under the transitional alias (Chalk::IR::Node), so a name
# admitted here is simultaneously claimed as a machine encoding.
#
# `Unknown` is excluded and MUST STAY excluded. It is not merely unlowerable --
# it is a poison value in this field, in two ways at once. It blocks the
# inference that would have narrowed it (the loader's guards read a present
# repr as "already decided"; _is_narrowed below softens that but the passes
# still have nothing to narrow FROM), and any node still holding it at machine
# type selection dies in _repr_to_llvm_type: "the pessimistic top: INFERENCE
# never determined a type for this value."
#
# That is also the sharpest argument that the alias cannot be the end state:
# `Unknown` is the CORRECT type for an un-narrowed node and an INVALID
# representation for that same node. One value, right on one axis and poison on
# the other, is what a single shared field cannot express -- see
# docs/plans/2026-08-24-loader-analysis-pipeline.md.
#
# `ArrayRef`/`HashRef` are admitted (slice 3b). Both already have machine
# encodings in %_REPR_LLVM_TYPE (`i8*`, a boxed aggregate pointer), so dropping
# them was an omission in the original six-name list rather than a deliberate
# exclusion. Measured over 12 programs, they are 9 of the 86 stamps the producer
# emits; `Unknown` is another 9.
#
# `Array`/`Hash` are admitted too, and they are the CONTAINERS -- `%Array*`
# ({i64, i64, %Slot*}) and `%Hash*` -- not the ArrayRef/HashRef references that
# point at them. Both have had machine encodings all along
# (`Context.pm:3529-3530`); what was missing was a producer that emitted them.
# An earlier note here recorded that the remaining lattice names "are never
# emitted at all", which was true when measured and is now false for these two:
# perl5-son 86d7f73 stamps an aggregate SIGNATURE PARAMETER from its sigil, so
# `sub f($x, @rest)` sends @rest as Array and `sub g($x, %opt)` sends %opt as
# Hash. Dropping them here would discard the only type information that end can
# provide about a slurpy.
#
# Note the asymmetry with the element type: the CONTAINER lowers, but
# `Array[Scalar]`'s ELEMENT does not, for want of a boxed value representation
# (docs/architecture/ir-and-lowering.md section 5). Admitting `Array` types the
# container; it does not make an arbitrary element read lowerable.
my %LOWERABLE_STAMP = map { $_ => 1 }
    qw(Int Num Str Boolean Undef Object ArrayRef HashRef Array Hash Scalar);

# is_lowerable_stamp($stamp) -> bool
#
# The table's one question, asked directly. Exposed because it is a CONTRACT
# with the backend -- a stamp admitted here is claimed to have a machine
# encoding -- and a contract with no way to check it drifts. `Scalar` was
# excluded here long after it gained one (%Slot at both LLVM type
# authorities), and the cost was the largest single GAP group in the corpus
# gate: a method returning an un-narrowed Scalar reached lowering with no
# representation at all.
sub is_lowerable_stamp ($stamp) {
    return false if !defined $stamp;
    return $LOWERABLE_STAMP{$stamp} ? true : false;
}


# -----------------------------------------------------------------------
# _extract_fields($node, \%id_remap) — returns a hashref of extra fields
# for nodes that carry them, or undef if no extra fields.
# id_remap is needed for Phi whose region field holds a node reference.
# -----------------------------------------------------------------------
sub _extract_fields ($node, $id_remap) {
    my $op = $node->operation;

    if ($op eq 'Constant') {
        return {
            const_type => $node->const_type,
            value      => defined $node->value ? "${\$node->value}" : undef,
        };
    }
    if ($op eq 'AnonSub') {
        # Emitted only when present: a frontend-built AnonSub has no wire
        # name and falls back to per-node identity.
        return { (defined $node->name ? (name => $node->name) : ()) };
    }

    if ($op eq 'Call') {
        return {
            dispatch_kind => $node->dispatch_kind,
            name          => $node->name,
            # Constructor calls (name='new') carry the :param name list; losing
            # it silently re-lowers with no bound params (branch-review I3).
            param_names   => [ ($node->param_names // [])->@* ],
            # Method-dispatch calls name their statically-known class
            # (019eb42a MOP-direct); losing it makes a reloaded call
            # un-lowerable and changes its content hash.
            (defined $node->class_name ? (class_name => $node->class_name) : ()),
            # A folded sort's comparison kind and direction. Losing them makes
            # three different programs one node -- ascending numeric,
            # descending numeric, and a STRING compare all read as `sort` over
            # a list -- so a reloaded graph would lower to whichever the
            # backend guessed. Emitted only when present, so every other Call
            # is byte-identical to before.
            # The callsite's context. Emitted only when the producer stated
            # one: an ABSENT want means perl left entersub's context slot
            # empty (a call in last-operand position, whose context arrives at
            # runtime), which is a different fact from "scalar". Writing a
            # default here would erase that distinction at the seam.
            (defined $node->want ? (want => $node->want) : ()),
            (defined $node->sort_cmp   ? (sort_cmp   => $node->sort_cmp)   : ()),
            (defined $node->sort_order ? (sort_order => $node->sort_order) : ()),
            # paren_form is part of content_hash (Call.pm) -- losing it would
            # change a reloaded call's identity/hash-consing behavior relative
            # to the graph that produced it.
            paren_form => $node->paren_form,
        };
    }
    if ($op eq 'Phi') {
        return { region => $id_remap->{ $node->region->id } };
    }
    if ($op eq 'Proj') {
        return { index => $node->index };
    }
    if ($op eq 'PadAccess') {
        return {
            targ   => $node->targ,
            sigil  => $node->sigil,
            symbol => $node->symbol,
            ( $node->shared ? ( shared => 1 ) : () ),
        };
    }
    if ($op eq 'FieldAccess') {
        return { field_index => $node->field_index, field_stash => $node->field_stash };
    }
    if ($op eq 'Parameter') {
        return {
            # The INDEX is the identity: a parameter is a value identified by
            # POSITION, and two reads of parameter 0 are one node. The name is
            # debug information; the sigil is what types it, and a slurpy is
            # NOT always an array -- `sub f(%h)` is a hash.
            index => $node->index,
            name  => $node->name,
            sigil => $node->sigil,
        };
    }
    if ($op eq 'EntryDef') {
        return {
            package => $node->package,
            sigil   => $node->sigil,
            symbol  => $node->symbol,
        };
    }
    if ($op eq 'CompoundAssign') {
        return { op => $node->op };
    }
    if ($op eq 'PostfixDeref') {
        return { sigil => $node->sigil };
    }
    if ($op eq 'RegexMatch') {
        return {
            pattern => $node->pattern,
            flags   => $node->flags,
        };
    }
    if ($op eq 'RegexSubst') {
        return {
            pattern     => $node->pattern,
            replacement => $node->replacement,
            flags       => $node->flags,
        };
    }
    if ($op eq 'RegexCapture') {
        return { n => $node->n };
    }
    if ($op eq 'EnvRead') {
        return { key => $node->key };
    }
    if ($op eq 'VarDecl') {
        return { scope => $node->scope };
    }
    if ($op eq 'Coerce') {
        return {
            from_repr => $node->from_repr,
            to_repr   => $node->to_repr,
        };
    }
    return undef;
}

# -----------------------------------------------------------------------
# This is the cross-repo walk-order contract; the corpus gate enforces it.
# perl5-son's SoN::Serialize::JSON carries a duplicated copy of this function
# (deliberately — the repos are divorced); the gate keeps them honest.
#
# _all_nodes_topo($graph_or_nodes) — return all nodes in topological order.
# Accepts either a Chalk::IR::Graph (calls ->nodes) or a plain arrayref of
# already-reachable nodes (a caller that computed its own reachable set via
# a full inputs+consumers BFS, e.g. a producer whose graph was never
# incrementally merge()'d into a Graph's own membership cache). Graph->nodes
# does a DFS over inputs[] only; Phi nodes reference a region via a separate
# field (not inputs[]), so Region may appear after Phi in the base list.
# This function re-sorts to ensure Phi region references are always
# serialized before their Phi nodes.
# -----------------------------------------------------------------------
sub _all_nodes_topo ($graph_or_nodes) {
    my $base = ref($graph_or_nodes) eq 'ARRAY'
        ? $graph_or_nodes
        : $graph_or_nodes->nodes;

    # Collect any Phi region nodes AND control_in-linked nodes not already in
    # the base list. Graph::nodes()'s membership cache is seeded by
    # merge()/_seed() and its consumer walk is filtered to cached members
    # (Graph.pm's `in_cache` check) -- a node reachable ONLY via a control_in
    # edge (produce-time control: set_control_in registers the use-def edge
    # via add_consumer, but never merge()s the node into the graph's own
    # cache) is invisible to that walk and would silently vanish from the
    # serialized output. Two distinct shapes need adding:
    #   (a) a node whose control predecessor is missing (walk control_in
    #       BACKWARD from every base node -- e.g. a void statement-effect
    #       Call reached only via a Return's control_in); and
    #   (b) a node that is itself missing because its only inbound edge is
    #       ITS OWN control_in pointing at an already-reachable node (e.g. a
    #       loop condition whose control_in is the Loop, but nothing's
    #       inputs() reference the condition) -- walk FORWARD via consumers()
    #       and keep any consumer whose control_in points back at the node
    #       being walked.
    # Fixpoint both directions together (an added node can itself expose
    # further control_in-only neighbors) until nothing new is found.
    my %seen = map { $_->id => 1 } $base->@*;
    my @extra;
    my @frontier = $base->@*;
    while (@frontier) {
        my @next_frontier;
        for my $node (@frontier) {
            if ($node->operation eq 'Phi') {
                my $region = $node->region;
                if (defined $region && !$seen{ $region->id }++) {
                    push @extra, $region;
                    push @next_frontier, $region;
                }
            }
            # (a) backward: this node's own control predecessor.
            if ($node->can('control_in') && defined $node->control_in) {
                my $ctrl = $node->control_in;
                if (!$seen{ $ctrl->id }++) {
                    push @extra, $ctrl;
                    push @next_frontier, $ctrl;
                }
            }
            # (b) forward: a consumer whose control_in IS this node.
            if ($node->can('consumers')) {
                for my $c ($node->consumers->@*) {
                    next unless blessed($c);
                    next unless $c->can('control_in') && defined $c->control_in
                        && $c->control_in->id eq $node->id;
                    next if $seen{ $c->id }++;
                    push @extra, $c;
                    push @next_frontier, $c;
                }
            }
        }
        @frontier = @next_frontier;
    }

    # Always re-sort via DFS post-order so that Phi regions are guaranteed
    # to precede their Phi nodes (region is a predecessor, not in inputs[]).
    my @all = grep { blessed($_) } ($base->@*, @extra);
    my %visited;
    my %in_progress;
    my @order;

    # Predecessors of a node are its inputs plus, for Phi, its region, plus
    # (control-aware topo) its control_in edge when it has one. A node whose
    # ONLY inbound edge is control_in (e.g. a void statement-effect Call with
    # no data consumer) has no ordering constraint from inputs() alone and
    # could otherwise be emitted AFTER whatever reads it via control_in (e.g.
    # a Return whose control_in it is) -- a genuine forward reference the
    # loader would reject. Adding control_in as a predecessor here forces it
    # to be visited (and thus emitted) before its control_in consumer,
    # exactly like any other producer edge. control_in never closes a cycle
    # back through itself the way a loop Phi's backedge does (it is a
    # straight-line control chain: Start -> effect -> effect -> ... ->
    # Return/Loop), so no cycle-cut exclusion is needed here.
    #
    # A LOOP header Phi's second input (inputs[1], the back-edge value) is
    # the cycle-closing edge: it necessarily forward-references in any
    # serialization order (the loader defer-patches it via set_backedge once
    # every node exists). Treating it as an ordinary predecessor to visit
    # eagerly picks whichever side of the Phi<->backedge cycle the caller's
    # (unordered) input list happens to reach first: if the Phi is visited
    # before the value that reads it (e.g. an Add computing the next
    # iteration), descending into the backedge hits that Add's in-progress
    # cycle guard and lets the Add finish -- and get appended -- BEFORE the
    # Phi, producing a genuine (non-sanctioned) forward reference. Exclude
    # the backedge from a loop Phi's predecessors so only its init input
    # (inputs[0]) and region are visited eagerly, mirroring the
    # pre-unification SoN::IR::Graph::nodes() cycle-cut. A MERGE Phi (region
    # is a Region, not a Loop) has no such cycle and keeps both inputs.
    my $predecessors = sub ($n) {
        my @in = $n->inputs->@*;
        if ($n->operation eq 'Phi' && defined $n->region
                && $n->region->operation eq 'Loop') {
            @in = ($in[0]);
        }
        my @preds = grep { defined $_ && blessed($_) } @in;
        if ($n->operation eq 'Phi' && defined $n->region) {
            push @preds, $n->region;
        }
        if ($n->can('control_in') && defined $n->control_in) {
            push @preds, $n->control_in;
        }
        return @preds;
    };

    my $visit;
    $visit = sub ($n) {
        return unless blessed($n);
        return if $visited{ $n->id };
        return if $in_progress{ $n->id };   # cycle guard
        $in_progress{ $n->id } = 1;
        for my $pred ($predecessors->($n)) {
            $visit->($pred);
        }
        delete $in_progress{ $n->id };
        $visited{ $n->id } = 1;
        push @order, $n;
    };

    for my $node (@all) {
        $visit->($node);
    }

    return \@order;
}

# -----------------------------------------------------------------------
# _serialize_graph($graph) — returns a Perl data structure for one graph.
# -----------------------------------------------------------------------
sub _serialize_graph ($graph) {
    my $topo_nodes = _all_nodes_topo($graph);

    # Build positional ID remap: node->id => positional index (0, 1, 2, ...)
    my %id_remap;
    my $pos = 0;
    for my $node ($topo_nodes->@*) {
        $id_remap{ $node->id } = $pos++;
    }

    # Emit each node
    my @nodes;
    for my $node ($topo_nodes->@*) {
        my @inputs = map { $id_remap{ $_->id } } grep { blessed($_) } $node->inputs->@*;
        my $fields = _extract_fields($node, \%id_remap);

        my %entry = (
            id     => $id_remap{ $node->id },
            op     => $node->operation,
            inputs => \@inputs,
        );
        $entry{fields} = $fields if defined $fields;
        # THE TYPE AXIS. Emitted here because a graph that loses its types on
        # the way out is not serialized, only sketched.
        #
        # This was missing entirely: `stamp` appeared nowhere in to_json, so
        # every type a graph carried was dropped at serialization. The load
        # side has always read the field -- B::SoN sends it -- which is how the
        # asymmetry survived: the wire schema had the key, and only chalk's
        # emitter never wrote it. Measured by round-tripping producer wire
        # (t/bootstrap/ir/loader-reproduces-the-wire.t): 27 stamps lost across
        # four small programs.
        #
        # It matters most where there is no B::SoN at all. `to_json` is the
        # SELF-HOSTING output path, so a serializer that cannot express types
        # means chalk cannot hand a typed graph to anything -- including a
        # future chalk.
        #
        # Absence stays ABSENT rather than becoming null: the load side
        # distinguishes "no stamp" from "stamped Unknown", and a key that is
        # always present would erase that distinction.
        # ONLY LATTICE TYPES GO ON THE WIRE. The stamp field is shared with
        # `representation` under the transitional alias, so a machine ENCODING
        # can be sitting in it -- the OOB path writes `Slot` (a non-lattice
        # name) at _seed_and_propagate_reprs. Emitting that would make an
        # in-memory corruption PERSISTENT and hand the next reader a "type"
        # no lattice contains.
        #
        # t/bootstrap/ir/stamp-alias-preconditions.t exists for exactly this,
        # and caught it: adding the reader above tripped its "nothing in lib/
        # reads the type axis" sweep, and `"stamp": "Slot"` was verified
        # reaching the wire before this guard.
        #
        # Dropping is right rather than lossy: `Slot` is not information the
        # TYPE axis can carry, and the honest type for a statically-missing
        # read is `Undef` (see docs/architecture/ir-and-lowering.md §5). When
        # the OOB path records that instead, this filter stops firing on its
        # own. Until then a dropped Slot is better than a fabricated type.
        # The read and the membership check are ONE expression deliberately:
        # reading this field is only safe when the check accompanies it, and
        # the sweep in stamp-alias-preconditions.t recognises that shape.
        if ($node isa Chalk::IR::Value
                && Chalk::Grammar::Perl::TypeLibrary::is_lattice_type($node->stamp)) {
            $entry{stamp} = $node->stamp;
        }
        # Produce-time control: emit the control_in edge as its own wire key
        # so from_json can decode it back onto control_in directly, instead
        # of the old convention of flattening control into inputs[0] plus a
        # transitional producer-side marker table. _all_nodes_topo's control-
        # aware walk (membership fixpoint + control_in-as-predecessor
        # ordering) guarantees a node's control predecessor is always
        # captured, and always emitted before it, whenever the node itself
        # is -- so the referenced index always resolves on load.
        if ($node->can('control_in') && defined $node->control_in
                && exists $id_remap{ $node->control_in->id }) {
            $entry{control_in} = $id_remap{ $node->control_in->id };
        }
        # Region.head -> the owning If/Loop, set at produce time (FromOptree's
        # StackSim::merge / _build_single_exit / Loop exit-Region sites; the
        # hand-written frontend's IfStatement/loop actions via set_region).
        # An If/Loop is always a control predecessor of the Region it owns,
        # so it is always already in the topo order (and hence in %id_remap)
        # by the time the Region itself is emitted -- no forward-ref defer-
        # patch needed (unlike the loop-Phi backedge).
        if ($node->operation eq 'Region' && defined $node->head
                && exists $id_remap{ $node->head->id }) {
            $entry{head} = $id_remap{ $node->head->id };
        }

        push @nodes, \%entry;
    }

    # Find start node positional ID
    my $start_pos = $id_remap{ $graph->start->id };

    # Find return node positional IDs
    my @return_pos = map { $id_remap{ $_->id } } $graph->returns->@*;

    return {
        nodes   => \@nodes,
        start   => $start_pos,
        returns => \@return_pos,
    };
}

# -----------------------------------------------------------------------
# to_json(\%named_graphs) — serialize named graphs to a JSON string.
# -----------------------------------------------------------------------
sub to_json ($named_graphs) {
    my %methods;
    for my $name (sort keys $named_graphs->%*) {
        $methods{$name} = _serialize_graph($named_graphs->{$name});
    }

    my $data = {
        version => 1,
        source  => undef,
        methods => \%methods,
    };

    return JSON::PP->new->canonical->pretty->encode($data);
}

# -----------------------------------------------------------------------
# _deserialize_graph($method_data) — rebuild a Chalk::IR::Graph from data.
# Handles the full SoN schema. Fields that Chalk nodes don't support
# (e.g., pattern/replacement on RegexMatch/RegexSubst, scope on VarDecl,
# stash_name/var_name on EntryDef) are silently dropped.
# -----------------------------------------------------------------------
sub _deserialize_graph ($method_data) {
    my $factory   = Chalk::IR::NodeFactory->new();
    my @node_data = $method_data->{nodes}->@*;

    my @nodes;  # positional array of created node objects
    my @backedge_patches;  # [phi_position, backedge_index] deferred wirings

    for my $nd (@node_data) {
        my $op     = $nd->{op};
        my $fields = $nd->{fields} // {};
        # Derived from the op name via %CFG_OPS -- the table that answers this
        # is defined 355 lines above (and to_json's emit side reads the same
        # table). The wire cfg:true key the emitter still writes is redundant
        # with $op and is ignored here.
        my $is_cfg = exists $CFG_OPS{$op};

        # Resolve inputs from already-created nodes. Nodes are built in array
        # order, so a valid input index is < the current node count; an index at
        # or beyond it is a FORWARD reference that resolves to undef here. The one
        # sanctioned forward edge is a loop Phi's backedge (inputs[1]), deferred
        # and patched below. Any OTHER forward index is a producer ordering bug
        # that would silently become an undef input and crash DEEP in the backend
        # (seen at LLVM.pm before the Graph::nodes DFS fix). Die at the seam,
        # naming the node/slot/index, so a future ordering bug is an immediate,
        # legible loader error rather than an opaque backend crash (zhi 019f26a5).
        my @input_idx = ($nd->{inputs} // [])->@*;
        my $phi_backedge_slot =
            ($op eq 'Phi' && @input_idx == 2 && $input_idx[1] >= @nodes) ? 1 : -1;
        for my $slot (0 .. $#input_idx) {
            my $idx = $input_idx[$slot];
            next if $slot == $phi_backedge_slot;   # sanctioned deferred backedge
            next if defined $idx && $idx >= 0 && $idx < @nodes;
            die "IR load: node #" . scalar(@nodes) . " ($op) input slot $slot "
              . "references index " . ($idx // 'undef') . ", which is not an "
              . "already-created node (have " . scalar(@nodes) . "); an "
              . "unresolvable forward input reference is a producer ordering bug.";
        }
        my @inputs = map { $nodes[$_] } @input_idx;

        # Build the argument hash, with inputs and any extra fields
        my %args = (inputs => \@inputs);

        # Merge extra fields based on op type.
        # For fields Chalk nodes don't support, we silently drop them.
        if ($op eq 'Constant') {
            $args{value}      = $fields->{value};
            $args{const_type} = $fields->{const_type} if exists $fields->{const_type};
        }
        elsif ($op eq 'AnonSub') {
            # The body's methods key. Without it the node falls back to a
            # construction counter, and a reloaded AnonSub hashes differently
            # from the graph that produced it.
            $args{name} = $fields->{name} if exists $fields->{name};
        }
        elsif ($op eq 'MakeCell') {
            # The captured variable's name, for diagnostics.
            $args{cell_name} = $fields->{cell_name}
                if exists $fields->{cell_name};
            # WHETHER ANY CLOSURE WRITES THROUGH THIS CELL. A read-only capture
            # lowers to a plain value with no allocation, so this decides
            # whether the cell exists at all at runtime.
            #
            # NOT INVENTED WHEN ABSENT. Defaulting a missing flag to false would
            # elide a cell that is in fact written -- dropping the write, a
            # miscompile. The class defaults it to 0 for a frontend-built node
            # with no wire record; a wire that omits it for a real capture is a
            # producer defect, and the honest failure is the missing write
            # showing up in the behavioural corpus rather than a guess here.
            $args{captured_written} = $fields->{captured_written} ? 1 : 0
                if exists $fields->{captured_written};
        }
        elsif ($op eq 'CellParam') {
            # Position within the closure's CELL inputs -- not the caller's
            # argument list. See CellParam.pm on why this is not a Parameter.
            $args{index} = $fields->{index} if exists $fields->{index};
            $args{name}  = $fields->{name}  if exists $fields->{name};
        }
        elsif ($op eq 'Call') {
            $args{dispatch_kind} = $fields->{dispatch_kind};
            $args{name}          = $fields->{name};
            $args{param_names}   = $fields->{param_names}
                if exists $fields->{param_names};
            $args{want}          = $fields->{want} if exists $fields->{want};
            # THE LAST INPUT IS MEMORY, not an argument: a builtin that reads
            # or writes an aggregate (push, shift, ...) follows a memory
            # version. Dropped, push took its MemStart for a value to append.
            $args{memory_input}  = 1 if $fields->{memory_input};
            $args{class_name}    = $fields->{class_name}
                if exists $fields->{class_name};
            $args{paren_form}    = $fields->{paren_form}
                if exists $fields->{paren_form};
            # A folded sort states what it compares and in which direction
            # (perl5-son ebb46f0). The comment above this block -- "for fields
            # Chalk nodes don't support, we silently drop them" -- is exactly
            # how these would go missing, so they are named here rather than
            # left to the default.
            $args{sort_cmp}      = $fields->{sort_cmp}
                if exists $fields->{sort_cmp};
            $args{sort_order}    = $fields->{sort_order}
                if exists $fields->{sort_order};
        }
        elsif ($op eq 'Phi') {
            $args{region} = $nodes[ $fields->{region} ];

            # predecessors[i] is the Proj that inputs[i] arrives along, carried
            # as node indices. It makes arm identity a field read instead of a
            # backward control-chain search -- see
            # docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md.
            #
            # Optional on the wire (a loop Phi records none), and dropped
            # wholesale if any index fails to resolve: the consumer pairs by
            # POSITION, so a partial list would silently mis-pair, which is the
            # exact failure this field exists to remove.
            if (my $pred_ix = $fields->{predecessors}) {
                my @preds = map { $nodes[$_] } @$pred_ix;
                $args{predecessors} = \@preds
                    unless grep { !defined } @preds;
            }
            # A loop Phi's backedge input (inputs[1]) may reference a node
            # LATER in the array -- the Phi<->backedge data cycle forces one
            # forward edge in any serialization order, and a forward index
            # resolves to undef in the single pass above. Defer it: construct
            # the Phi with its init input only and wire inputs[1] via
            # set_backedge once every node exists (the same post-construction
            # patch the corpus builder uses for loop_backedge edges).
            my @idx = ($nd->{inputs} // [])->@*;
            if (@idx == 2 && $idx[1] >= @nodes) {
                push @backedge_patches, [ scalar @nodes, $idx[1] ];
                $args{inputs} = [ $inputs[0] ];
            }
        }
        elsif ($op eq 'Proj') {
            $args{index} = $fields->{index};
        }
        elsif ($op eq 'PadAccess') {
            $args{targ} = $fields->{targ};
            # REQUIRED, not defaulted, for the reason spelled out on EntryDef
            # below: the sigil is identity-bearing, and defaulting one invents
            # an identity. A wire carrying the pre-split `varname` blob reaches
            # here with no sigil, and must fail LOUDLY rather than hash-cons
            # `$a` and `@a` together.
            die "GAP: PadAccess '" . ($fields->{symbol} // '?')
              . "' arrived with no sigil -- the wire predates the sigil/symbol "
              . "split (perl5-son 2aa5fd7), or the producer failed to stamp it."
                unless defined $fields->{sigil};
            $args{sigil}  = $fields->{sigil};
            $args{symbol} = $fields->{symbol};
            # A FILE LEXICAL A NAMED SUB SHARES is a location, read and written
            # through memory -- the backend lowers it to a module global.
            $args{shared} = 1 if $fields->{shared};
            # ...and what it holds is whatever was last stored, from any graph:
            # a Scalar, which the backend reads as its Slot. Unknown (nothing
            # typed it) is what a read stamped where no store is in sight says.
            # A `my $x` KEPT IN MEMORY (its input a memory version, not a
            # VarDecl -- handed to a call) is a location too, and likewise.
            my $location = $fields->{shared}
                || ( ( $fields->{sigil} // '' ) eq '$' && blessed($inputs[0])
                     && $inputs[0]->operation ne 'VarDecl' );
            $nd->{stamp} = 'Scalar'
                if $location && ( $nd->{stamp} // 'Unknown' ) eq 'Unknown';
            # AN @ VARIABLE IS AN ARRAY, a % one a HASH, whatever inference
            # missed: `my @r;` arrives as a bare PadAccess stamped Unknown.
            if (( $nd->{stamp} // 'Unknown' ) eq 'Unknown' && !$fields->{shared}) {
                $nd->{stamp} = 'Array' if ( $fields->{sigil} // '' ) eq '@';
                $nd->{stamp} = 'Hash'  if ( $fields->{sigil} // '' ) eq '%';
            }
        }
        elsif ($op eq 'Parameter') {
            # index is REQUIRED -- it is the node's identity. A missing one is a
            # producer/loader disagreement, not something to default away.
            $args{index} = $fields->{index};
            $args{name}  = $fields->{name};
            $args{sigil} = $fields->{sigil} // '$';
        }
        elsif ($op eq 'FieldAccess') {
            $args{field_index} = $fields->{field_index};
            $args{field_stash} = $fields->{field_stash};
        }
        elsif ($op eq 'CompoundAssign') {
            $args{op} = $fields->{op};
        }
        elsif ($op eq 'PostfixDeref') {
            $args{sigil} = $fields->{sigil};
        }
        elsif ($op eq 'EntryDef') {
            $args{package} = $fields->{package} // '';
            $args{symbol}  = $fields->{symbol}  // '';
            # REQUIRED, not defaulted. `_` alone names three different things
            # ($_, @_, and the `-f _` filetest handle), so a wire without a
            # sigil does not identify a variable -- defaulting one here would
            # invent an identity and re-merge what the producer kept apart.
            die "GAP: EntryDef '" . ($fields->{symbol} // '?')
              . "' arrived with no sigil -- the wire predates sigil-qualified "
              . "stash identity, or the producer failed to stamp it."
                unless defined $fields->{sigil};
            $args{sigil}   = $fields->{sigil};
        }
        elsif ($op eq 'RegexMatch') {
            $args{pattern} = $fields->{pattern} // '';
            $args{flags}   = $fields->{flags}   // '';
        }
        elsif ($op eq 'RegexSubst') {
            $args{pattern}     = $fields->{pattern}     // '';
            $args{replacement} = $fields->{replacement} // '';
            $args{flags}       = $fields->{flags}       // '';
        }
        elsif ($op eq 'RegexCapture') {
            $args{n} = $fields->{n};
        }
        elsif ($op eq 'EnvRead') {
            $args{key} = $fields->{key};
        }
        # B::SoN's ops the backend does not lower yet still LOAD, so it can say
        # by name what it lacks instead of the loader dying on the op.
        elsif ($op =~ /\A(?:Exists|Delete|ElemRestore|Chomp|ChompValue)\z/) {
            $args{kind} = $fields->{kind} if defined $fields->{kind};
        }
        elsif ($op eq 'EntryWrite') {
            $args{binds} = $fields->{binds} ? 1 : 0;
        }
        elsif ($op eq 'LocalAlias') {
            $args{name} = $fields->{name} if defined $fields->{name};
        }
        elsif ($op eq 'PackageMark') {
            $args{package} = $fields->{package};
        }
        elsif ($op eq 'Transliterate') {
            $args{$_} = $fields->{$_} // '' for qw(from to flags);
        }
        elsif ($op eq 'VarDecl') {
            $args{scope} = $fields->{scope} // 'my';
        }
        elsif ($op eq 'Coerce') {
            # from_repr/to_repr are REPRESENTATIONS named in the producer's stamp
            # vocabulary. The two vocabularies now agree name-for-name, so these
            # pass straight through; the reconciliation that used to happen here
            # existed only for Boolean, which chalk spelled 'Bool'.
            $args{from_repr} = $fields->{from_repr};
            $args{to_repr}   = $fields->{to_repr};
        }

        my $node;
        if ($is_cfg) {
            $node = $factory->make_cfg($op, %args);
        }
        else {
            $node = $factory->make($op, %args);
        }

        # Produce-time control: decode a genuine control_in wire key, emitted
        # by to_json for a graph built with control_in set directly (never
        # flattened into inputs[0]). Control-aware topo (_all_nodes_topo)
        # guarantees a node's control predecessor is always serialized
        # before it, so the referenced index is always already constructed
        # here.
        if (defined $nd->{control_in}) {
            $node->set_control_in($nodes[ $nd->{control_in} ]);
        }

        # Produce-time head/region: decode the genuine head wire key, emitted
        # by to_json for a Region whose owning If/Loop was set at produce
        # time (set_region installs both If.region and Region.head). The
        # owning If/Loop is always a control predecessor of the Region, so
        # control-aware topo guarantees it is already constructed here --
        # no defer-patch needed, unlike the loop-Phi backedge.
        if ($op eq 'Region' && defined $nd->{head}) {
            $nodes[ $nd->{head} ]->set_region($node);
        }

        # Map a B::SoN stamp to a Chalk representation so the backend can lower
        # the node runtime-free. Chalk's own serializer emits no stamp, so this
        # only fires for B::SoN-produced JSON.
        if (is_lowerable_stamp($nd->{stamp})) {
            $node->set_stamp($nd->{stamp});
        }
        # `Unknown` IS A TYPE AND MUST BE CARRIED, even though it is not
        # lowerable. The gate above answers "does this stamp have a machine
        # encoding?" and `Unknown` honestly does not -- so widening that gate
        # would break its stated contract with the backend. This is a separate
        # admission answering a different question: does T1 have an OPINION
        # about this node?
        #
        # WHY IT MATTERS. Dropping it turns a node the producer typed
        # `Unknown` ("inference ran and could not decide") into a node with NO
        # stamp ("inference never reached this"), which are different claims.
        # Measured on corpus T14 (`exit 4 if $c`): the wire says
        # `Call(exit) stamp=Unknown` and T1 finished with that node untyped,
        # because the answer was discarded here -- the comment below already
        # names the mechanism, "by the time any later pass looks the wire's
        # answer is gone".
        #
        # THE INVARIANT THIS SERVES: every Value node carries a stamp after T1,
        # with `Unknown` as the honest answer where nothing could be derived
        # (_assert_value_nodes_are_typed). Absence stops being a state a value
        # node can be in, which is what lets `_is_narrowed` be the only
        # question consumers ask.
        #
        # NOT A LICENCE TO SYNTHESIZE. This carries an answer the producer
        # gave; it does not invent one. A node the wire left unstamped stays
        # unstamped here and is T1's to derive or to declare Unknown for.
        #
        # ANY LATTICE TYPE, not just `Unknown`. Measured across the corpus and
        # the ir/data fixtures, the wire sends four types this gate was
        # dropping -- `Unknown`, `List`, `Code`, `ScalarRef` -- and every one is
        # a genuine lattice member that simply has no machine encoding:
        #
        #     List       lattice=yes  lowerable=no
        #     Code       lattice=yes  lowerable=no
        #     ScalarRef  lattice=yes  lowerable=no
        #     Unknown    lattice=yes  lowerable=no
        #
        # An `Unknown`-only special case was the first fix here and it was too
        # narrow: it closed the two untyped `Call` roots in the corpus and left
        # nine ir/ fixtures failing on `AnonSub`(Code), `Ref`(ScalarRef),
        # `ArrayLiteral`(List) and `FieldAccess`. Same defect, four values.
        elsif (defined $nd->{stamp}
               && Chalk::Grammar::Perl::TypeLibrary::is_lattice_type($nd->{stamp})) {
            $node->set_stamp($nd->{stamp});
        }

        # A BUILTIN CALL STAMPED `List` YIELDS AN AGGREGATE, and its consumers
        # need a representation before lowering -- _require_repr runs as a
        # pre-pass, so `Count(keys %h)` died on an operand with none.
        #
        # This must happen HERE and cannot happen in Analysis: `stamp` and
        # `representation` are ONE field, and is_lowerable_stamp above
        # deliberately drops `List`, so by the time any later pass looks the
        # wire's answer is gone. $nd->{stamp} is the last place it exists.
        #
        # `Array`, not `List`. List is the right TYPE and an invalid
        # REPRESENTATION -- arity-polymorphic, refused by name in
        # %_REPR_NO_MACHINE_TYPE -- and what enters this field must be an
        # encoding. The encoding of a materialised list of scalars is %Array*.
        #
        # Keyed on the stamp the producer computed from the CALLSITE'S OWN
        # CONTEXT (want=3 gives List, want=2 gives Int), not on a builtin-name
        # table here: `keys` is a count in scalar context and the keys in list
        # context, so a name table would be vaguer than the op. TypeLibrary
        # has no `keys` row for exactly that reason.
        # THE ARGUMENT IS ABOUT THE VALUE, NOT THE OP that produced it, so the
        # rescue covers an ArrayLiteral too. `my @g = grep { ... } (3,1,2)`
        # stamps its SOURCE LIST `List` on the wire; the drop above then left
        # it with no representation and the backend refused at
        # "Length.operand ... with NO representation (undef)" -- a message that
        # names TypeInference and sends the reader to the wrong layer, because
        # nothing had failed to infer. The answer was on the wire and this
        # filter discarded it.
        #
        # Scoped to the ops that MATERIALISE a list of scalars -- a builtin
        # Call and a literal. It is deliberately NOT every List-stamped node:
        # the drop exists because `List` is arity-polymorphic and most things
        # wearing it have no single encoding, and re-stamping all of them
        # `Array` would be exactly the guess the drop prevents.
        if (($nd->{stamp} // '') eq 'List'
                && ( $op eq 'ArrayLiteral'
                  || ($op eq 'Call'
                      && ($fields->{dispatch_kind} // '') eq 'builtin') )) {
            $node->set_stamp('Array');
        }

        # A Print carries no stamp (the producer leaves it unstamped), but perl's
        # print returns a genuine boolean (builtin::is_bool true), so a
        # value-context `my $ok = print ...` reads Bool:1. Seed the repr as Boolean
        # so the return epilogue tags it correctly.
        if ($op eq 'Print') {
            $node->set_stamp('Boolean');
        }

        push @nodes, $node;
    }

    # Wire the deferred loop-Phi backedges now that every node exists.
    for my $patch (@backedge_patches) {
        my ($phi_idx, $val_idx) = @$patch;
        $nodes[$phi_idx]->set_backedge($nodes[$val_idx]);
    }

    my $start   = $nodes[ $method_data->{start} ];
    my @returns = map { $nodes[$_] } $method_data->{returns}->@*;

    my $graph = Chalk::IR::Graph->new(start => $start, returns => \@returns);

    # A statement-effect node reachable ONLY through a Return's control_in chain
    # (a field store in an ADJUST body, whose result value is not the Return
    # value) is not seeded by start/returns and would be dropped from the graph's
    # membership. Merge each Return's control_in chain so those stores count as
    # body statements (the ADJUST emitter reads graph->members).
    for my $r (@returns) {
        my $c = $r->can('control_in') ? $r->control_in : undef;
        my %seen;
        while (defined $c && blessed($c) && !$seen{ $c->id }++) {
            $graph->merge($c);
            $c = $c->can('control_in') ? $c->control_in : undef;
        }
    }

    return $graph;
}





# from_json($json_string) — deserialize JSON to named Chalk::IR::Graph instances.
# -----------------------------------------------------------------------
sub from_json ($json_string) {
    my $data    = JSON::PP->new->decode($json_string);

    # A BEGIN OR END BLOCK WITH EFFECTS OF ITS OWN is refused, not dropped:
    # only `methods` is loaded, so a program's `BEGIN { print }` and `END {
    # print }` vanished and it printed its main line alone. A `use` is a
    # BEGIN block too, and compile-time: ONE `require` of a module's file (or of a
    # perl version) and
    # import, unimport or VERSION calls on that module (`no` unimports, `use
    # X 1.0` checks a VERSION). Only that shape is let through -- the bare
    # names were, and a program's own `BEGIN { Foo->import }` and a `require`
    # of a file by path were dropped with whatever they printed.
    for my $p (($data->{phase_blocks} // [])->@*) {
        my @nodes = ($p->{nodes} // [])->@*;
        my %by_id = map { ( $_->{id} // '' ) => $_ } @nodes;
        my @calls = grep { ( $_->{op} // '' ) eq 'Call' } @nodes;
        my @req   = grep { ( ( $_->{fields} // {} )->{name} // '' ) eq 'require' } @calls;
        my $file  = @req == 1
            ? ( ( $by_id{ ( $req[0]{inputs} // [] )->[0] // '' } // {} )->{fields} // {} )->{value}
            : undef;
        my $module = defined $file && $file =~ m{\A(\w+(?:/\w+)*)\.pm\z}
            ? $1 =~ s{/}{::}gr : undef;
        # `use v5.42` requires a perl version: a number, and nothing else.
        my $is_version = @calls == 1 && @req == 1 && defined $file
            && $file =~ /\A\d+(?:\.\d+)*\z/;
        my $is_use = $is_version || defined $module && !grep {
            my $f = $_->{fields} // {};
            ( $f->{name} // '' ) ne 'require'
                && !( ( $f->{name} // '' ) =~ /\A(?:import|unimport|VERSION)\z/
                      && ( $f->{class_name} // '' ) eq $module )
        } @calls;
        my @effects = grep {
            ( $_->{op} // '' ) !~ /\A(?:Start|Constant|MemStart|Return)\z/
                && !( $is_use && ( $_->{op} // '' ) eq 'Call' )
        } @nodes;
        die "GAP: a $p->{phase} block with effects of its own is not lowered "
          . "(a BEGIN or END block runs outside the main program)\n" if @effects;
    }

    my %graphs;
    for my $name (sort keys $data->{methods}->%*) {
        $graphs{$name} = _deserialize_graph($data->{methods}{$name});
    }

    # ANALYSIS LIVES IN ITS OWN MODULE, BODIES AND ALL. The passes are not
    # deserialization -- every one takes graphs plus class metadata and none
    # touches the JSON -- so they are in Chalk::IR::Analysis.
    #
    # An earlier step moved only the CALL SEQUENCE and left the pass bodies
    # here, which made the two modules mutually dependent: Analysis called back
    # into this file, so a compile-time `use` on both sides was a load cycle and
    # only a runtime `require` broke it. That cycle was the code reporting that
    # the split was a file boundary rather than a real one. The bodies have now
    # moved too, the dependency points one way, and `use` at the top is enough.
    #
    # STILL TO DO, and this is the actual boundary: from_json should not call
    # this at all. The loader's job is to reproduce the graph the frontend
    # serialized -- typing it is T1's. The call stays only so the ~40 existing
    # callers keep working during the transition; measured by
    # t/bootstrap/ir/loader-reproduces-the-wire.t, it adds 16 stamps the wire
    # never sent. That number reaching zero is what finishing the split means.
    return Chalk::IR::Analysis->run(
        \%graphs, (ref $data->{classes} eq "HASH" ? $data->{classes} : undef));
}




















1;
