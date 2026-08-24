# ABOUTME: Well-typed-graph invariant checker for the typed-IR-representation model.
# ABOUTME: Checks a Graph and flags unbridged representation mismatches (H2 from the arch review).
package Chalk::IR::Graph::TypedInvariant;
use 5.42.0;
use utf8;

use Scalar::Util qw(blessed);

use Chalk::IR::Node::Coerce;
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype: Int <: Num

# Required-operand-representation for each operation.
# Values may be a single string (all inputs must carry that repr) or an
# arrayref of strings (inputs must carry ONE of the listed reprs — used for
# polymorphic unary ops like Length which accept Array or Str).
# An op listed here requires ALL its data inputs to carry the given representation
# (or be a Coerce node whose to_repr equals that representation).
# Only ops whose operand representations are structurally enforced at the IR level
# are listed. Ops NOT listed here are unchecked (the invariant applies only to
# operations with a declared requirement).
my %OP_REQUIRED_REPR = (
    # Add/Subtract/Multiply take their requirement from the NODE, not from this
    # table — see %OP_REQUIRES_OWN_REPR below. The entry is the fallback for an
    # unstamped node only. These read 'Int' until Num package scalars lowered,
    # which contradicted the backend's own contract (Context.pm:703) the moment
    # a Num could reach one.
    Add      => 'Num',
    Subtract => 'Num',
    Multiply => 'Num',
    Divide   => 'Num',  # Perl `/` is always float division; inputs must be Num
    Modulo   => 'Int',  # perl's `%` is integer-valued
    Concat   => 'Str',  # String concatenation requires Str operands (G3)
    Length   => [qw(Array ArrayRef Hash HashRef Str)],  # scalar @arr (count), scalar %h (key count), or length($str); operand must be Array/ArrayRef, Hash/HashRef, or Str
);

# Ops that are ONE operator applied at whatever representation their operands
# share, rather than a family of per-type operators. Add's signature is
# (Num, Num) -> Num; Int <: Num, so an all-Int application IS a Num application
# whose result stays in Int, and `add i64` is the representation chosen for it —
# an optimization, not a second integer-specific operator.
#
# Their operands are therefore required to match the NODE'S OWN representation,
# exactly. A mixed application is where the representations genuinely differ, and
# the producer bridges it with an explicit Coerce(Int->Num) at the build site
# (FromOptree, alongside Divide's), so by the time the graph is checked the
# operands are uniform and no relaxation is needed:
#
#   Add:Int over (Int, Int)            -> conforms, emits add i64
#   Add:Num over (Coerce->Num, Num)    -> conforms via the Coerce bridge
#   Add:Int over (Int, Num)            -> VIOLATION: an Add carrying a Num
#                                         operand cannot be stamped Int without
#                                         dropping the fraction
#
# Checking these against a fixed table entry instead cannot express that: 'Num'
# alone rejects the honest all-Int case, and 'Int' rejects the honest Num one.
my %OP_REQUIRES_OWN_REPR = map { $_ => 1 } qw(Add Subtract Multiply);

# _conforms($actual_repr, $op, \@allowed, $node_repr) -> bool
sub _conforms {
    my ($actual, $op, $allowed, $node_repr) = @_;
    return $actual eq ($node_repr // $allowed->[0]) ? true : false
        if $OP_REQUIRES_OWN_REPR{$op};
    return grep({ $actual eq $_ } $allowed->@*) ? true : false;
}

# _arm_proj_of($control) -> the Proj this arm hangs off, or undef.
#
# A Region input is the arm's LAST control node, not its Proj, so recovering
# arm IDENTITY means walking control_in back to the branch. Stops at another
# Region: its arms are a different question, and descending past it would
# attribute this arm to the wrong branch.
#
# Bounded by a seen-set. An arm's control chain is acyclic, but a loop
# back-edge elsewhere in the graph must not turn an unclassifiable shape into
# a hang -- the failure mode that made an earlier producer-side descent
# recurse forever. Mirrors SoN::FromOptree::StackSim::arm_proj, which is the
# producer's copy of the same walk.
sub _arm_proj_of {
    my ($node) = @_;
    my %seen;
    while (defined $node && blessed($node)) {
        my $id = $node->can('id') ? $node->id : undef;
        last if defined $id && $seen{$id}++;
        my $op = $node->can('operation') ? $node->operation : '';
        return $node if $op eq 'Proj';
        last if $op eq 'Region';
        $node = $node->can('control_in') ? $node->control_in : undef;
    }
    return undef;
}

# Per-position required representation for ops with different constraints at each input.
# Each entry maps op-name -> arrayref of per-position constraints, where each
# constraint is either undef (unchecked) or an arrayref of allowed repr strings.
# Position 0 is inputs->[0], position 1 is inputs->[1], etc.
my %OP_PER_POSITION_REPR = (
    # Subscript(container, key_or_index):
    #   inputs[0] = container — must be Array, Hash, ArrayRef, or HashRef
    #   inputs[1] = key/index — unchecked (Int for array, Str for hash, both valid)
    Subscript => [ [qw(Array Hash ArrayRef HashRef)], undef ],
    # PostfixDeref(ref):
    #   inputs[0] = the ref — must be ArrayRef or HashRef
    PostfixDeref => [ [qw(ArrayRef HashRef)] ],
);

# Ops whose graph presence requires a defined control_in — i.e. the producer
# (perl5-son) build-site policy pins these unconditionally onto the control
# chain so their effect is ordered and survives DCE. Derived from reading the
# producer's construction sites (perl5-son 40d8f8b), NOT from
# lib/Chalk/Bootstrap/Perl/Actions.pm's %STATEMENT_EFFECT_OPS threading
# (that table wires ten ops by POSITION, not by op, and never runs on
# producer-built graphs — using it to derive this set would be the wrong
# source; that mistake was already made twice):
#   Print   — FromOptree.pm:2091-2096, control-pinned when $sim->control is defined
#   Assign  — pinned at every element/field/stash/compound-assign build site
#             (e.g. FromOptree.pm:1722, :1774, :1790, :1812, :1953, :2006, :2285, :2292);
#             the single EXCEPTION is the generic list-assign fallback
#             (`my ($a,$b) = LIST`, FromOptree.pm:2067) which is unpinned —
#             no corpus case exercises that shape, so it is a known, undemonstrated
#             gap in producer coverage, not something this leg can special-case
#             without over-fitting to today's corpus.
#   Return  — FromOptree.pm _build_single_exit sets control_in from the exit's
#             control (single-exit) or the merged Region (multi-exit), :1717/:1949
#   Call    — pinned unconditionally as of producer 40d8f8b (R1.0 effect-by-default);
#             all three build sites (method dispatch :1149, direct call :1189,
#             builtin shift/pop :2163) call set_control_in before returning
#   Unwind  — pinned as of producer 2f5eb24 (die), FromOptree.pm:783-786
#
# NOT checked — RegexSubst / RegexMatch / Match: never pinned, in ANY position,
# at any of their producer build sites (FromOptree.pm:760, :1536, :1543 — bare
# make() calls, no set_control_in). The match family is instead
# value-ordered through its RegexCapture/Assign data edges: a following $N
# capture read or a `$s =~ ...` assignment target is itself an ordinary data
# consumer, so its position in the graph is fixed by dataflow, not by a
# control pin. This is evidence, not proof: a reviewer tried and could not
# construct a miscompile from an unpinned regex node (two ordered
# substitutions, two matches with both captures read, both matched perl), but
# that is not the same as proving it safe.
#
# NotMatch and BacktickExpr are absent from this set because they are absent
# from the PRODUCER, not merely absent from the corpus: NotMatch appears only
# as a member of the %COMPARISON_OP list (a Not(RegexMatch) is emitted
# instead — no distinct NotMatch node is ever built), and BacktickExpr has
# zero references anywhere in perl5-son's lib/. Neither op has a build site
# to police.
my @CONTROL_CHAIN_OPS = qw(Print Assign Return Call Unwind);
my %CONTROL_CHAIN_OP = map { $_ => 1 } @CONTROL_CHAIN_OPS;

# _check_repr_for_position($op, $i, $allowed_ref, $input, $violations_ref)
#
# $allowed_ref is an arrayref of allowed repr strings for position $i.
# Pushes to $violations_ref if the input's repr does not match.
sub _check_repr_for_position {
    my ($op, $i, $allowed_ref, $input, $violations_ref) = @_;
    my @allowed = $allowed_ref->@*;

    my $input_repr = $input->representation();
    return unless defined $input_repr;  # undef = not yet assigned; skip

    if ($input->isa('Chalk::IR::Node::Coerce')) {
        my $to = $input->to_repr();
        unless (grep { $to eq $_ } @allowed) {
            my $allowed_str = join(' or ', @allowed);
            push $violations_ref->@*, {
                node_id => $input->id(),
                message => sprintf(
                    'op %s at position %d: Coerce node to_repr=%s does not match required %s',
                    $op, $i, $to, $allowed_str
                ),
            };
        }
        return;
    }

    unless (grep { $input_repr eq $_ } @allowed) {
        my $allowed_str = join(' or ', @allowed);
        push $violations_ref->@*, {
            node_id => $input->id(),
            message => sprintf(
                'op %s input[%d] has representation=%s, required=%s, no Coerce bridge',
                $op, $i, $input_repr, $allowed_str
            ),
        };
    }
}

# check(\@nodes) -> { ok => bool, violations => [ { node_id, message } ] }
#
# Walks the provided node list. For each operation node whose operation() is
# in %OP_REQUIRED_REPR or %OP_PER_POSITION_REPR, checks that every input's
# representation either:
#   (a) matches the required representation, or
#   (b) is undef (not yet assigned — skip; undef is "not yet checked", not wrong), or
#   (c) the input is a Coerce node whose to_repr matches the required representation.
#
# Any other combination is a violation: the operand has a definite, wrong
# representation and no Coerce bridges the gap.
# check($graph) -> {ok, violations}
#
# THE ENTRY POINT. Takes a Chalk::IR::Graph, because the question this module
# exists to answer -- "is this graph well-typed?" -- is a property of a graph.
# A node list cannot answer it: it is whatever the caller assembled, so a
# missing node reads identically to a graph that never had one.
#
# This module's own comments recorded that limitation in three places while the
# signature was still a node list; the control-chain leg's is the clearest:
# "an effect reachable ONLY through control (not present in that node list) is
# invisible to it". Taking the graph is the first step toward closing it -- the
# walk below still uses ->nodes, so control-only reachability is NOT yet covered
# (see check_nodes' note), but the caller can no longer hand over a set that
# silently omits things.
#
# Slice 5 of docs/plans/2026-08-24-loader-analysis-pipeline.md runs this at the
# end of the analysis pipeline as the loader's exit gate.
sub check {
    my ($class, $graph) = @_;

    # An unmigrated caller passing an arrayref must fail loudly. Accepting it
    # would check a fragment while reading as a graph check -- and a caller
    # whose list happened to be empty would get a vacuous ok=1.
    unless (blessed($graph) && $graph->can('nodes')) {
        require Carp;
        Carp::croak(
            'TypedInvariant->check expects a Chalk::IR::Graph. To check a '
          . 'node fragment (no Start, no Return), call check_nodes(\\@nodes) '
          . '-- it answers a weaker question and is named for it.'
        );
    }

    return $class->check_nodes($graph->nodes);
}

# check_nodes(\@nodes) -> {ok, violations}
#
# Checks a FRAGMENT: a bare list of nodes, which may have no Start and no
# Return. This is the weaker question, and it is named differently so a caller
# cannot reach for it by accident.
#
# It exists for the unit tests that isolate ONE typing rule over three floating
# nodes (`[$lhs, $rhs, $add]`). Wrapping those in a synthetic Graph would give
# each a Start and a Return it does not care about, obscuring what it pins.
#
# WHAT IT CANNOT ANSWER, and why check($graph) is the real entry:
#   - completeness ("every Value node here is typed") is a claim about the
#     caller's list, not about a graph;
#   - reachability -- an orphaned node and a live one are indistinguishable;
#   - a node reachable only through the control chain is simply absent.
sub check_nodes {
    my ($class, $nodes) = @_;
    my @violations;

    for my $node ($nodes->@*) {
        # Skip metadata objects (ClassInfo, MethodInfo, MOP::Field) that are not
        # IR nodes — they do not carry an operation() and cannot be checked here.
        next unless $node->can('operation');
        my $op = $node->operation();

        # Control-chain leg: every node of a checked op PRESENT in the graph
        # must carry a defined control_in.
        #
        # LIMITS (read before relying on this leg for anything beyond what it
        # actually checks):
        #   - It polices a chain-break on a node that IS in the graph. It
        #     cannot catch a node the producer dropped ENTIRELY (the F4
        #     shape: the whole Call was missing, leaving Start/Constant/
        #     Return with nothing to flag) — there is no absence to detect.
        #   - It is a graph-shape check only; it cannot see a backend-scan
        #     regression (the F2 shape) because that is not a property of
        #     the graph at all.
        #   - It only receives the graph's node set (via $nodes->@*, i.e.
        #     $g->nodes), so an effect reachable ONLY through control (not
        #     present in that node list) is invisible to it.
        if ($CONTROL_CHAIN_OP{$op} && $node->can('control_in')) {
            unless (defined $node->control_in) {
                push @violations, {
                    node_id => $node->id(),
                    message => sprintf(
                        'op %s has undef control_in (broken effect chain)',
                        $op
                    ),
                };
            }
        }

        # PHI/REGION ARITY. A Phi's incoming values pair POSITIONALLY with its
        # Region's control inputs -- slot i comes from the predecessor at
        # Region input i -- so the two lists must have the same length.
        #
        # Nothing checked this. Chalk had THREE phi-pairing miscompiles in one
        # arc (44d1fa8c, 9ce43cdd) and no assertion would have caught any of
        # them. Every production Sea-of-Nodes IR has this check: C2's "broken
        # Phi/Region subgraph", Graal's
        # `phiPredecessorCount() == valueCount()`, TurboFan's
        # `CHECK_EQ(value_count, control->op()->ControlInputCount())`.
        #
        # HONEST LIMIT: arity does not catch a SWAPPED pairing of equal length,
        # which is what all three of those defects actually were. This is the
        # half checkable from the graph alone; it turns a length divergence
        # from silent into loud. The pairing half needs the structural change
        # in docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md
        # (store the Proj per value, or add an end-of-arm carrier).
        if ($op eq 'Phi' && $node->can('region')) {
            my $region = $node->region;
            if (defined $region && blessed($region)
                    && $region->can('inputs') && defined $region->inputs) {
                # Region inputs may be a flat list or one arrayref of controls.
                my @controls = $region->inputs->@*;
                @controls = $controls[0]->@*
                    if @controls == 1 && ref $controls[0] eq 'ARRAY';

                my $values = $node->inputs // [];

                # LOOP PHIS ARE EXEMPT, and the reason is structural rather
                # than a carve-out. A merge Phi pairs against a Region whose
                # control inputs are the arms. A LOOP Phi's `region` is the
                # Loop node ITSELF, and its two values are [init, backedge] --
                # which pair with the loop's ENTRY and BACK edges, not with a
                # list of merge predecessors. Measured: every one of the 16
                # corpus cases this leg first flagged was `Region Loop#2 has 1
                # control input`, i.e. exactly this shape, across D2/D2b/D2c/
                # D2d/D2e/D3 and friends. The backedge is also wired later via
                # Phi::set_backedge, so the counts legitimately disagree
                # mid-construction.
                #
                # Check the node the Phi points AT, not that node's head: for a
                # loop the Phi points at the Loop directly, so a head-based test
                # never fires.
                my $rop = $region->can('operation') ? $region->operation : '';
                my $head = $region->can('head') ? $region->head : undef;
                my $is_loop = $rop eq 'Loop'
                    || (defined $head && blessed($head)
                        && $head->can('operation') && $head->operation eq 'Loop');

                if (!$is_loop && @controls && scalar($values->@*) != scalar(@controls)) {
                    push @violations, {
                        node_id => $node->id(),
                        message => sprintf(
                            'Phi has %d incoming value(s) but its Region %s has %d control input(s); they pair by position, so the lengths must match',
                            scalar($values->@*), $region->id(), scalar(@controls)
                        ),
                    };
                }

                # PHI/REGION PAIRING -- the half arity cannot check. A swapped
                # pairing of equal length passes the arity check above, and that
                # is precisely what all three miscompiles were. The Phi must
                # RECORD which arm each value arrives from rather than leave the
                # consumer to search for it.
                #
                # THE TRIGGER IS NARROW, ON PURPOSE: required only when the
                # Region's control inputs RESOLVE TO PROJS, i.e. there are
                # genuinely named arms to point at. A Region input is the arm's
                # LAST control node, so the Proj is reached by walking control_in
                # back -- the same walk the producer does once at construction
                # (SoN::FromOptree::StackSim::arm_proj).
                #
                # Measured across chalk's 32 merge-Phi construction sites: 20
                # have Proj arms, 12 build a branchless Region to unit-test
                # something else (scope-trivial-phi.t on `Region(controls=>[])`).
                # Demanding predecessors of the latter would mean inventing an
                # If/Proj skeleton those tests do not care about. The exemption
                # is structural -- there is nothing to name -- not a carve-out.
                if (!$is_loop && @controls
                        && !defined $node->predecessors
                        && (grep { _arm_proj_of($_) } @controls) == @controls) {
                    push @violations, {
                        node_id => $node->id(),
                        message => sprintf(
                            'Phi records no predecessors, but every control input of its Region %s resolves to a Proj; a merge over named arms must say which value comes from which arm',
                            $region->id()
                        ),
                    };
                }
            }
        }

        if (my $per_pos = $OP_PER_POSITION_REPR{$op}) {
            # Per-position checking.
            my $inputs = $node->inputs();
            next unless defined $inputs;

            for my $i (0 .. $per_pos->$#*) {
                my $allowed_ref = $per_pos->[$i];
                next unless defined $allowed_ref;  # undef = unchecked at this position

                my $input = $inputs->[$i];
                next unless defined $input;
                next if ref($input) eq 'ARRAY';

                _check_repr_for_position($op, $i, $allowed_ref, $input, \@violations);
            }
            next;
        }

        my $required = $OP_REQUIRED_REPR{$op};
        next unless defined $required;

        # Normalize to arrayref of allowed reprs.
        my @allowed = ref($required) eq 'ARRAY' ? $required->@* : ($required);

        my $inputs = $node->inputs();
        next unless defined $inputs;

        for my $i (0 .. $inputs->$#*) {
            my $input = $inputs->[$i];
            next unless defined $input;
            # Skip nested arrayrefs (e.g. Call arg lists)
            next if ref($input) eq 'ARRAY';

            my $input_repr = $input->representation();
            # undef = not yet assigned; skip (not a violation)
            next unless defined $input_repr;

            # If the input IS a Coerce node, check its to_repr against allowed set
            if ($input->isa('Chalk::IR::Node::Coerce')) {
                my $to = $input->to_repr();
                unless (_conforms($to, $op, \@allowed, $node->representation())) {
                    my $allowed_str = join(' or ', @allowed);
                    push @violations, {
                        node_id => $node->id(),
                        message => sprintf(
                            'op %s at position %d: Coerce node to_repr=%s does not match required %s',
                            $op, $i, $to, $allowed_str
                        ),
                    };
                }
                next;
            }

            # Plain node: representation must conform to the allowed set —
            # exactly, or by subtyping for the ops that permit it.
            unless (_conforms($input_repr, $op, \@allowed, $node->representation())) {
                my $allowed_str = join(' or ', @allowed);
                push @violations, {
                    node_id => $node->id(),
                    message => sprintf(
                        'op %s input[%d] has representation=%s, required=%s, no Coerce bridge',
                        $op, $i, $input_repr, $allowed_str
                    ),
                };
            }
        }
    }

    return {
        ok         => @violations == 0 ? 1 : 0,
        violations => \@violations,
    };
}

1;
