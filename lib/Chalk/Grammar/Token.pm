# ABOUTME: Base Token class for scanned terminal values
# ABOUTME: Provides type information to distinguish operators from other tokens
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Token {
    field $value :param :reader;           # The matched text
    field $pattern_name :param :reader = undef;  # Pattern name from grammar (e.g., 'IDENTIFIER')

    # Overload stringification to return the value
    use overload
        '""' => sub { shift->value },
        fallback => 1;

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
