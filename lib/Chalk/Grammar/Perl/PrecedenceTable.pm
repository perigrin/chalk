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
            { assoc => 'left',     ops => ['&', '&.'] },                                  # 8
            { assoc => 'left',     ops => ['|', '^', '|.', '^.'] },                    # 9
            { assoc => 'left',     ops => ['&&'] },                                     # 10
            { assoc => 'left',     ops => ['||', '//', '^^'] },                         # 11
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

    # Named-unary operators at perlop L10.
    # These sit between binary-op levels (0-14) and assignment (100).
    # Source: perlop "Named Unary Operators" + PREFIX_BUILTINS cross-check.
    my @NAMED_UNARY = qw(
        defined exists ref scalar length chr ord
        keys values each delete substr sprintf join split
        abs int hex oct sqrt sin cos exp log
        lc uc lcfirst ucfirst quotemeta
        fileno tell wantarray caller
    );

    # perlop L10 (named-unary) sits between Chalk binary-op level 4 (<< >>)
    # and level 5 (isa). No integer slot exists between 4 and 5, so 4.5 is
    # used. Perl's numeric comparison handles fractional values natively.
    # The principled long-term fix is to renumber the entire table to leave
    # an integer gap (Option A in step2-second-blocker.md); 4.5 unblocks
    # Step 2 without requiring a table-wide renumber.
    sub named_unary_level() { return 4.5; }

    # perlop L23 (not) sits between Chalk binary-op level 12 (.. ...) and
    # level 13 (and). No integer slot exists between 12 and 13, so 12.5 is
    # used. This gives `not` a level tighter than `and` (13) and `or`/`xor`
    # (14), but looser than all binary operators through level 12.
    sub not_level() { return 12.5; }

    # Named unary operators do not chain: `defined defined $x` is a syntax
    # error in Perl, so the associativity is 'nonassoc'.
    sub named_unary_assoc() { return 'nonassoc'; }

    my %_named_unary_lookup;
    my $_named_unary_built = false;

    sub _build_named_unary_lookup() {
        return if $_named_unary_built;
        $_named_unary_lookup{$_} = 1 for @NAMED_UNARY;
        $_named_unary_built = true;
    }

    # Returns true if $name is a named-unary operator.
    sub is_named_unary($name) {
        _build_named_unary_lookup();
        return exists $_named_unary_lookup{$name};
    }
}
