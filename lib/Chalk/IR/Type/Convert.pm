# ABOUTME: Type conversion utilities for Grammar→IR type mapping
# ABOUTME: Ensures clean type boundaries between parsing and optimization phases

use 5.42.0;
use experimental qw(class);

# Load all IR types
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Bool;
use Chalk::IR::Type::String;
use Chalk::IR::Type::Array;
use Chalk::IR::Type::Hash;
use Chalk::IR::Type::Code;
use Chalk::IR::Type::Ref;
use Chalk::IR::Type::Object;
use Chalk::IR::Type::Undef;
use Chalk::IR::Type::Scalar;

class Chalk::IR::Type::Convert {
    # Grammar type class -> IR type class mapping
    my %GRAMMAR_TO_IR = (
        # Numeric
        'Chalk::Grammar::Chalk::Type::Int'     => 'Chalk::IR::Type::Integer',
        'Chalk::Grammar::Chalk::Type::Num'     => 'Chalk::IR::Type::Float',
        'Chalk::Grammar::Chalk::Type::Boolean' => 'Chalk::IR::Type::Bool',

        # Strings
        'Chalk::Grammar::Chalk::Type::Str'     => 'Chalk::IR::Type::String',

        # Collections
        'Chalk::Grammar::Chalk::Type::Array'   => 'Chalk::IR::Type::Array',
        'Chalk::Grammar::Chalk::Type::Hash'    => 'Chalk::IR::Type::Hash',

        # References
        'Chalk::Grammar::Chalk::Type::Ref'       => 'Chalk::IR::Type::Ref',
        'Chalk::Grammar::Chalk::Type::ArrayRef'  => 'Chalk::IR::Type::Ref',
        'Chalk::Grammar::Chalk::Type::HashRef'   => 'Chalk::IR::Type::Ref',
        'Chalk::Grammar::Chalk::Type::CodeRef'   => 'Chalk::IR::Type::Ref',
        'Chalk::Grammar::Chalk::Type::ScalarRef' => 'Chalk::IR::Type::Ref',

        # Code
        'Chalk::Grammar::Chalk::Type::Code'    => 'Chalk::IR::Type::Code',

        # Objects
        'Chalk::Grammar::Chalk::Type::Object'  => 'Chalk::IR::Type::Object',
        'Chalk::Grammar::Chalk::Type::Class'   => 'Chalk::IR::Type::Object',

        # Special
        'Chalk::Grammar::Chalk::Type::Undef'   => 'Chalk::IR::Type::Undef',
        'Chalk::Grammar::Chalk::Type::Scalar'  => 'Chalk::IR::Type::Scalar',
        'Chalk::Grammar::Chalk::Type::Any'     => 'Chalk::IR::Type::Top',
        'Chalk::Grammar::Chalk::Type::None'    => 'Chalk::IR::Type::Bottom',
    );

    # Convert a Grammar type to the corresponding IR type
    # Returns IR::Type::Top if the grammar type is unknown
    sub grammar_to_ir ($class, $grammar_type) {
        return Chalk::IR::Type::Top->TOP() unless defined $grammar_type;

        # If it's already an IR type, return it unchanged
        return $grammar_type if $grammar_type isa Chalk::IR::Type;

        my $grammar_class = blessed($grammar_type) // ref($grammar_type) // '';
        my $ir_class = $GRAMMAR_TO_IR{$grammar_class};

        unless ($ir_class) {
            # Unknown grammar type - return Top
            return Chalk::IR::Type::Top->top();
        }

        # Create the IR type instance
        # Most IR types use TOP() factory method, but Top uses top()
        if ($ir_class eq 'Chalk::IR::Type::Top') {
            return Chalk::IR::Type::Top->top();
        } elsif ($ir_class eq 'Chalk::IR::Type::Bottom') {
            return Chalk::IR::Type::Bottom->BOTTOM();
        } else {
            return $ir_class->TOP();
        }
    }

    # Check if a type is a Grammar type (should be converted)
    sub is_grammar_type ($class, $type) {
        return 0 unless defined $type && blessed($type);
        return $type isa Chalk::Grammar::Chalk::Type;
    }

    # Check if a type is an IR type (ready for optimization/codegen)
    sub is_ir_type ($class, $type) {
        return 0 unless defined $type && blessed($type);
        return $type isa Chalk::IR::Type;
    }

    # Ensure a type is an IR type - converts if necessary
    sub ensure_ir_type ($class, $type) {
        return Chalk::IR::Type::Top->top() unless defined $type;
        return $type if $class->is_ir_type($type);
        return $class->grammar_to_ir($type);
    }
}

1;
