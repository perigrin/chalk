# ABOUTME: Per-builtin facts the type signatures (TypeLibrary) do not hold: which builtins
# ABOUTME: change case, work a tie or a handle, take or return a LIST. Sits beside KeywordTable.
use 5.42.0;
use utf8;
use experimental 'class';

# WHY A TABLE BESIDE TypeLibrary AND NOT IN IT. TypeLibrary's
# %BUILTIN_SIGNATURES is read at PARSE time: a builtin named there has its
# arguments checked by the TypeInference semiring, which kills parses whose
# argument types do not satisfy it. Adding `lc` there to record that it
# returns a Str would also start checking lc's argument -- a parser change made
# to record a fact. So a fact a backend asks about, for a builtin the
# signatures do not hold (or a fact the signatures have no column for), is
# here; Chalk::IR::Node::Call reads both and answers.
#
# A FACT HERE IS TRUE OF EVERY BUILTIN IT NAMES; it is not claimed that every
# builtin it is true of is named. Each column says which it lists.
class Chalk::Grammar::Perl::BuiltinTable {
    my %FACTS = (
        # THE CASE FUNCTIONS (perlfunc: lc, lcfirst, uc, ucfirst): a string of
        # their argument's, in another case.
        lc        => { changes_case => 1, return_type => 'Str' },
        uc        => { changes_case => 1, return_type => 'Str' },
        lcfirst   => { changes_case => 1, return_type => 'Str' },
        ucfirst   => { changes_case => 1, return_type => 'Str' },
        quotemeta => { return_type => 'Str' },

        # THE TIE FUNCTIONS (perlfunc: tie, tied, untie): each of a variable's
        # tie -- its class's object behind the variable.
        tie   => { tie => 1 },
        tied  => { tie => 1 },
        untie => { tie => 1 },

        # A LIST AFTER ITS FIRST OPERAND (perlfunc's `push ARRAY,LIST`, `join
        # EXPR,LIST`, `sprintf FORMAT, LIST`, `printf FORMAT, LIST`) or as its
        # whole operand (`die LIST`, `warn LIST`): what it is given there is
        # evaluated in list context. Not every such builtin is listed -- the
        # ones a backend asks about are.
        push    => { list_args => 1 },
        unshift => { list_args => 1 },
        join    => { list_args => 1 },
        sprintf => { list_args => 1 },
        printf  => { list_args => 1 },
        die     => { list_args => 1 },
        warn    => { list_args => 1 },

        # A LIST IN LIST CONTEXT (perlfunc's `each HASH`: "in list context
        # returns a 2-element list consisting of the key and value"), where
        # B::SoN's stamp does not say so. Not every list-returning builtin is
        # listed -- the ones a backend asks about are.
        each    => { list_in_list => 1 },

        # A LIST IN LIST CONTEXT, for a builtin TypeLibrary has no signature
        # for (its signatures say List for keys, values, each, sort, splice,
        # split): perlfunc's `reverse LIST` ("in list context, returns a list
        # value consisting of the elements of LIST in the opposite order"),
        # `caller EXPR`, `readline` ("in list context, reads until end-of-file
        # ... and returns a list of lines"), `unpack`, `glob`, `localtime` (its
        # nine fields). Each is a scalar of its own in scalar context.
        reverse   => { return_type => 'List', reorders => 1 },
        caller    => { return_type => 'List' },
        readline  => { return_type => 'List', handle_io => 1 },
        unpack    => { return_type => 'List' },
        glob      => { return_type => 'List' },
        localtime => { return_type => 'List' },

        # ITS LIST IN ANOTHER ORDER (perlfunc: sort, reverse): the elements of
        # its LIST, none added or taken away.
        sort    => { reorders => 1 },

        # A HASH'S KEYS OR ITS VALUES (perlfunc: keys, values): every one, a
        # count in scalar context. Each also RESETS THE HASH'S ITERATOR
        # ("each ... the iterator ... is reset by calling keys or values").
        keys    => { lists_hash => 'keys',   resets_iterator => 1 },
        values  => { lists_hash => 'values', resets_iterator => 1 },

        # AN OPERATION ON A FILEHANDLE (perlfunc's "Input and output
        # functions"): open, close, eof, readline, select of the default output
        # handle, and select's four-argument form (`sselect`, B::SoN's name for
        # it). Not every such builtin is listed -- the ones a backend asks
        # about are.
        open    => { handle_io => 1 },
        close   => { handle_io => 1 },
        eof     => { handle_io => 1 },
        select  => { handle_io => 1 },
        sselect => { handle_io => 1 },
    );

    # fact($builtin, $column) -> the builtin's fact in that column, or undef.
    sub fact($name, $column) {
        my $f = $FACTS{ $name // '' } or return undef;
        return $f->{$column};
    }
}

1;
