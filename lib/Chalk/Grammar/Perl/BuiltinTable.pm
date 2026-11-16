# ABOUTME: Per-builtin facts the type signatures (TypeLibrary) do not hold: what a builtin returns,
# ABOUTME: its kind, the state it reads or changes, a tie, a handle, a LIST. Sits beside KeywordTable.
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
        # their argument's, in another case (which: changes_case, below).
        lc        => { return_type => 'Str' },
        uc        => { return_type => 'Str' },
        lcfirst   => { return_type => 'Str' },
        ucfirst   => { return_type => 'Str' },
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
        # WRITES THE SCALAR IT IS GIVEN FIRST, given this many operands
        # (perlfunc: "substr EXPR,OFFSET,LENGTH,REPLACEMENT ... replaces
        # parts of the EXPR"): an alias there writes through.
        substr  => { writes_first_with => 4 },

        open    => { handle_io => 1 },
        close   => { handle_io => 1 },
        eof     => { handle_io => 1 },
        select  => { handle_io => 1 },
        sselect => { handle_io => 1 },
    );

    # COLUMNS GIVEN A COLUMN AT A TIME, each builtin it names merged into its
    # row above (a builtin may be in several).
    my @COLUMNS = (
        # WHAT IT RETURNS, for a builtin TypeLibrary has no signature for.
        # A number of its operand's (perlfunc: "Numeric functions") -- an
        # IV, a UV or an NV as it comes out: int(1e20) is an NV, hex of 16
        # f's a UV. require's 1 (a file already loaded, or one B::SoN
        # followed). index's position, -1 for none. Yes or no: perl's
        # chdir, -d and -e (1 or ''). blessed's class name, the kind of thing
        # `ref \$x` names (B::SoN's reftype_of_ref).
        return_type => {
            ( map { ( $_ => 'Num' ) } qw(int abs rand hex oct) ),
            require => 'Int', index => 'Int',
            ( map { ( $_ => 'Boolean' ) } qw(chdir ftdir ftis) ),
            blessed => 'Str', reftype_of_ref => 'Str',
        },

        # ITS VALUE MAY BE UNDEF: substr outside its string, blessed of what
        # is not an object, -d and -e of nothing there.
        may_be_undef => { map { ( $_ => 1 ) } qw(substr blessed ftdir ftis) },

        # THE KIND OF BUILTIN IT IS (after perlfunc's "Perl Functions by
        # Category", one each):
        #   number     a number of its operand: int, abs, rand, hex, oct
        #   path       of a file it is given the name of: a file test (-d,
        #              -e), the directory chdir changes to, the file
        #              require loads
        #   substring  a piece of a string (substr), or where one is (index)
        #   object     what a reference is: bless, blessed, `ref \$x`
        #   array      an element taken off an array's end: shift, pop
        #   list       a LIST made or taken whole: join's (a string of one),
        #              unpack's and glob's (a list), each's (a key and value)
        #   warning    a message to the warn handler or STDERR: warn
        #   scalar     one scalar of its operands: chr, ord, time, reverse
        #              (in scalar context), sprintf, lock, prototype, pack,
        #              formline
        family => {
            ( map { ( $_ => 'number' ) }    qw(int abs rand hex oct) ),
            ( map { ( $_ => 'path' ) }      qw(ftdir ftis chdir require) ),
            ( map { ( $_ => 'substring' ) } qw(substr index) ),
            ( map { ( $_ => 'object' ) }    qw(bless blessed reftype_of_ref) ),
            ( map { ( $_ => 'array' ) }     qw(shift pop) ),
            ( map { ( $_ => 'list' ) }      qw(join unpack glob each) ),
            warn => 'warning',
            ( map { ( $_ => 'scalar' ) }    qw(chr ord time reverse sprintf lock prototype pack formline) ),
        },

        # WHAT NUMBER IT MAKES OF ITS OPERAND (the number family): int its
        # integer part, abs its absolute value, rand a random number below
        # it, hex and oct the numeral it reads.
        number_kind => {
            int => 'integer_part', abs => 'absolute', rand => 'random',
            hex => 'numeral', oct => 'numeral',
        },

        # WHICH CASE, OF WHAT (the case functions): every character's or the
        # first's, upper or lower.
        changes_case => {
            uc => 'upper', lc => 'lower', ucfirst => 'upper_first', lcfirst => 'lower_first',
        },

        # ITS VALUE IS OF STATE A LATER STORE MAY CHANGE: a hash's keys,
        # values or next pair, a list's order or join, the call stack, a
        # string's pos, a variable's tie (tie, untie: every later access is
        # the tie's), an object's class (bless), the format accumulator
        # (formline), %SIG's __WARN__ (warn). Read where it stands, not
        # later.
        reads_state => { map { ( $_ => 1 ) } qw(keys values each sort caller pos tie untie bless formline join warn) },

        # IT CHANGES STATE A LATER READ SEES: chdir the working directory
        # (the next -d's), require %INC and the subs it compiles in.
        changes_state => { map { ( $_ => 1 ) } qw(chdir require) },
    );
    while ( my ( $col, $rows ) = splice @COLUMNS, 0, 2 ) {
        $FACTS{$_}{$col} = $rows->{$_} for keys $rows->%*;
    }

    # fact($builtin, $column) -> the builtin's fact in that column, or undef.
    sub fact($name, $column) {
        my $f = $FACTS{ $name // '' } or return undef;
        return $f->{$column};
    }
}

1;
