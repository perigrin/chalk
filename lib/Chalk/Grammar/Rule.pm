# ABOUTME: Represents a BNF grammar rule with name and alternative expressions.
# ABOUTME: Immutable value object where expressions is an array of arrays of Symbols.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Grammar::Rule {
    field $name        :param :reader; # rule name (string)
    field $expressions :param :reader; # arrayref of arrayrefs of Chalk::Grammar::Symbol

    method alternative_count() {
        return scalar $expressions->@*;
    }

    method is_terminal_rule() {
        # A rule is terminal if all alternatives contain only terminal symbols
        for my $alt ($expressions->@*) {
            for my $symbol ($alt->@*) {
                return false unless $symbol->is_terminal();
            }
        }
        return true;
    }

    method to_string() {
        my @alts = map {
            join(' ', map { $_->to_string() } $_->@*)
        } $expressions->@*;

        return "$name ::= " . join(' | ', @alts) . " ;";
    }
}
