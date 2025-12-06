# ABOUTME: Class type representing user-defined class instances in Chalk type system
# ABOUTME: Supports forward references via placeholders and auto-deepening for lazy resolution

use 5.042;
use experimental qw(class keyword_any);

class Chalk::Grammar::Chalk::Type::Class :isa(Chalk::Grammar::Chalk::Type) {
    # Qualified class name as string
    field $class_name :param :reader;

    # Hashref {field_name => Type} or undef for placeholders
    field $fields :param :reader = undef;

    method is_complete() {
        return defined $fields;
    }

    method name() {
        return "Class($class_name)";
    }

    method has_field($field_name) {
        # Auto-deepening: delegate to registry if incomplete
        unless (defined $fields) {
            require Chalk::Grammar::Chalk::TypeRegistry;
            my $complete = Chalk::Grammar::Chalk::TypeRegistry->instance()->lookup($class_name);

            # Prevent infinite recursion if class is still incomplete
            return 0 if $complete == $self || !$complete->is_complete();

            return $complete->has_field($field_name);
        }

        return exists $fields->{$field_name};
    }

    method field_type($field_name) {
        # Auto-deepening: delegate to registry if incomplete
        unless (defined $fields) {
            require Chalk::Grammar::Chalk::TypeRegistry;
            my $complete = Chalk::Grammar::Chalk::TypeRegistry->instance()->lookup($class_name);

            # Prevent infinite recursion if class is still incomplete
            unless ($complete != $self && $complete->is_complete()) {
                die "Cannot access fields on incomplete class '$class_name'";
            }

            return $complete->field_type($field_name);
        }

        unless (exists $fields->{$field_name}) {
            die "No field $field_name in class $class_name";
        }

        return $fields->{$field_name};
    }

    method is_subtype_of($other) {
        # Nominal typing: Class("X") <: Class("X") (reflexive)
        if (ref($other) eq 'Chalk::Grammar::Chalk::Type::Class') {
            # Same class name => subtype (reflexive)
            return $self->class_name() eq $other->class_name();
        }

        # Class <: Object <: Ref <: Scalar <: Any
        return any { $other isa $_ } qw(
            Chalk::Grammar::Chalk::Type::Object
            Chalk::Grammar::Chalk::Type::Ref
            Chalk::Grammar::Chalk::Type::Scalar
            Chalk::Grammar::Chalk::Type::Any
        );
    }
}

1;
