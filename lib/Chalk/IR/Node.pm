# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, use-def chains, content_hash, stamp, and compat_class fields.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node {

    # Stable content-based ID for the node
    field $id :param :reader;

    # Producer nodes - nodes that produce values consumed by this node
    field $inputs :param :reader = [];

    # Consumer nodes - nodes that consume values produced by this node
    # This is mutable to allow building the graph
    field $consumers :reader = [];

    # Optional stamp for identifying parse-origin or generation context
    field $stamp        :param :reader = undef;

    # Optional compat_class overrides the result of class() for back-compat
    field $compat_class :param :reader = undef;

    # Effect-chain predecessor when this node appears as a statement-position
    # side effect (bare Call, bare Assign, etc.). Set by the Block control-
    # chain fixup pass via set_control_in(); undef for nodes in pure-data
    # position. Not part of content_hash: side-effect vs pure-data uses of
    # the same content (e.g. `foo()` as statement vs as expression) should
    # still hash-cons to the same node; control_in is a per-use decoration.
    field $control_in :reader = undef;

    # Per-node scheduler interpretation, populated lazily by the scheduler
    # via set_schedule_data(). Holds a Chalk::Scheduler::ScheduleMeta
    # subclass instance whose dialect (EagerPinning, GCM, ...) matches the
    # scheduler that produced the current Schedule. Excluded from
    # content_hash for the same reason as control_in: it is a per-use
    # decoration, not a structural property of the node's content.
    field $schedule_data :reader = undef;

    # Machine-level representation of the value produced by this node.
    # Realized lattice (see typed-ir-representation.md): 'Bool' (i1),
    # 'Int' (i64), 'Num' (double/f64), 'Str' ({ptr,len,encoding}),
    # 'Undef'/'Slot' ({defined,payload}), 'Array' ({len,cap,Slot*}),
    # 'Hash' (linear-scan table), 'ArrayRef'/'HashRef' (i8* to the boxed
    # aggregate), 'Object' (i8* to {vtable*, Slot...}); plus the older
    # 'Ptr'/'Struct'/'Scalar' (boxed Perl SV*, conservative fallback).
    # Set post-construction by the IR builder or a lowering pass via
    # set_representation(); undef = not yet assigned.
    # Excluded from content_hash: representation is a per-use lowering
    # decision, not a structural property of what value the node IS. Two
    # nodes with identical content (same literal, same operation, same
    # inputs) must still hash-cons to one node regardless of what
    # representation the builder later assigns. Coerce nodes (§2 of
    # typed-ir-representation.md) bridge between representations on edges.
    field $representation :reader = undef;

    # Add a consumer to this node's consumer list
    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    # Remove a consumer from this node's consumer list
    method remove_consumer($node) {
        my $target_id = $node->id();
        $consumers->@* = grep { $_->id() ne $target_id } $consumers->@*;
    }

    # Abstract method - subclasses must implement
    method operation() {
        die ref($self) . " must implement operation()";
    }

    method class() {
        return $compat_class if defined $compat_class;
        return $self->operation();
    }

    # Serialize inputs to a list of ID strings for content_hash.
    # Handles undef, nested arrayrefs, and plain node inputs.
    method _serialize_inputs() {
        my @parts;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @parts, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @parts, '[' . join(',', @ids) . ']';
            } else {
                push @parts, $input->id();
            }
        }
        return @parts;
    }

    method content_hash() {
        return join('|', $self->operation(), $self->_serialize_inputs());
    }

    # Late-binding setter for the per-node scheduler interpretation.
    # Called by the scheduler as it walks the graph and decides what
    # surface syntax each control-affecting node should emit.
    method set_schedule_data($meta) {
        $schedule_data = $meta;
        return;
    }

    # Late-binding setter for the effect-chain predecessor.
    # Maintains the bidirectional use-def edge by adjusting consumer
    # registration on the old and new predecessors. Called by the
    # Block control-chain fixup pass in Perl::Actions when this node
    # appears as a statement-position side effect.
    method set_control_in($ctrl) {
        if (defined $control_in) {
            $control_in->remove_consumer($self);
        }
        $control_in = $ctrl;
        if (defined $ctrl) {
            $ctrl->add_consumer($self);
        }
        return;
    }

    # Late-binding setter for the machine-level representation.
    # Called by the IR builder or a lowering pass after the node is
    # constructed. Does not affect content_hash or hash-consing identity.
    method set_representation($repr) {
        $representation = $repr;
        return;
    }
}
