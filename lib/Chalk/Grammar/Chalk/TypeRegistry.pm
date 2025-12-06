# ABOUTME: Singleton registry managing class type namespace for forward references
# ABOUTME: Maps qualified class names to Class type instances, supporting lazy resolution
use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::TypeRegistry {
    # Registry storage: class_name => Class instance
    field %registry;

    # Singleton accessor (class method)
    sub instance($class = __PACKAGE__) {
        state $singleton = Chalk::Grammar::Chalk::TypeRegistry->new();
        return $singleton;
    }

    # Reset singleton (for testing)
    method reset() {
        %registry = ();
    }

    # Register a class type (prevents redefinition of complete classes)
    method register($name, $class_obj) {
        # Check if trying to redefine a complete class
        if (exists $registry{$name} && $registry{$name}->is_complete()) {
            die "Cannot redefine complete class '$name'";
        }

        $registry{$name} = $class_obj;
        return $class_obj;
    }

    # Lookup class type (auto-creates placeholder if not found)
    method lookup($name) {
        # Return existing class if found
        return $registry{$name} if exists $registry{$name};

        # Auto-create placeholder for forward reference
        require Chalk::Grammar::Chalk::Type::Class;
        my $placeholder = Chalk::Grammar::Chalk::Type::Class->new(
            class_name => $name,
            fields => undef  # incomplete
        );
        $registry{$name} = $placeholder;
        return $placeholder;
    }

    # Check if class is registered
    method has_class($name) {
        return exists $registry{$name};
    }

    # Check if class has complete field definitions
    method is_complete($name) {
        return 0 unless exists $registry{$name};
        return $registry{$name}->is_complete();
    }
}

1;
