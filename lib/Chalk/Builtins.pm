# ABOUTME: Built-in function type signatures for Chalk's latent type system
# ABOUTME: Provides type information for Perl built-in functions used in type checking

use 5.042;
use experimental qw(class);

class Chalk::Builtins {
    use Chalk::Type::Any;
    use Chalk::Type::Int;
    use Chalk::Type::Num;
    use Chalk::Type::Str;
    use Chalk::Type::Boolean;
    use Chalk::Type::Array;
    use Chalk::Type::Hash;
    use Chalk::Type::Scalar;
    use Chalk::Type::Undef;
    use Chalk::Type::List;

    # Built-in function signatures
    # Format: 'function_name' => { params => [...], returns => Type }
    our %BUILTIN_SIGNATURES = (
        # String functions
        'length' => {
            params => [Chalk::Type::Str->new()],
            returns => Chalk::Type::Int->new(),
            description => 'Returns length of string',
        },
        'substr' => {
            params => [
                Chalk::Type::Str->new(),
                Chalk::Type::Int->new(),
                Chalk::Type::Int->new(),  # optional length
            ],
            returns => Chalk::Type::Str->new(),
            description => 'Extracts substring',
        },
        'uc' => {
            params => [Chalk::Type::Str->new()],
            returns => Chalk::Type::Str->new(),
            description => 'Uppercase string',
        },
        'lc' => {
            params => [Chalk::Type::Str->new()],
            returns => Chalk::Type::Str->new(),
            description => 'Lowercase string',
        },
        'chomp' => {
            params => [Chalk::Type::Str->new()],
            returns => Chalk::Type::Int->new(),
            description => 'Remove trailing newline',
        },
        'chop' => {
            params => [Chalk::Type::Str->new()],
            returns => Chalk::Type::Str->new(),
            description => 'Remove last character',
        },

        # Array functions
        'push' => {
            params => [
                Chalk::Type::Array->new(element_type => Chalk::Type::Any->new()),
                Chalk::Type::Any->new(),
            ],
            returns => Chalk::Type::Int->new(),
            description => 'Push elements onto array, returns new size',
        },
        'pop' => {
            params => [
                Chalk::Type::Array->new(element_type => Chalk::Type::Any->new()),
            ],
            returns => Chalk::Type::Scalar->new(),
            description => 'Pop element from array',
        },
        'shift' => {
            params => [
                Chalk::Type::Array->new(element_type => Chalk::Type::Any->new()),
            ],
            returns => Chalk::Type::Scalar->new(),
            description => 'Shift element from array start',
        },
        'unshift' => {
            params => [
                Chalk::Type::Array->new(element_type => Chalk::Type::Any->new()),
                Chalk::Type::Any->new(),
            ],
            returns => Chalk::Type::Int->new(),
            description => 'Unshift elements onto array, returns new size',
        },
        'splice' => {
            params => [
                Chalk::Type::Array->new(element_type => Chalk::Type::Any->new()),
                Chalk::Type::Int->new(),
                Chalk::Type::Int->new(),  # optional length
            ],
            returns => Chalk::Type::List->new(),
            description => 'Remove and return array elements',
        },

        # Hash functions
        'keys' => {
            params => [
                Chalk::Type::Hash->new(value_type => Chalk::Type::Any->new()),
            ],
            returns => Chalk::Type::List->new(),
            description => 'Return list of hash keys',
        },
        'values' => {
            params => [
                Chalk::Type::Hash->new(value_type => Chalk::Type::Any->new()),
            ],
            returns => Chalk::Type::List->new(),
            description => 'Return list of hash values',
        },
        'exists' => {
            params => [
                Chalk::Type::Hash->new(value_type => Chalk::Type::Any->new()),
                Chalk::Type::Str->new(),
            ],
            returns => Chalk::Type::Boolean->new(),
            description => 'Check if hash key exists',
        },
        'delete' => {
            params => [
                Chalk::Type::Hash->new(value_type => Chalk::Type::Any->new()),
                Chalk::Type::Str->new(),
            ],
            returns => Chalk::Type::Scalar->new(),
            description => 'Delete hash key, return value',
        },

        # Type checking functions
        'defined' => {
            params => [Chalk::Type::Any->new()],
            returns => Chalk::Type::Boolean->new(),
            description => 'Check if value is defined',
        },
        'ref' => {
            params => [Chalk::Type::Any->new()],
            returns => Chalk::Type::Str->new(),
            description => 'Return reference type name',
        },

        # Numeric functions
        'abs' => {
            params => [Chalk::Type::Num->new()],
            returns => Chalk::Type::Num->new(),
            description => 'Absolute value',
        },
        'int' => {
            params => [Chalk::Type::Num->new()],
            returns => Chalk::Type::Int->new(),
            description => 'Truncate to integer',
        },
        'sqrt' => {
            params => [Chalk::Type::Num->new()],
            returns => Chalk::Type::Num->new(),
            description => 'Square root',
        },
        'sin' => {
            params => [Chalk::Type::Num->new()],
            returns => Chalk::Type::Num->new(),
            description => 'Sine function',
        },
        'cos' => {
            params => [Chalk::Type::Num->new()],
            returns => Chalk::Type::Num->new(),
            description => 'Cosine function',
        },

        # I/O functions
        'print' => {
            params => [Chalk::Type::Any->new()],
            returns => Chalk::Type::Boolean->new(),
            description => 'Print to output',
        },
        'say' => {
            params => [Chalk::Type::Any->new()],
            returns => Chalk::Type::Boolean->new(),
            description => 'Print with newline',
        },

        # List functions
        'join' => {
            params => [
                Chalk::Type::Str->new(),
                Chalk::Type::List->new(),
            ],
            returns => Chalk::Type::Str->new(),
            description => 'Join list elements into string',
        },
        'split' => {
            params => [
                Chalk::Type::Str->new(),  # pattern
                Chalk::Type::Str->new(),  # string
            ],
            returns => Chalk::Type::List->new(),
            description => 'Split string into list',
        },
        'sort' => {
            params => [Chalk::Type::List->new()],
            returns => Chalk::Type::List->new(),
            description => 'Sort list elements',
        },
        'reverse' => {
            params => [Chalk::Type::List->new()],
            returns => Chalk::Type::List->new(),
            description => 'Reverse list elements',
        },
        'grep' => {
            params => [
                Chalk::Type::Any->new(),  # block or pattern
                Chalk::Type::List->new(),
            ],
            returns => Chalk::Type::List->new(),
            description => 'Filter list elements',
        },
        'map' => {
            params => [
                Chalk::Type::Any->new(),  # block
                Chalk::Type::List->new(),
            ],
            returns => Chalk::Type::List->new(),
            description => 'Transform list elements',
        },
    );

    method get_signature($function_name) {
        return $BUILTIN_SIGNATURES{$function_name};
    }

    method has_signature($function_name) {
        return exists $BUILTIN_SIGNATURES{$function_name};
    }

    method all_functions() {
        return keys %BUILTIN_SIGNATURES;
    }
}

1;
