# ABOUTME: Base Token class for scanned terminal values
# ABOUTME: Provides type information to distinguish operators from other tokens
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Token {
    field $value :param;           # The matched text
    field $pattern_name :param :reader = undef;  # Pattern name from grammar (e.g., 'IDENTIFIER')

    # Overload stringification and comparison operators
    use overload
        '""'  => 'value',
        'eq'  => '_string_eq',
        'ne'  => '_string_ne',
        'cmp' => '_string_cmp';

    # Accessor for value field that accepts overload's extra arguments
    method value(@args) { $value }

    # String comparison operators
    method _string_eq($other, $swap) { "$value" eq "$other" }
    method _string_ne($other, $swap) { "$value" ne "$other" }
    method _string_cmp($other, $swap) { $swap ? "$other" cmp "$value" : "$value" cmp "$other" }


    method to_string() {
        my $type = ref($self) || 'Chalk::Grammar::Token';
        my $name = $pattern_name // 'literal';
        return "$type($name: '$value')";
    }
}

# Operator tokens: matched by operator patterns in the grammar
# Use isa('Chalk::Grammar::Token::Operator') to detect
class Chalk::Grammar::Token::Operator :isa(Chalk::Grammar::Token) { }

# Integer tokens: matched by INTEGER pattern in the grammar
# Use isa('Chalk::Grammar::Token::Int') to detect
class Chalk::Grammar::Token::Int :isa(Chalk::Grammar::Token) { }

# Float tokens: matched by FLOAT pattern in the grammar
# Use isa('Chalk::Grammar::Token::Float') to detect
class Chalk::Grammar::Token::Float :isa(Chalk::Grammar::Token) { }

1;
