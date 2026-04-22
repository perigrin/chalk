# ABOUTME: Compile-time Meta Object Protocol for the Chalk compiler.
# ABOUTME: Owns the class registry and provides cross-class resolution protocols.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::MOP::Class;

class Chalk::MOP {
    field %classes;
    field $current_class :reader(current_class);

    ADJUST {
        # Seed implicit main class — all code belongs to a class
        my $main = Chalk::MOP::Class->new(name => 'main', mop => $self);
        $classes{main} = $main;
        $current_class = $main;
    }

    method set_current_class($class) {
        $current_class = $class;
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
}
