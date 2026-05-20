# ABOUTME: Compile-time Meta Object Protocol for the Chalk compiler.
# ABOUTME: Owns the class registry and provides cross-class resolution protocols.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::MOP::Class;

class Chalk::MOP {
    field %classes;

    ADJUST {
        # Seed implicit main class — all code belongs to a class
        my $main = Chalk::MOP::Class->new(name => 'main', mop => $self);
        $classes{main} = $main;
    }

    method declare_class($name, %opts) {
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
