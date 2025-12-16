# ABOUTME: Chalk-specific type inference rules
# ABOUTME: Infers types from operations and usage patterns per Perl semantics

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::TypeInference {
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::Num;
    use Chalk::Grammar::Chalk::Type::Str;
    use Chalk::Grammar::Chalk::Type::Boolean;
    use Chalk::Grammar::Chalk::Type::Any;

    # Infer result type from binary operation
    method infer_binary_op($op, $left_type, $right_type) {
        # Arithmetic operators
        if ($op =~ /^[+\-*]$/) {
            return $self->_infer_arithmetic($left_type, $right_type);
        }

        # Division always yields Num
        if ($op eq '/') {
            return Chalk::Grammar::Chalk::Type::Num->new();
        }

        # String concatenation
        if ($op eq '.') {
            return Chalk::Grammar::Chalk::Type::Str->new();
        }

        # Comparison operators yield Boolean
        if ($op =~ /^(==|!=|<|>|<=|>=|eq|ne|lt|gt|le|ge)$/) {
            return Chalk::Grammar::Chalk::Type::Boolean->new();
        }

        # Unknown operator - return Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    method _infer_arithmetic($left_type, $right_type) {
        # If either is Num, result is Num
        if ($left_type isa Chalk::Grammar::Chalk::Type::Num ||
            $right_type isa Chalk::Grammar::Chalk::Type::Num) {
            return Chalk::Grammar::Chalk::Type::Num->new();
        }

        # Int op Int = Int
        if ($left_type isa Chalk::Grammar::Chalk::Type::Int &&
            $right_type isa Chalk::Grammar::Chalk::Type::Int) {
            return Chalk::Grammar::Chalk::Type::Int->new();
        }

        # Default to Num for other numeric contexts
        return Chalk::Grammar::Chalk::Type::Num->new();
    }
}

1;
