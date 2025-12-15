# ABOUTME: Built-in function type signatures for Chalk's latent type system
# ABOUTME: Provides type information for Perl built-in functions used in type checking

use 5.042;
use experimental qw(class);
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Boolean;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Str;

class Chalk::Builtins {

    # Built-in function signatures
    # Format: 'function_name' => { params => [...], returns => Type }
    my %BUILTIN_SIGNATURES = (
        # String functions
        'length' => {
            params => [Chalk::Grammar::Chalk::Type::Str->new()],
            returns => Chalk::Grammar::Chalk::Type::Int->new(),
            description => 'Returns length of string',
        },
        'substr' => {
            params => [
                Chalk::Grammar::Chalk::Type::Str->new(),
                Chalk::Grammar::Chalk::Type::Int->new(),
                Chalk::Grammar::Chalk::Type::Int->new(),  # optional length
            ],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Extracts substring',
        },
        'uc' => {
            params => [Chalk::Grammar::Chalk::Type::Str->new()],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Uppercase string',
        },
        'lc' => {
            params => [Chalk::Grammar::Chalk::Type::Str->new()],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Lowercase string',
        },
        'chomp' => {
            params => [Chalk::Grammar::Chalk::Type::Str->new()],
            returns => Chalk::Grammar::Chalk::Type::Int->new(),
            description => 'Remove trailing newline',
        },
        'chop' => {
            params => [Chalk::Grammar::Chalk::Type::Str->new()],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Remove last character',
        },

        # Array functions
        'push' => {
            params => [
                Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new()),
                Chalk::Grammar::Chalk::Type::Any->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::Int->new(),
            description => 'Push elements onto array, returns new size',
        },
        'pop' => {
            params => [
                Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new()),
            ],
            returns => Chalk::Grammar::Chalk::Type::Scalar->new(),
            description => 'Pop element from array',
        },
        'shift' => {
            params => [
                Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new()),
            ],
            returns => Chalk::Grammar::Chalk::Type::Scalar->new(),
            description => 'Shift element from array start',
        },
        'unshift' => {
            params => [
                Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new()),
                Chalk::Grammar::Chalk::Type::Any->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::Int->new(),
            description => 'Unshift elements onto array, returns new size',
        },
        'splice' => {
            params => [
                Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new()),
                Chalk::Grammar::Chalk::Type::Int->new(),
                Chalk::Grammar::Chalk::Type::Int->new(),  # optional length
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Remove and return array elements',
        },

        # Hash functions
        'keys' => {
            params => [
                Chalk::Grammar::Chalk::Type::Hash->new(value_type => Chalk::Grammar::Chalk::Type::Any->new()),
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Return list of hash keys',
        },
        'values' => {
            params => [
                Chalk::Grammar::Chalk::Type::Hash->new(value_type => Chalk::Grammar::Chalk::Type::Any->new()),
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Return list of hash values',
        },
        'exists' => {
            params => [
                Chalk::Grammar::Chalk::Type::Hash->new(value_type => Chalk::Grammar::Chalk::Type::Any->new()),
                Chalk::Grammar::Chalk::Type::Str->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::Boolean->new(),
            description => 'Check if hash key exists',
        },
        'delete' => {
            params => [
                Chalk::Grammar::Chalk::Type::Hash->new(value_type => Chalk::Grammar::Chalk::Type::Any->new()),
                Chalk::Grammar::Chalk::Type::Str->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::Scalar->new(),
            description => 'Delete hash key, return value',
        },

        # Type checking functions
        'defined' => {
            params => [Chalk::Grammar::Chalk::Type::Any->new()],
            returns => Chalk::Grammar::Chalk::Type::Boolean->new(),
            description => 'Check if value is defined',
        },
        'ref' => {
            params => [Chalk::Grammar::Chalk::Type::Any->new()],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Return reference type name',
        },

        # Numeric functions
        'abs' => {
            params => [Chalk::Grammar::Chalk::Type::Num->new()],
            returns => Chalk::Grammar::Chalk::Type::Num->new(),
            description => 'Absolute value',
        },
        'int' => {
            params => [Chalk::Grammar::Chalk::Type::Num->new()],
            returns => Chalk::Grammar::Chalk::Type::Int->new(),
            description => 'Truncate to integer',
        },
        'sqrt' => {
            params => [Chalk::Grammar::Chalk::Type::Num->new()],
            returns => Chalk::Grammar::Chalk::Type::Num->new(),
            description => 'Square root',
        },
        'sin' => {
            params => [Chalk::Grammar::Chalk::Type::Num->new()],
            returns => Chalk::Grammar::Chalk::Type::Num->new(),
            description => 'Sine function',
        },
        'cos' => {
            params => [Chalk::Grammar::Chalk::Type::Num->new()],
            returns => Chalk::Grammar::Chalk::Type::Num->new(),
            description => 'Cosine function',
        },

        # I/O functions
        'print' => {
            params => [Chalk::Grammar::Chalk::Type::Any->new()],
            returns => Chalk::Grammar::Chalk::Type::Boolean->new(),
            description => 'Print to output',
        },
        'say' => {
            params => [Chalk::Grammar::Chalk::Type::Any->new()],
            returns => Chalk::Grammar::Chalk::Type::Boolean->new(),
            description => 'Print with newline',
        },

        # List functions
        'join' => {
            params => [
                Chalk::Grammar::Chalk::Type::Str->new(),
                Chalk::Grammar::Chalk::Type::List->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::Str->new(),
            description => 'Join list elements into string',
        },
        'split' => {
            params => [
                Chalk::Grammar::Chalk::Type::Str->new(),  # pattern
                Chalk::Grammar::Chalk::Type::Str->new(),  # string
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Split string into list',
        },
        'sort' => {
            params => [Chalk::Grammar::Chalk::Type::List->new()],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Sort list elements',
        },
        'reverse' => {
            params => [Chalk::Grammar::Chalk::Type::List->new()],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Reverse list elements',
        },
        'grep' => {
            params => [
                Chalk::Grammar::Chalk::Type::Any->new(),  # block or pattern
                Chalk::Grammar::Chalk::Type::List->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
            description => 'Filter list elements',
        },
        'map' => {
            params => [
                Chalk::Grammar::Chalk::Type::Any->new(),  # block
                Chalk::Grammar::Chalk::Type::List->new(),
            ],
            returns => Chalk::Grammar::Chalk::Type::List->new(),
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
