# ABOUTME: Type lattice implementation for Chalk grammar
# ABOUTME: Wraps Chalk::Grammar::Chalk::Type::* system to provide type operations for IR validation
# See docs/type-system.md for hierarchy (Int <: Num <: Str <: Scalar) and lattice operations (meet/join)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Grammar::Chalk::TypeLattice {
    use Chalk::Grammar::Chalk::Type::Any;
    use Chalk::Grammar::Chalk::Type::Array;
    use Chalk::Grammar::Chalk::Type::Boolean;
    use Chalk::Grammar::Chalk::Type::Hash;
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::List;
    use Chalk::Grammar::Chalk::Type::Num;
    use Chalk::Grammar::Chalk::Type::Object;
    use Chalk::Grammar::Chalk::Type::Scalar;
    use Chalk::Grammar::Chalk::Type::Str;
    use Chalk::Grammar::Chalk::Type::Undef;

    # Type inference: Infer type object from IR node operation
    method infer_type_from_operation($op, $node = undef) {
        # Constants - check node attributes for type
        if ($op eq 'Constant') {
            return $self->_infer_constant_type($node) if defined $node;
            return Chalk::Grammar::Chalk::Type::Int->new();  # Default
        }

        # Collection types (with default Any element/value types)
        return Chalk::Grammar::Chalk::Type::Array->new(
            element_type => Chalk::Grammar::Chalk::Type::Any->new()
        ) if $op eq 'ArrayValue';
        return Chalk::Grammar::Chalk::Type::Hash->new(
            value_type => Chalk::Grammar::Chalk::Type::Any->new()
        ) if $op eq 'HashValue';

        # Object construction
        if ($op eq 'New') {
            return Chalk::Grammar::Chalk::Type::Object->new() if defined $node;
        }

        # Arithmetic operations return Num
        return Chalk::Grammar::Chalk::Type::Num->new()
            if $op =~ qr/^(Add|Subtract|Multiply|Divide|Negate)$/;

        # Numeric comparison operations return Boolean
        return Chalk::Grammar::Chalk::Type::Boolean->new()
            if $op =~ qr/^(GT|LT|EQ|NE|GE|LE)$/;

        # String comparison operations return Boolean
        return Chalk::Grammar::Chalk::Type::Boolean->new()
            if $op =~ qr/^(StrEQ|StrNE|StrLT|StrLE|StrGT|StrGE)$/;

        # Logical operations return Boolean
        return Chalk::Grammar::Chalk::Type::Boolean->new()
            if $op =~ qr/^(And|Or|Not)$/;

        # String operations return Str
        return Chalk::Grammar::Chalk::Type::Str->new() if $op eq 'Concat';

        # Array/Hash access - unknown type
        return Chalk::Grammar::Chalk::Type::Any->new()
            if $op =~ qr/^(ArrayGet|HashGet)$/;

        # Unknown - return Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Helper: Infer type from Constant node attributes
    method _infer_constant_type($node) {
        my $attrs = $node->attributes;
        my $type_name = $attrs->{type} if defined $attrs;

        return Chalk::Grammar::Chalk::Type::Int->new() if !defined($type_name) || $type_name eq 'Int';
        return Chalk::Grammar::Chalk::Type::Num->new() if $type_name eq 'Num';
        return Chalk::Grammar::Chalk::Type::Str->new() if $type_name eq 'Str';
        return Chalk::Grammar::Chalk::Type::Boolean->new() if $type_name eq 'Bool' || $type_name eq 'Boolean';
        return Chalk::Grammar::Chalk::Type::Undef->new() if $type_name eq 'Undef';

        # Default to Any for unknown type names
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Check if operation is valid for given types
    method validate_operation($op, $left_type, $right_type) {
        # Arithmetic operations require numeric types
        if ($op =~ qr/^(Add|Subtract|Multiply|Divide)$/) {
            return $self->_check_numeric_operation($left_type, $right_type);
        }

        # String concatenation prefers strings but accepts anything
        if ($op eq 'Concat') {
            return { valid => 1 };  # Always valid - coerces to string
        }

        # Comparison operations accept compatible types
        if ($op =~ qr/^(GT|LT|EQ|NE|GE|LE)$/) {
            return $self->_check_comparison_operation($left_type, $right_type);
        }

        # Unknown operation - assume valid
        return { valid => 1 };
    }

    # Helper: Check numeric operation validity
    method _check_numeric_operation($left_type, $right_type) {
        my $num_type = Chalk::Grammar::Chalk::Type::Num->new();

        # Check if types are compatible with Num
        my $left_ok = !defined($left_type) ||
                      $left_type->is_subtype_of($num_type) ||
                      $num_type->is_compatible_with($left_type);

        my $right_ok = !defined($right_type) ||
                       $right_type->is_subtype_of($num_type) ||
                       $num_type->is_compatible_with($right_type);

        if (!$left_ok || !$right_ok) {
            return {
                valid => 0,
                error => "Type mismatch in numeric operation",
                expected => "Num",
                got_left => $left_type ? $left_type->name() : "unknown",
                got_right => $right_type ? $right_type->name() : "unknown",
            };
        }

        return { valid => 1 };
    }

    # Helper: Check comparison operation validity
    method _check_comparison_operation($left_type, $right_type) {
        # Comparisons work if types are compatible
        if (defined($left_type) && defined($right_type)) {
            if (!$left_type->is_compatible_with($right_type)) {
                return {
                    valid => 0,
                    error => "Incompatible types in comparison",
                    got_left => $left_type->name(),
                    got_right => $right_type->name(),
                };
            }
        }

        return { valid => 1 };
    }

    # Get type name as string
    method type_name($type_obj) {
        return "unknown" unless defined $type_obj;
        return $type_obj->name();
    }

    # Create type from name string (for backward compatibility)
    method type_from_name($name) {
        return Chalk::Grammar::Chalk::Type::Int->new() if $name eq 'Int';
        return Chalk::Grammar::Chalk::Type::Num->new() if $name eq 'Num';
        return Chalk::Grammar::Chalk::Type::Str->new() if $name eq 'Str';
        return Chalk::Grammar::Chalk::Type::Scalar->new() if $name eq 'Scalar';
        return Chalk::Grammar::Chalk::Type::Array->new(
            element_type => Chalk::Grammar::Chalk::Type::Any->new()
        ) if $name eq 'Array';
        return Chalk::Grammar::Chalk::Type::Hash->new(
            value_type => Chalk::Grammar::Chalk::Type::Any->new()
        ) if $name eq 'Hash';
        return Chalk::Grammar::Chalk::Type::List->new() if $name eq 'List';
        return Chalk::Grammar::Chalk::Type::Boolean->new() if $name eq 'Bool' || $name eq 'Boolean';
        return Chalk::Grammar::Chalk::Type::Undef->new() if $name eq 'Undef';
        return Chalk::Grammar::Chalk::Type::Any->new() if $name eq 'Any';
        return Chalk::Grammar::Chalk::Type::Object->new() if $name =~ qr/^Object/;

        # Unknown type defaults to Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Lattice operations - compute meet (greatest lower bound)
    method meet($type_a, $type_b) {
        return $type_a->meet($type_b);
    }

    # Lattice operations - compute join (least upper bound)
    method join($type_a, $type_b) {
        return $type_a->join($type_b);
    }

    # Compute meet of multiple types
    method meet_all(@types) {
        return Chalk::Grammar::Chalk::Type::Any->new() unless @types;
        my $result = shift(@types);
        for my $type (@types) {
            $result = $result->meet($type);
        }
        return $result;
    }

    # Compute join of multiple types
    method join_all(@types) {
        use Chalk::Grammar::Chalk::Type::None;
        return Chalk::Grammar::Chalk::Type::None->new() unless @types;
        my $result = shift(@types);
        for my $type (@types) {
            $result = $result->join($type);
        }
        return $result;
    }

    # Check if two types are compatible (have non-None meet)
    method are_compatible($type_a, $type_b) {
        my $meet = $type_a->meet($type_b);
        return !$meet->is_bottom();
    }

    # Get the top type (Any)
    method top_type() {
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Get the bottom type (None)
    method bottom_type() {
        use Chalk::Grammar::Chalk::Type::None;
        return Chalk::Grammar::Chalk::Type::None->new();
    }
}

1;
