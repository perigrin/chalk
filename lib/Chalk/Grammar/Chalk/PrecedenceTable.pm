# ABOUTME: Perl operator precedence table for use in Chalk parser
# ABOUTME: Reference: perldoc perlop - Operator Precedence and Associativity
use 5.42.0;
use experimental 'class';
use utf8;

class Chalk::Grammar::Chalk::PrecedenceTable {
    # Class method to get the Perl precedence table
    # Returns array of precedence levels (highest to lowest)
    # Each level is { assoc => 'left'|'right'|'nonassoc'|'chained'|'chain/na', ops => [...] }
    sub get_table {
        return (
            # Index 0 - Highest precedence
            # NOTE: '->' needs to be in precedence table to prevent wrong parses like
            # (state $x = $obj)->method() where assignment (low precedence) is nested
            # inside method call (high precedence). The MethodCall grammar rule
            # uses Expression as receiver, so we need precedence validation.
            { assoc => 'left', ops => ['->'] },  # method call, array/hash deref
            { assoc => 'nonassoc', ops => ['++', '--'] },  # postfix
            { assoc => 'right',   ops => ['**'] },
            { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
            { assoc => 'left',    ops => ['=~', '!~'] },
            { assoc => 'left',    ops => ['*', '/', '%', 'x'] },
            { assoc => 'left',    ops => ['+', '-', '.'] },
            { assoc => 'left',    ops => ['<<', '>>'] },
            { assoc => 'nonassoc', ops => ['named unary'] },
            { assoc => 'nonassoc', ops => ['isa'] },
            { assoc => 'chained', ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'] },
            { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne', '<=>', 'cmp', '~~'] },
            { assoc => 'left',    ops => ['&'] },
            { assoc => 'left',    ops => ['|', '^'] },
            { assoc => 'left',    ops => ['&&'] },
            { assoc => 'left',    ops => ['||', '^^', '//'] },
            { assoc => 'nonassoc', ops => ['..', '...'] },
            { assoc => 'right',   ops => ['?:'] },
            { assoc => 'right',   ops => ['=', '+=', '-=', '*=', '/=', '%=', '**=', '&=', '|=', '^=', '.=', '<<=', '>>=', '&&=', '||=', '//='] },
            { assoc => 'left',    ops => [',', '=>'] },
            { assoc => 'right',   ops => ['not'] },
            { assoc => 'left',    ops => ['and'] },
            { assoc => 'left',    ops => ['or', 'xor'] },
            # Index 22 - Lowest precedence
        );
    }
}

1;
