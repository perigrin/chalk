# ABOUTME: Compile-time Meta Object Protocol for the Chalk compiler.
# ABOUTME: Owns the class registry and provides cross-class resolution protocols.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::MOP::Class;

class Chalk::MOP {
    field %classes;
    field $struct_promotion_schemas :reader = {};

    # The MOP is a parse-time accumulator: declare_* fires per member as the
    # Earley actions complete. seal() marks the moment construction ends —
    # post-parse consumers (the LLVM backend's class registry in particular)
    # read an enforceably immutable surface. Idempotent; propagates to every
    # registered class.
    field $sealed = false;

    # THE UNIT'S GRAPH REGISTRY -- the MOP is the unit handle (T1 spec §6).
    #
    # A Call answers "what does my callee return" from the graph it is already
    # in: graph -> mop -> graphs. Without this, reaching a sibling means a
    # lookup in a hash somebody passed alongside, which is the graph-set shape
    # §2 rejects. The registry satisfies §2's real prohibition -- no
    # Map<String,Graph> in a PUBLIC signature -- because it is reached THROUGH
    # the edge rather than passed beside it.
    #
    # Populated by the LOADER, where the `set_mop` sweep already runs, so it
    # survives the T1 split. NOT populated at construction: graphs necessarily
    # precede the MOP (the MOP is built FROM them), the same ordering that
    # forces Graph::set_mop to be a setter rather than a param.
    field %graph_registry;

    method graphs() { return { %graph_registry } }

    # WAS THIS CLASS DECLARED BY THE WIRE, as opposed to seeded?
    #
    # Chalk::MOP's ADJUST seeds `main` on every load, so `for_class('main')`
    # being true is NOT evidence the wire said anything about it -- a
    # distinction that cost a loader crash on any wire carrying subs and no
    # `classes` key (bc255ea3). The raw records answered this before; on the
    # protocol, the answer survives the seal, so an inference pass never needs
    # the wire section to ask.
    field %declared;
    method was_declared ($name) { return $declared{$name} ? true : false }
    method mark_declared ($name) { $declared{$name} = 1; return $self }

    method register_graphs($graphs) {
        # A copy, so a later mutation of the loader's private hash cannot
        # reach through the edge. The GRAPHS are shared by reference -- the
        # registry names the same objects, it does not clone them.
        %graph_registry = $graphs->%*;
        return $self;
    }

    method is_sealed() { return $sealed }

    method seal() {
        return if $sealed;
        $sealed = true;
        $_->seal for values %classes;
        return;
    }

    ADJUST {
        # Seed implicit main class — all code belongs to a class
        my $main = Chalk::MOP::Class->new(name => 'main', mop => $self);
        $classes{main} = $main;
    }

    # Side structure populated by the Phase 5 StructPromotion pass.
    # Holds the analyzed-but-not-yet-rewritten schema table; passed
    # downstream to codegen for struct emission.
    method set_struct_promotion_schemas($schemas) {
        $struct_promotion_schemas = $schemas;
        return;
    }

    method declare_class($name, %opts) {
        die "Chalk::MOP: declare_class('$name') on a sealed MOP — "
          . "construction ended at seal()" if $sealed;
        my $cls = Chalk::MOP::Class->new(
            name => $name,
            mop  => $self,
            %opts,
        );
        $classes{$name} = $cls;
        return $cls;
    }

    method classes() {
        return values %classes;
    }

    method for_class($name) {
        return $classes{$name};
    }

    # Resolve a method name across all known classes. Returns the first
    # Chalk::MOP::Method whose name matches, or undef when not found.
    # Used by Phase 4 CallExpression to attach a resolved callee handle
    # to Call IR nodes.
    method find_method($method_name) {
        for my $cls (values %classes) {
            for my $m ($cls->methods) {
                return $m if $m->name eq $method_name;
            }
        }
        return undef;
    }
}
