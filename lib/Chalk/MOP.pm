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
