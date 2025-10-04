# ABOUTME: Base classes for Chalk parser - Element and Semiring abstractions
# ABOUTME: Provides fundamental algebraic structures used throughout the parser
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);

class Chalk::Element {
    use overload
      '+'      => 'add',
      '*'      => 'multiply',
      '""'     => 'to_string',
      '=='     => 'equals',
      fallback => 1;

    method add( $other, $swap = undef )      { ... }
    method multiply( $other, $swap = undef ) { ... }
    method equals( $other, $swap = undef )   { ... }
    method score()                           { ... }
    method to_string()                       { ... }
}

class Chalk::Semiring {
    method init_element_from_rule($rule) { ... }
}

1;
