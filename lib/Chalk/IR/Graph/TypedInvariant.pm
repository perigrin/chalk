# ABOUTME: Well-typed-graph invariant checker for the typed-IR-representation model.
# ABOUTME: Walks a node list and flags unbridged representation mismatches (H2 from the arch review).
package Chalk::IR::Graph::TypedInvariant;
use 5.42.0;
use utf8;

use Chalk::IR::Node::Coerce;

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
    Add      => 'Int',
    Subtract => 'Int',
    Multiply => 'Int',
    Divide   => 'Num',  # Perl `/` is always float division; inputs must be Num
    Modulo   => 'Int',
    Concat   => 'Str',  # String concatenation requires Str operands (G3)
    Length   => [qw(Array ArrayRef Hash HashRef Str)],  # scalar @arr (count), scalar %h (key count), or length($str); operand must be Array/ArrayRef, Hash/HashRef, or Str
);

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
sub check {
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
                unless (grep { $to eq $_ } @allowed) {
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

            # Plain node: representation must be one of the allowed set
            unless (grep { $input_repr eq $_ } @allowed) {
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
