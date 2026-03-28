# ABOUTME: Represents a single symbol in a BNF grammar (terminal or nonterminal).
# ABOUTME: Immutable value object with type, value, and optional quantifier.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Symbol {
    field $type      :param :reader; # 'reference' (nonterminal) or 'terminal' (regex)
    field $value     :param :reader; # identifier name or regex pattern
    field $quantifier :param :reader = undef; # undef, '*', '+', or '?'

    method is_terminal()   { $type eq 'terminal' }
    method is_reference()  { $type eq 'reference' }
    method is_quantified() { defined $quantifier }

    # Prefixed key for DFA goto_table: "t:value" for terminals, "n:value" for
    # nonterminals. Prevents collisions when a terminal pattern string matches
    # a nonterminal name.
    method goto_key() { ($type eq 'reference' ? 'n:' : 't:') . $value }

    method to_string() {
        my $str = $self->is_terminal() ? "/$value/" : $value;
        $str .= $quantifier if defined $quantifier;
        return $str;
    }
}
