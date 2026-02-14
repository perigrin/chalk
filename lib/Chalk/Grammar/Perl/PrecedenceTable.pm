# ABOUTME: Perl operator precedence table for the Precedence semiring.
# ABOUTME: Returns array of {assoc, ops} hashes, lower index = higher precedence.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::PrecedenceTable {
    # Returns the operator precedence table.
    # Each entry: { assoc => 'left'|'right'|'nonassoc'|'chained', ops => [...] }
    # Lower index = higher precedence (tighter binding).
    sub get_table() {
        return (
            { assoc => 'right',    ops => ['**'] },                                    # 0
            { assoc => 'left',     ops => ['=~', '!~'] },                              # 1
            { assoc => 'left',     ops => ['*', '/', '%', 'x'] },                      # 2
            { assoc => 'left',     ops => ['+', '-', '.'] },                            # 3
            { assoc => 'left',     ops => ['<<', '>>'] },                               # 4
            { assoc => 'nonassoc', ops => ['isa'] },                                    # 5
            { assoc => 'chained',  ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'] }, # 6
            { assoc => 'nonassoc', ops => ['==', '!=', '<=>', 'eq', 'ne', 'cmp'] },    # 7
            { assoc => 'left',     ops => ['&'] },                                      # 8
            { assoc => 'left',     ops => ['|', '^'] },                                 # 9
            { assoc => 'left',     ops => ['&&'] },                                     # 10
            { assoc => 'left',     ops => ['||', '//'] },                               # 11
            { assoc => 'nonassoc', ops => ['..', '...'] },                              # 12
            { assoc => 'left',     ops => ['and'] },                                    # 13
            { assoc => 'left',     ops => ['or', 'xor'] },                              # 14
        );
    }

    # Build a lookup hash: operator_string => { level => N, assoc => str }
    # Cached as package variable for efficiency.
    my %op_lookup;
    my $lookup_built = false;

    sub _build_lookup() {
        return if $lookup_built;
        my @table = get_table();
        my $last = scalar(@table) - 1;
        for my $i (0 .. $last) {
            for my $op ($table[$i]->{ops}->@*) {
                $op_lookup{$op} = { level => $i, assoc => $table[$i]->{assoc} };
            }
        }
        $lookup_built = true;
    }

    # Look up an operator. Returns { level => N, assoc => str } or undef.
    sub lookup($op) {
        _build_lookup();
        return $op_lookup{$op};
    }
}
