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

    # Default: not an operator (subclasses can override)
    method is_operator() { 0 }

    method to_string() {
        my $type = ref($self) || 'Chalk::Grammar::Token';
        my $name = $pattern_name // 'literal';
        return "$type($name: '$value')";
    }
}

# Operator tokens: matched by operator patterns in the grammar
class Chalk::Grammar::Token::Operator :isa(Chalk::Grammar::Token) {
    # Operators return true for is_operator check
    method is_operator() { 1 }
}

1;
