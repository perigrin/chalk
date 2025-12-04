# ABOUTME: MemoryPointer represents pointer/reference types in IR type lattice
# ABOUTME: Supports nullable/non-null pointers and struct type targeting

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::MemoryPointer :isa(Chalk::IR::Type) {
    field $struct_name :param :reader = undef;
    field $nullable :param :reader = 0;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Pointers are not constant values
    method is_top() { (!defined($struct_name) && !$is_bottom) ? 1 : 0 }

    # Convert a non-null pointer to nullable (widening operation)
    method to_nullable() {
        return $self if $nullable;  # Already nullable
        return __PACKAGE__->new(
            struct_name => $struct_name,
            nullable => 1,
            is_bottom => $is_bottom,
        );
    }

    # Convert a nullable pointer to non-null (narrowing operation, unsafe)
    method to_non_null() {
        return $self if !$nullable;  # Already non-null
        return __PACKAGE__->new(
            struct_name => $struct_name,
            nullable => 0,
            is_bottom => $is_bottom,
        );
    }

    sub TOP {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }

    sub BOTTOM {
        state $singleton = __PACKAGE__->new(is_bottom => 1);
        return $singleton;
    }

    sub NULL {
        # null is a nullable pointer to TOP (non-existent memory)
        state $singleton = __PACKAGE__->new(nullable => 1);
        return $singleton;
    }

    # meet() for TypePointer
    # Meet finds the most specific (narrowest) common type
    method meet($other) {
        # Handle global Bottom type - absorbs everything
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # PtrBot absorbs everything within pointer domain
        return __PACKAGE__->BOTTOM() if $self->is_bottom;
        return __PACKAGE__->BOTTOM() if $other isa __PACKAGE__ && $other->is_bottom;

        # PtrTop is identity for meet within pointer domain
        return $other if $self->is_top && $other isa __PACKAGE__;
        return $self if $other isa __PACKAGE__ && $other->is_top;

        # Both are pointers to specific types
        if ($other isa __PACKAGE__) {
            # Different struct types -> incompatible -> PtrTop
            if (defined($struct_name) && defined($other->struct_name)
                && $struct_name ne $other->struct_name) {
                return __PACKAGE__->TOP();
            }

            # Same struct type - meet on nullability
            # non-null meet nullable = non-null (more specific)
            # non-null meet non-null = non-null
            # nullable meet nullable = nullable
            my $result_nullable = $nullable && $other->nullable;
            my $result_struct = $struct_name // $other->struct_name;

            return __PACKAGE__->new(
                struct_name => $result_struct,
                nullable => $result_nullable,
            );
        }

        # Cross-type meet = global Top
        return Chalk::IR::Type::Top->top();
    }

    # join() for TypePointer
    # Join finds the least specific (broadest) common type
    method join($other) {
        # Handle global Bottom type - identity for join
        return $self if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - absorbs in join
        return $other if $other isa Chalk::IR::Type::Top;

        # PtrBot is identity for join within pointer domain
        return $other if $self->is_bottom && $other isa __PACKAGE__;
        return $self if $other isa __PACKAGE__ && $other->is_bottom;

        # PtrTop absorbs everything within pointer domain
        return __PACKAGE__->TOP() if $self->is_top;
        return __PACKAGE__->TOP() if $other isa __PACKAGE__ && $other->is_top;

        # Both are pointers to specific types
        if ($other isa __PACKAGE__) {
            # Different struct types -> unknown which -> PtrTop
            if (defined($struct_name) && defined($other->struct_name)
                && $struct_name ne $other->struct_name) {
                return __PACKAGE__->TOP();
            }

            # Same struct type - join on nullability
            # non-null join nullable = nullable (less specific)
            # non-null join non-null = non-null
            # nullable join nullable = nullable
            my $result_nullable = $nullable || $other->nullable;
            my $result_struct = $struct_name // $other->struct_name;

            return __PACKAGE__->new(
                struct_name => $result_struct,
                nullable => $result_nullable,
            );
        }

        # Cross-type join = global Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
