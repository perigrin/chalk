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
        join    => { list_args => 1, reads_list => 1 },
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
        reverse   => { return_type => 'List', reorders => 1, reads_list => 1 },
        caller    => { return_type => 'List' },
        readline  => { return_type => 'List', handle_io => 1 },
        unpack    => { return_type => 'List' },
        glob      => { return_type => 'List' },
        localtime => { return_type => 'List' },

        # ITS LIST IN ANOTHER ORDER (perlfunc: sort, reverse): the elements of
        # its LIST, none added or taken away.
        # READS ITS LIST, AND NO ELEMENT OF IT IS WRITTEN (join, sort, reverse;
        # column reads_list): a sub that hands its @_ to one only reads its
        # arguments. Not every such builtin is listed -- the ones a backend asks
        # about are.
        sort    => { reorders => 1, reads_list => 1 },

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
        # `ref \$x` names (B::SoN's reftype_of_ref), the kind of thing a
        # reference refers to (Scalar::Util's reftype).
        return_type => {
            ( map { ( $_ => 'Num' ) } qw(int abs rand hex oct) ),
            require => 'Int', index => 'Int',
            ( map { ( $_ => 'Boolean' ) } qw(chdir ftdir ftis) ),
            blessed => 'Str', reftype_of_ref => 'Str', reftype => 'Str',
        },

        # ITS VALUE MAY BE UNDEF: substr outside its string, blessed of what
        # is not an object, reftype of what is no reference, -d and -e of
        # nothing there.
        may_be_undef => { map { ( $_ => 1 ) } qw(substr blessed reftype ftdir ftis) },

        # THE KIND OF BUILTIN IT IS (after perlfunc's "Perl Functions by
        # Category", one each):
        #   number     a number of its operand: int, abs, rand, hex, oct
        #   path       of a file it is given the name of: a file test (-d,
        #              -e), the directory chdir changes to, the file
        #              require loads
        #   substring  a piece of a string (substr), or where one is (index)
        #   object     what a reference is: bless, blessed, reftype, `ref \$x`
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
            ( map { ( $_ => 'object' ) }    qw(bless blessed reftype reftype_of_ref) ),
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
        # (formline), %SIG's __WARN__ (warn), the clock a sleep moves (time),
        # the random stream an srand reseeds and a rand advances (rand). Read
        # where it stands, not later (B::SoN pins each).
        reads_state => { map { ( $_ => 1 ) } qw(keys values each sort caller pos tie untie bless formline join warn time rand) },

        # IT CHANGES STATE A LATER READ SEES: chdir the working directory
        # (the next -d's), require %INC and the subs it compiles in.
        changes_state => { map { ( $_ => 1 ) } qw(chdir require) },

        # IT DOES SOMETHING BESIDES MAKE ITS VALUE (perlfunc): changes an
        # array, a hash, a string, a handle, a file, a process, an object's
        # class, a tie. It runs where it stands, once -- never later, at
        # its value's first use, and never not at all. Not every such builtin
        # is listed: the ones B::SoN's wire is checked for (WireCheck).
        acts => { map { ( $_ => 1 ) } qw(push pop shift unshift splice delete chomp chop
            open close binmode printf prtf say syswrite sysread read readline seek truncate opendir readdir closedir
            unlink mkdir rmdir rename chdir chmod chown utime link symlink
            exit die warn system exec fork wait waitpid kill sleep
            bless tie untie select srand each) },

        # WHAT IT DOES, among the builtins of its family (or, for one of no
        # family, of the column it shares: a handle's operation, a tie
        # function, an array's end, a list's order) -- one each, so a backend
        # tells them apart by what they do. (The number family's is
        # number_kind, the case functions' case_change.)
        #   path       -d PATH is it a directory, -e PATH is anything there, chdir
        #              the working directory changed, require a file loaded
        #   substring  substr a piece of the string, index the position of one
        #   object     bless a reference blessed into a class, blessed the
        #              class it was, `ref \$x` the kind of thing $x holds
        #   list       join its LIST joined into a string, unpack the values a
        #              template reads, glob the names of the files a pattern
        #              matches, each a hash's next key and value
        #   scalar     chr the character of a number, ord the number of a
        #              character, time the seconds since the epoch, reverse
        #              (in scalar context) its LIST's string reversed, sprintf
        #              its LIST formatted, lock its operand, prototype a
        #              sub's, pack the string a template makes of its LIST,
        #              formline its LIST formatted into the accumulator
        #   printf     (B::SoN's prtf, perl's op name) its LIST formatted
        #              as sprintf's and printed to a handle: its value 1
        #   an array's end: shift takes its first, pop its last; push adds
        #              its LIST last, unshift first; `$#a = N` (B::SoN's
        #              set_arylen) sets its last index
        #   a list's order: sort its LIST sorted (reverse's, reversed)
        #   a handle's: open opens one, close closes it, eof is it at its end,
        #              readline reads its lines, select selects the default
        #              output handle, four-argument select waits for handles
        #              ready
        #   a tie's: tie binds a variable to a class's object, tied that
        #              object, untie unbinds it
        kind => {
            ftdir => 'is_directory', ftis => 'is_present', chdir => 'changes_directory', require => 'loads_file',
            substr => 'piece', index => 'position',
            bless => 'blesses', blessed => 'class_name', reftype => 'referent_type', reftype_of_ref => 'referent_kind',
            join => 'joined', unpack => 'unpacked', glob => 'file_names', each => 'next_pair',
            chr => 'character', ord => 'code_point', time => 'epoch_seconds', reverse => 'reversed',
            sprintf => 'formatted', printf => 'prints_formatted', prtf => 'prints_formatted', lock => 'operand', prototype => 'prototype_of', pack => 'packed',
            formline => 'format_line',
            shift => 'takes_first', pop => 'takes_last', push => 'adds_last', unshift => 'adds_first',
            set_arylen => 'sets_last_index',
            sort => 'sorted',
            open => 'opens', close => 'closes', eof => 'at_end', readline => 'reads_lines',
            select => 'selects_output', sselect => 'waits_for_handles',
            tie => 'binds', tied => 'tied_object', untie => 'unbinds',
        },

        # ITS VALUE IS OF THE CALL STACK: caller's, the package, file and line
        # of the call N frames up -- each call of a sub pushes its site.
        call_stack => { caller => 1 },

        # ITS VALUE IS WHERE THE LAST m//g ON A VARIABLE LEFT OFF (perlfunc's
        # pos), and an lvalue: a store to it sets where the next one starts.
        match_offset => { pos => 1 },

        # ITS STRING WITH EVERY REGEX METACHARACTER BACKSLASHED (quotemeta):
        # in a pattern, a literal.
        quotes_meta => { quotemeta => 1 },

        # THE PROGRAM ENDS, with a status (perlfunc's exit, 0 where none is
        # given): nothing after it runs.
        exits => { exit => 1 },

        # WITHOUT THREADS IT DOES NOTHING (perlfunc's lock: "a no-op on
        # systems without threads"); its value is its operand.
        unthreaded_noop => { lock => 1 },

        # A STRING'S FIELDS (perlfunc's split), between its pattern's
        # matches: a list, their count in scalar context.
        splits => { split => 1 },

        # A TIME'S NINE FIELDS in list context, its text (ctime's) in scalar
        # context (perlfunc's localtime), now where it is given none.
        local_time => { localtime => 1 },

        # A FILE COMPILED IN (perlfunc's require), entered in %INC: its
        # name's file, of a module's name.
        loads_file => { require => 1 },

        # A HASH'S NEXT PAIR, BY ITS ITERATOR (perlfunc's each), which it
        # moves on: keys and values start it over (resets_iterator).
        advances_iterator => { each => 1 },

        # OF NO OPERAND, OF $_ (perlfunc: "If EXPR is omitted, uses $_").
        # Not rand, whose is 1. Not every such builtin is listed -- the ones
        # a backend asks about are.
        topic_default => { map { ( $_ => 1 ) } qw(abs chr cos exp hex int lc lcfirst length log oct ord quotemeta sqrt uc ucfirst) },

        # THE BASE A NUMERAL IS READ IN: hex's 16; oct's 8, or 16, 2 or 8 by
        # its prefix (0x, 0b, 0o).
        numeral_base => { hex => 16, oct => 8 },
    );
    while ( my ( $col, $rows ) = splice @COLUMNS, 0, 2 ) {
        $FACTS{$_}{$col} = $rows->{$_} for keys $rows->%*;
    }

    # names() -> every builtin a fact is held of, by the name B::SoN gives it.
    sub names() { return sort keys %FACTS }

    # fact($builtin, $column) -> the builtin's fact in that column, or undef.
    sub fact($name, $column) {
        my $f = $FACTS{ $name // '' } or return undef;
        return $f->{$column};
    }
}

1;
