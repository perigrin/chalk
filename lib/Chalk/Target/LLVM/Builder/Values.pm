# ABOUTME: The LLVM builder's values: the LLVM type each value is (chosen once, here), the
# ABOUTME: node that computes it, truth and conversions (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

use Scalar::Util qw(blessed refaddr);

# Undef and a Scalar nothing narrowed are each a %Slot: its tag says which.
my %SCALAR = (Int => 'i64', Num => 'double', Str => '%Str', Boolean => 'i1', Undef => '%Slot', Scalar => '%Slot');
my %ARITH  = (Add => 'add', Subtract => 'sub', Multiply => 'mul');
my %SCMP   = (StrEq => 'eq', StrNe => 'ne', StrLt => 'lt', StrGt => 'gt', StrLe => 'le', StrGe => 'ge');
my %CMP    = (NumLt => 'lt', NumGt => 'gt', NumLe => 'le', NumGe => 'ge', NumEq => 'eq', NumNe => 'ne');

# T2'S BUILTINS: what T2 makes of a builtin, by name -- the functor from a
# builtin to T2, in one place. Not a fact of perl's about the builtin (those
# are Chalk::IR::Node::Call's, read from BuiltinTable and TypeLibrary): how T2
# holds its value and which of T2's emitters makes it.
#   type      its T2 type, where that is one in every context (one whose type
#             follows its context -- caller, keys, sort, localtime, readline --
#             is type_of's own case):
#               %Slot   may be undef or either kind of number: substr outside
#                       its string, int and rand, -d, chdir, reftype, a shift or
#                       pop, an object (bless; blessed's class or undef), -e
#               i64     require's 1, index's position
#               %Array* a list always: unpack's, glob's, each's
#               %Str    join's string
#   value     the emitter of its value (a builtin made elsewhere -- an array's,
#             a hash's, a handle's -- is in array_value, hash_value, io_value)
#   in_place  where B::SoN pins it, T2 makes its value where it stands (walk):
#             'passed' -- a read it waits on also settled before a later store
#             -- or 'value'
our %T2_BUILTIN = (
    ( map { ( $_ => { type => '%Slot' } ) }   qw(shift pop blessed reftype_of_ref) ),
    ( map { ( $_ => { type => '%Array*' } ) } qw(unpack glob) ),
    join     => { type => '%Str', in_place => 'passed' },
    each     => { type => '%Array*', in_place => 'passed' },
    ( map { ( $_ => { in_place => 'passed' } ) } qw(keys values sort caller pos tie untie) ),
    bless    => { type => '%Slot', in_place => 'passed' },
    formline => { value => 'builtin_value', in_place => 'passed' },
    ftdir    => { type => '%Slot', value => 'path_value' },
    chdir    => { type => '%Slot', value => 'path_value', in_place => 'value' },
    require  => { type => 'i64',   value => 'path_value', in_place => 'value' },
    ( map { ( $_ => { type => '%Slot', value => 'number_value' } ) } qw(int rand) ),
    substr   => { type => '%Slot', value => 'substr_value' },
    index    => { type => 'i64',   value => 'substr_value' },
    ftis     => { type => '%Slot', value => 'builtin_value' },
    ( map { ( $_ => { value => 'builtin_value' } ) } qw(chr ord time reverse sprintf lock prototype pack) ),
    warn     => { type => '%Slot', value => 'warn_value', in_place => 'passed' },
);

# t2_builtin($Call, $column) -> what T2's table says of a builtin's call, or undef.
sub t2_builtin {
    my ($v, $col) = @_;
    return undef unless $v->operation eq 'Call' && $v->is_builtin;
    my $e = $T2_BUILTIN{ $v->name // '' } or return undef;
    return $e->{$col};
}

# phi_type($Phi) -> a merge's T2 type: its stamp's, except a Str (a Num may
# reach it) or a stamp T1 could not give (a recursive sub's result) -- boxed.
sub phi_type {
    my ($b, $phi) = @_;
    return '%Slot' if $b && $b->{ret_phi} && $b->{ret_phi}{ refaddr($phi) };   # (a merge returned: see func)
    my $st = $phi->stamp // ''; # static type
    # THE LIST A SUB RETURNS, merged from its returns (`return` in one arm, a
    # last value in the other): an array, each arm's value a list of it.
    return '%Array*' if grep { blessed($_) && $_->operation eq 'Return' && $_->inputs->@* == 2 && refaddr( $_->inputs->[0] ) == refaddr($phi) }
        ( $phi->consumers // [] )->@*;
    # AN EVAL'S VALUE IN LIST CONTEXT, typed a list: the body's list, or the
    # empty one where a die was caught (close_eval). (B::SoN merges nothing
    # else at an eval's join but its memory: a variable the body rebinds it
    # refuses.) One typed a scalar (B::SoN's Maybe[Int] for `my @r = eval
    # { ...; 7 }`) is read as one element by what takes it: refused, its
    # die's empty list is no element.
    if ( ( _eval_want_of($phi) // '' ) eq 'list' ) {
        return '%Array*' if $st =~ /\A(?:List|Array)\z/;   # static type
        out('an eval in list context whose value is typed a scalar (a die gives the empty list)');
    }
    # A MERGE OF VERSIONS OF ONE ARRAY OR HASH (`@p = ()` in an arm or a
    # loop body; B::SoN's phi of the variable and its new value), or of
    # arrays of their own: the one the way taken holds, by pointer (an
    # array's %Array*, a hash's %Slot) -- a push after the join writes it.
    if ( my $k = $b->agg_versions($phi) ) { return $k eq '@' ? '%Array*' : '%Slot' }
    return '%Slot' if $st =~ /\A(?:Str|Unknown|None|Scalar)\z/ || $st =~ /\AMaybe\[/;   # a Maybe: T or undef
    # A LIST A LOOP BUILDS (map, grep): one array, its back edge a ListAppend
    # to it. Another array phi (`@p = ()` in a loop) is not this.
    # AN ARRAY ASSIGNED WHOLE IN EACH ARM of an if (`@e = @in` here, `@e = (...)`
    # there): each arm's a fresh list, the arm taken's at the join. (In a loop
    # a list made in the body would be made again each pass: not this.)
    if ($st =~ /\A(?:Array|List)\z/) {
        return '%Array*' if grep { blessed($_) && $_->operation eq 'ListAppend' } $phi->inputs->@*;
        # A MERGE (not a loop's) OF FRESH ARRAYS: list literals, copies of a deref.
        return '%Array*' if !( blessed( $phi->region ) && $phi->region->operation eq 'Loop' )
            && !grep { !( blessed($_) && ( $_->operation eq 'ArrayLiteral' && ( $_->stamp // '' ) eq 'Array'   # static type
                                          || $_->operation eq 'PostfixDeref' && $_->is_array_deref && $_->copy ) ) } $phi->inputs->@*;
        # A `my` ARRAY WHOLE-ASSIGNED IN AN ARM (`@a = sort @a` in one): each
        # way in a fresh array of its own, or the variable itself. Fresh ones
        # only: the join picks one (none is another variable's, which a later
        # push would write too). With the variable: each fresh one is copied
        # into it at its arm's end, and the join is the variable -- perl's
        # whole assign, in place.
        my %pad;
        if (_fresh_arrays($phi, {}, \%pad) && keys %pad <= 1) {
            ( $b->{phi_store}{ refaddr($phi) } ) = values %pad;
            return '%Array*';
        }
        out("a phi stamped $st");
    }
    return $SCALAR{$st} // out("a phi stamped $st");
}

# _eval_want_of($Phi) -> the context of the eval whose value $Phi is (B::SoN's
# eval_want: undef for scalar or void, 'list', or 'scalar' in a sub's copy for
# a scalar call), or undef for a phi at no eval's join.
sub _eval_want_of {
    my ($phi) = @_;
    my $r = $phi->region;
    return undef unless blessed($r) && $r->operation eq 'Region' && defined $r->eval_entry && !$phi->is_memory;
    return $r->eval_want;
}

# agg_versions($Phi) -> '@' or '%' where each way into the merge is, through
# merges and choices, an array (or each a hash) that is a version of one
# `my` variable of this function -- the variable itself, a new value of it
# (`@p = ()`) -- or one of its own (a list literal, a copy of a deref, a
# list a loop builds), or an array through a reference (the merge is that
# array, as the deref is); else undef. No way in is another variable's: a
# write after the join writes only what the way taken held. (Not where
# _fresh_arrays places an array merge in its variable: its join copies.)
sub agg_versions {
    my ($b, $phi) = @_;
    # (a list a loop builds: phi_type's own)
    return undef if ( $phi->stamp // '' ) =~ /\A(?:Array|List)\z/ && grep { blessed($_) && $_->operation eq 'ListAppend' } $phi->inputs->@*;   # static type
    my $pad = {};
    return undef if blessed( $phi->region ) && $phi->region->operation eq 'Region'
        && _fresh_arrays($phi, {}, $pad) && keys %$pad <= 1 && ( $phi->stamp // '' ) =~ /\A(?:Array|List)\z/;   # static type
    my (%kind, %var, @phis, $alias);
    my %seen;
    my @q = ($phi);
    while ( defined( my $n = shift @q ) ) {
        return undef unless blessed($n);
        next if $seen{ refaddr($n) }++;
        my $op = $n->operation;
        my $st = $n->stamp // '';   # static type
        if ( $op eq 'Phi' ) { return undef if $n->is_memory; push @phis, $n; push @q, $n->inputs->@*; next }
        if ( $op eq 'TernaryExpr' && $st =~ /\A(?:Array|List)\z/ ) { push @q, $n->inputs->@[1, 2]; next }
        if ( $op eq 'PadAccess' && !$n->shared && !( $n->can('file') && $n->file ) && ( $n->is_my_array || $n->is_my_hash ) ) {
            $var{ $n->name . '#' . ( $n->can('targ') ? $n->targ // '' : '' ) } = 1;
            $kind{ $n->sigil } = 1;
            next;
        }
        if ( $op eq 'ArrayLiteral' && $st eq 'Array' || $op eq 'ListAppend' || $op eq 'PostfixDeref' && $n->is_array_deref ) {
            $kind{'@'} = 1;
            $alias = 1 if $op eq 'PostfixDeref' && !$n->copy;
            next;
        }
        if ( $op eq 'HashLiteral' && $st eq 'Hash' || $op eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%' && $n->copy ) { $kind{'%'} = 1; next }
        # (a builtin's list -- `@r = sort ...` -- a list of its own, as a list literal is)
        if ( $op eq 'Call' && $n->is_builtin && $n->returns_a_list && $st =~ /\A(?:Array|List)\z/ ) { $kind{'@'} = 1; next }
        return undef;
    }
    return undef unless keys %kind == 1 && keys %var <= 1;
    # (AN ARRAY THROUGH A REFERENCE, the deref's own array: a merge of it is
    # read only -- one written after the join would write that array, or a
    # variable's: not this)
    return undef if $alias && grep { _written($_) } @phis;
    # WRITTEN IN PLACE THROUGH A REFERENCE TO A MERGE (`\@p`, `\$p[0]` where
    # @p is the loop's merge of it): nothing orders a read after a write
    # through it. Refused by name. (A push, splice, shift ... onto the merge
    # takes the memory it runs at and is the version after: B::SoN orders a
    # count after it, pvm c140.)
    out('a write in place to a merge of versions of an array or hash (B::SoN orders no read after it)')
        if grep { _written_off_memory($_) } @phis;
    return ( keys %kind )[0];
}

# _written_off_memory($n) -> some write in place of the aggregate $n is
# on no memory chain: a reference taken to it or an element -- written
# through that, nothing orders a read. (A store to an element is on the
# chain, as is a builtin that changes the array it is given first: B::SoN
# gives each the memory it runs at.)
sub _written_off_memory {
    my ($n) = @_;
    my $is = sub ($x) { blessed($x) && refaddr($x) == refaddr($n) };
    for my $c (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        my $op = $c->operation;
        return 1 if $op eq 'Ref' && $is->( $c->inputs->[0] );
        return 1 if $op eq 'Subscript' && $is->( $c->inputs->[0] )
            && grep { blessed($_) && $_->operation eq 'Ref' && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($c) } ( $c->consumers // [] )->@*;
    }
    return 0;
}

# _written($n) -> some node writes the aggregate $n in place: a builtin that
# changes the array it is given first, a store to (or a delete of) an element.
sub _written {
    my ($n) = @_;
    my $is = sub ($x) { blessed($x) && refaddr($x) == refaddr($n) };
    for my $c (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        my $op = $c->operation;
        return 1 if $op eq 'Call' && $c->mutates_array && $is->( $c->inputs->[0] );
        return 1 if $op =~ /\A(?:Assign|CompoundAssign|Delete)\z/ && $is->( $c->inputs->[0] );
        return 1 if $op eq 'Subscript' && $is->( $c->inputs->[0] )
            && grep { blessed($_) && $_->operation =~ /\A(?:Assign|CompoundAssign|Delete|Ref)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($c) } ( $c->consumers // [] )->@*;
    }
    return 0;
}

# _fresh_arrays($Phi, $seen, \%pad) -> true for a merge (not a loop's) each of
# whose ways in is a fresh array -- a list literal made into one -- or a `my`
# array (put in %pad by name), or such a merge.
sub _fresh_arrays {
    my ($phi, $seen, $pad) = @_;
    return 1 if $seen->{ refaddr($phi) }++;
    return 0 unless blessed( $phi->region ) && $phi->region->operation eq 'Region';
    for my $in ($phi->inputs->@*) {
        return 0 unless blessed($in);
        next if $in->operation eq 'ArrayLiteral' && ( $in->stamp // '' ) eq 'Array';   # static type
        next if $in->operation eq 'PostfixDeref' && $in->is_array_deref && $in->copy;   # (a copy of a deref)
        next if $in->operation eq 'Phi' && _fresh_arrays($in, $seen, $pad);
        # (a sub's list: a fresh array, the call's in list context)
        next if $in->operation eq 'Call' && $in->is_sub_call && _list_use($in);
        if ( $in->operation eq 'PadAccess' && $in->is_my_array && !$in->shared && !( $in->can('file') && $in->file ) ) {
            $pad->{ $in->name . '#' . ( $in->can('targ') ? $in->targ // '' : '' ) } = $in;
            next;
        }
        return 0;
    }
    return 1;
}

# phi_input($Phi, $in, $ty) -> the value a merge takes from one way in, made
# at that way's end: an array's list (a `my` array's merge: copied into it).
sub phi_input {
    my ($b, $p, $in, $ty) = @_;
    local $b->{at_way} = 1;   # (a whole aggregate it is: made at its way's end, where it stands)
    if ( my $want = ( $b->{ret_phi} // {} )->{ refaddr($p) } ) { return $b->ret_way($want, $in) }
    return $b->as($b->value($in), $ty) unless $ty eq '%Array*';
    my $pad = ( $b->{phi_store} // {} )->{ refaddr($p) } or return $b->as_list($in);
    my $var = $b->array_var($pad);
    my $l = $b->as_list($in);
    $b->emit(op => 'AAssign', type => 'void', inputs => [ $var, $l ]) unless refaddr($l) == refaddr($var);
    return $var;
}

# A LOOP PHI'S TYPE: its stamp, except a Str one, which a Num may reach on a
# later pass -- boxed, as a merge of differing arms is.
sub loop_type { my ($b, $phi) = @_; return $b->phi_type($phi) }

# The T2 type a T1 value is, decided once.
sub type_of {
    my ($b, $v) = @_;
    my $op = $v->operation;
    return '%Slot' if $op eq 'EnvRead' || $op eq 'DefinedOr' || $op eq 'RegexCapture' || $op eq 'Wantarray';   # may be undef (a capture: its group took no part)
    return '%Slot' if ( $v->stamp // '' ) eq 'Regex';   # a qr value: an object of class Regexp
    return '%Array*' if $op =~ /\A(?:RegexMatch|Match)\z/ && _is_list($v);   # a match in list context: its list
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'split') {
        # IN SCALAR CONTEXT split gives its count of fields (not T2's yet)
        out('a split in scalar context') if grep { blessed($_) && $_->operation eq 'Assign' && !( $_->can('targets') && defined $_->targets )
            && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->can('sigil') ? $_->inputs->[0]->sigil // '$' : '$' ) eq '$' } ( $v->consumers // [] )->@*;
        return '%Array*';
    }
    # A SUB'S ARGUMENT AND RESULT are whatever its callers pass and it returns:
    # T1 types them per call site (add(2,3) Int, though add(0.5,1) is 1.5),
    # so in T2 each is a %Slot, read by its tag.
    return '%Slot' if $b->{args}{ refaddr($v) };
    # AN ARRAY is an %Array of %Slot, by pointer; a count of it an i64, an
    # element a %Slot (it holds what was stored, by its tag).
    # AN ARRAY REFERENCE is a %Slot (tag 6) over an %Array: a scalar.
    return '%Slot' if $op eq 'EntryDef' && $v->metaobject_class;   # a special hash (%SIG): its %Slot
    return $v->sigil eq '@' ? '%Array*' : '%Slot' if $v->is_package_aggregate;   # a hash is its %Slot
    return '%Slot' if $op eq 'ArrayLiteral' && ( $v->stamp // '' ) eq 'ArrayRef'; # static type
    return '%Slot' if $op eq 'Ref';
    return '%Slot' if $op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$';
    return $v->copy ? '%Slot' : '%Array*' if $op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '%';   # (a copy: its own hash; else its pairs)
    return '%Array*' if $op eq 'ArrayLiteral' || $v->is_array_deref || $v->is_my_array || $op eq 'ArgsSource' || $op eq 'ListAppend';
    return '%Array*' if $op eq 'Slice' || $op eq 'Range';   # a list of its own, made where it is
    return $b->_count_may_be_undef($v) ? '%Slot' : 'i64' if $op eq 'Count';   # (undef, or the count: see array_value)
    return '%Slot' if $op eq 'Subscript';
    # A HASH REFERENCE is a %Slot (tag 5) over a %Hash: it is a scalar.
    return '%Slot' if $op eq 'HashLiteral' && ( $v->stamp // '' ) =~ /\A(?:HashRef|Hash)\z/; # static type
    return '%Slot' if $v->is_my_hash;
    # length of a scalar: undef for undef, so a %Slot; of a string, an i64.
    return ( ( $v->inputs->[0]->stamp // '' ) !~ /\A(?:Array|ArrayRef)\z/ && $b->type_of($v->inputs->[0]) eq '%Slot' ) ? '%Slot' : 'i64' if $op eq 'Length'; # static type
    my $hk = $v->can('kind') ? $v->kind // '' : '';
    return 'i1' if $op eq 'Exists' && $hk =~ /\A(?:hash|array)\z/;
    return '%Slot' if $op eq 'Delete' && $hk eq 'hash';
    return ( $v->stamp // '' ) eq 'Scalar' ? '%Slot' : '%Array*'   # static type
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'caller';
    if ( my $t = t2_builtin( $v, 'type' ) ) { return $t }
    if ($op eq 'Call' && $v->lists_a_hash) {
        return $v->lists_a_hash eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar' ? 'i64' : '%Array*';
    }
    return '%Array*' if $op eq 'Call' && $v->reorders_list
        && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/;   # static type
    # localtime: its nine fields in a list, its text in scalar context (B::SoN
    # stamps which: `() = localtime` a List, `my $s = localtime` a Scalar).
    return ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/ ? '%Array*' : '%Str'   # static type
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'localtime';
    return '%Str' if $op eq 'Call' && $v->changes_case;
    return '%Array*' if $v->is_argv;
    return '%Slot' if $v->is_package_scalar;   # what it holds is what was stored last, anywhere
    return '%Slot*' if $op eq 'MakeCell' || $op eq 'CellParam';   # a captured variable's storage
    return '%Slot' if $op eq 'CellRead' || $op eq 'AnonSub';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'indirect';
    if ($op eq 'FieldAccess') {
        my (undef, $sg) = $b->field_of($v);
        return $sg eq '@' ? '%Array*' : '%Slot';   # a scalar's value, or a hash's (its %Slot)
    }
    return '%Str' if $op eq 'EntryDef';
    return '%Slot' if $op eq 'PadAccess' && $v->is_location;
    return '%Slot' if $op eq 'Increment' || $op eq 'Decrement';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) =~ /\A(?:direct|method|dynamic_method)\z/;
    return '%Slot' if $op eq 'Call' && $v->is_tie_builtin;
    return '%Str' if $op eq 'RefType';
    return $b->print_to_handle($v) ? '%Slot' : 'i64' if $op eq 'Print';   # (1, or undef where the handle is not open for writing)
    # ARITHMETIC ON A %Slot is perl's: Ints stay Ints until they overflow. Done
    # as doubles (T1 may say Num), fact(20) lost its digits.
    return '%Slot' if $ARITH{$op} && grep { $b->type_of($_) eq '%Slot' } $v->inputs->@[0, 1];
    # NUMIFYING A SCALAR OR A STRING is perl's: an Int stays one, an integer
    # string is parsed whole -- through a double, 9007199254740993 lost its 3.
    return '%Slot' if $op eq 'Coerce' && ( $v->stamp // '' ) eq 'Num' # static type
        && $b->type_of($v->inputs->[0]) =~ /\A%(?:Slot|Str)\z/;
    return $b->phi_type($v) if $op eq 'Phi';
    # ** IS AN INTEGER where perl's is (an integer to a power, small enough),
    # else a number: which, at run time.
    return '%Slot' if $op eq 'Power';
    # readline IN A LIST: every line left.
    return ( $v->stamp // '' ) =~ /\A(?:List|Array)\z/ ? '%Array*' : '%Slot'   # static type
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'readline';
    # A BITWISE OP's result is a number, or (perl's choice, on two strings) bytes.
    return '%Slot' if $op =~ /\A(?:BitAnd|BitOr|BitXor|Complement|LeftShift|RightShift)\z/;
    # (LIST) x N: a list.
    return '%Array*' if $op eq 'Repeat' && ( $v->stamp // '' ) eq 'List';   # static type
    return '%Slot' if ( $v->stamp // '' ) =~ /\A(?:Unknown|None)\z/; # static type
    if ($op eq 'And' || $op eq 'Or') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[0, 1];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    if ($op eq 'TernaryExpr') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[1, 2];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    # A GLOB is a value T2 knows only by its name (a string of it, the type of
    # a reference to it): its slots and its address are the stash's.
    out('a glob read other than as a string, or a reference to it other than by ref (its slots are the stash\'s)')
        if _glob_name($v) || _glob_of($v);
    my $st = $v->stamp // ''; # static type
    return '%Slot' if $st =~ /\AMaybe\[/;   # T or undef: a %Slot
    return $SCALAR{$st} // out("a value stamped $st ($op)");
}

# value($t1) -> the T2 node for a T1 value, built once.
sub value {
    my ($b, $v) = @_;
    # (one made the same anywhere is made again here: a constant, `$ENV{X} // "a"`)
    out('a value an eval made, read past its end')
        if delete $b->{past_eval}{ refaddr($v) } and !$v->all_made_the_same;
    out('a read through a reference an arm made, read again past a call or a store')
        if $b->{arm_settled} && $b->{arm_settled}{ refaddr($v) } && !$b->{memo}{ refaddr($v) };
    return $b->{memo}{ refaddr($v) } //= $b->_value($v);
}

sub _value {
    my ($b, $v) = @_;
    # $& $` $' $+ @- @+ %+: of the last match that succeeded -- B::SoN gives
    # them as package variables, of no match: never read as one.
    out( 'the match variable ' . ( $v->sigil // '$' ) . $v->symbol . ' (B::SoN ties it to no match)' )
        if $v->operation eq 'EntryDef' && ( $v->symbol // '' ) =~ /\A(?:[&`'+-]|\d+)\z/;
    return $b->pkg_agg($v) if $v->is_package_aggregate;
    return $b->special_hash($v) if $v->operation eq 'EntryDef' && $v->metaobject_class;
    # $] IS THE VERSION OF THE PERL T2 IS: the one compiling (whose semantics it
    # keeps), read-only.
    return $b->as( $b->const_str("$]"), $b->type_of($v) )   # (its text: "5.042000")
        if blessed($v) && $v->operation eq 'EntryDef' && ( $v->sigil // '' ) eq '$' && ( $v->symbol // '' ) eq ']' && ( ( $v->can('package') ? $v->package : undef ) // 'main' ) eq 'main';
    # THE LITERAL A PACKAGE AGGREGATE WAS STORED FROM is how B::SoN gives a
    # later read of the name: read as the aggregate, which a push or another
    # sub may have changed since (a copy of the literal printed "1 2" for "1 2 3").
    if (my $t = $v->stored_whole_into) { return $b->pkg_agg($t) }
    # A qr// VALUE (a regex constant read as a value): an object of class Regexp.
    return $b->qr_value($v) if $v->operation eq 'Constant' && ( $v->const_type // '' ) eq 'regex';
    # A PRINT THAT RAN AS A STATEMENT (in an arm of && or ||) read as a value
    # after the join: perl's print returns 1, and the merge reads it only on
    # the path where it ran.
    if ($v->operation eq 'Print' && $v->can('control_in') && blessed($v->control_in)) {
        out('a print to a handle read as a value past where it ran') if $b->print_to_handle($v);
        return $b->emit(op => 'Const', type => 'i64', attr => { value => 1 });
    }
    # AN ARGUMENT READ (a shift, $_[N], a signature parameter) is the argument.
    if (my $arg = $b->{args}{ refaddr($v) }) { return $arg }
    # (a read after the Assign takes it as input; a target read is its input)
    if ($b->{argsarr} && $v->operation eq 'PadAccess'
        && ( my ($as) = ( ( grep { blessed($_) && $_->is_args_list_assign } $v->inputs->@* ),
                          ( grep { blessed($_) && $_->is_args_list_assign && grep { blessed($_) && refaddr($_) == refaddr($v) } $_->inputs->@[ 0 .. $_->inputs->$#* - 1 ] } ( $v->consumers // [] )->@* ) ) )) {
        out('a read of `my (...) = @_` in a sub that shifts @_') if $b->{args_mutated};
        return $b->args_elem($as, $v);
    }
    my $op = $v->operation;
    my $ty = $b->type_of($v);
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'direct') { return $b->call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) =~ /\A(?:method|dynamic_method)\z/) { return $b->method_call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'indirect') {
        my ($code, @args) = $v->inputs->@*;
        pop @args if $v->can('memory_input') && $v->memory_input;
        return $b->code_call($v, $b->as($b->value($code), '%Slot'), @args);
    }
    if ($op eq 'MakeCell' && blessed( $v->inputs->[0] ) && $v->inputs->[0]->operation eq 'PadAccess'
        && ( $v->inputs->[0]->sigil // '' ) =~ /\A[\@%]\z/) {
        # A `my` ARRAY OR HASH A CLOSURE CAPTURES: its cell holds a reference
        # to the variable's one storage (made at the function's entry), which
        # the closure reaches through it (array_var, hash_var). Made where the
        # variable is: one a loop or an arm renews is a new one each time.
        my ($pad, $ver) = $v->inputs->@*;
        my $at = blessed($ver) ? $b->{at}{ refaddr($ver) } : undef;
        my $depth = $at ? $at->[2] : blessed($ver) && $ver->operation eq 'MemStart' ? 0 : $b->{depth};
        out('an aggregate captured in a loop body or an arm') if $depth;
        my $key = 'cell' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
        return $b->{locs}{$key} //= do {
            my $agg = $pad->sigil eq '@' ? $b->array_var($pad) : $b->hash_var($pad);
            my $c = $b->emit_entry_end(op => 'HeapCell', type => '%Slot*', attr => { name => $pad->name });
            my $r = $pad->sigil eq '@' ? $b->emit_entry_end(op => 'ARef', type => '%Slot', inputs => [$agg]) : $agg;
            $b->emit_entry_end(op => 'Store', type => 'void', inputs => [ $r, $c ]);
            $c;
        };
    }
    if ($op eq 'MakeCell') {
        # THE CELL IS THE VARIABLE'S OWN STORAGE (the maker reads and writes it
        # as the closure does). A variable a loop renews, captured in it, is a
        # new one each pass: not this (one storage per call).
        my $var = Chalk::Target::LLVM::Context::_cell_variable($v) // out('a captured variable that is not one kept in memory');
        # WHERE THE CELL IS MADE, not where it is first used: the aggregate
        # arm's rule. A closure made at the top and called in an arm or a
        # loop (`if (...) { $add->(5) }`) asked for its cell there, and was
        # refused as one captured in the arm.
        my $ver = $v->inputs->[1];
        my $at = blessed($ver) ? $b->{at}{ refaddr($ver) } : undef;
        my $depth = $at ? $at->[2] : blessed($ver) && $ver->operation eq 'MemStart' ? 0 : $b->{depth};
        out('a variable captured in a loop body or an arm') if $depth;
        return $b->location($var);
    }
    if ($op eq 'CellParam') {
        my $env = $b->{env} // out('a captured variable outside a closure');
        my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $v->index });
        return $b->emit(op => 'EnvGet', type => '%Slot*', inputs => [ $env, $ix ]);
    }
    if ($op eq 'CellRead') {
        return $b->emit(op => 'Load', type => '%Slot', inputs => [ $b->value( $v->inputs->[0] ) ]);
    }
    if ($op eq 'AnonSub') { return $b->code_value($v) }
    # wantarray: the main program's is undef (no caller). A sub's is its
    # caller's context, which may be void (undef): T2 holds list or scalar only.
    if ($op eq 'Wantarray') {
        out('wantarray in a sub (T2 has no void context)') if $b->{in_func};
        return $b->emit(op => 'Undef', type => '%Slot');
    }
    # A push B::SoN left off the chain, a body's last statement (an ADJUST's):
    # made where its value is wanted -- its Return, the only use allowed.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'push' && !$v->is_pinned) {
        out('a push off the chain used other than by a return')
            if grep { blessed($_) && $_->operation ne 'Return' } ( $v->consumers // [] )->@*;
        $b->array_stmt($v);
        return $b->{memo}{ refaddr($v) };
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless') {
        my @in = $v->inputs->@*;
        pop @in if $v->can('memory_input') && $v->memory_input;
        # ONE ARGUMENT blesses into the package the bless is in: not known here.
        out('a bless of one argument') unless @in == 2;
        return $b->emit(op => 'Bless', type => '%Slot',
            inputs => [ $b->as($b->value($in[0]), '%Slot'), $b->as($b->value($in[1]), '%Str') ]);
    }
    # blessed($x): the class a reference was blessed into, else undef.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'blessed') {
        my @in = grep { blessed($_) } $v->inputs->@*;
        pop @in if $v->can('memory_input') && $v->memory_input;
        out('a blessed of other than one argument') unless @in == 1;
        return $b->emit(op => 'ClassOf', type => '%Slot', inputs => [ $b->as($b->value($in[0]), '%Slot') ]);
    }
    # $$r: what the variable r refers to holds; perl's die where r is no SCALAR
    # reference (a string under strict refs; undef too), its eval's to catch.
    # A FOREACH ALIAS READ (B::SoN's ${ \ $_[i] }, a guard of its existence
    # around it): the deref of a reference to an element is that element.
    if ( $op eq 'PostfixDeref' && ( my $el = $v->alias_element ) ) {
        my $arr = do { local $b->{elem_read} = 1; $b->array_of( $el->inputs->[0] ) };
        return $b->as( $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->as( $b->value( $el->inputs->[1] ), 'i64' ) ]), $ty );
    }
    if ($op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$') {
        my $at = $b->deref_at($v);
        my $r = $b->emit(op => 'SDeref', type => '%Slot', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ],
            attr => { strict => ( $v->can('strict') && $v->strict ? 1 : 0 ), %$at });
        $b->after_call;
        return $b->as($r, $ty);
    }
    # localtime(TIME) (now where there is none): libc's localtime_r -- its
    # nine fields in a list, ctime's text in scalar context.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'localtime') {
        my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out('a localtime of more than one argument') if @a > 1;
        $b->list_only($v, 'a localtime list') if $ty eq '%Array*';
        my $t = @a ? $b->as($b->value($a[0]), 'i64') : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        my $now = $b->emit(op => 'Const', type => 'i1', attr => { value => @a ? 0 : 1 });
        return $b->emit(op => 'LocalTime', type => $ty, inputs => [ $t, $now ]);
    }
    # qx`CMD` / readpipe IN SCALAR CONTEXT: all the command printed (t2_qx).
    # In a list (its lines) it is not T2's; nor a program reading $? (its
    # exit status is not kept). Printed, the lines are the whole text.
    if ($op eq 'BacktickExpr') {
        out('a qx in list context') if _is_list($v) || grep {
            my $u = $_;
            $u->operation =~ /\A(?:ArrayLiteral|ListAppend|Return)\z/
                || $u->operation eq 'Call' && ( $u->is_sub_call || $u->takes_a_list )
                || $u->operation eq 'Assign' && $u->can('targets') && defined $u->targets
        } grep { blessed($_) } ( $v->consumers // [] )->@*;
        out('a qx where the program reads $?') if grep { $_->operation eq 'EntryDef' && ( $_->symbol // '' ) eq '?' } _all_nodes($b->{mop}, $b->{ret});
        my ($cmd) = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out('a qx of no command') unless $cmd;
        return $b->as($b->emit(op => 'Qx', type => '%Str', inputs => [ $b->as($b->value($cmd), '%Str') ]), $ty);
    }
    if ($op eq 'RefType') {
        # A REFERENCE TO A GLOB is of type GLOB (its address is the stash's: not made).
        return $b->const_str('GLOB') if _glob_of( $v->inputs->[0] );
        return $b->emit(op => 'RefType', type => '%Str', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ]);
    }
    # A READ OF A VARIABLE KEPT IN MEMORY: a load, where it is first used (or
    # earlier, before a store that replaces its version: reads_before).
    if ($op eq 'PadAccess' && $v->is_location) {
        return $b->as($b->emit(op => 'Load', type => '%Slot', inputs => [ $b->location($v) ]), $ty);
    }
    if (my $h = $b->hash_value($v, $op)) { return $h }
    if (my $arr = $b->array_value($v, $op)) { return $arr }
    if ($op eq 'FieldAccess') {
        my ($key, $sg) = $b->field_of($v);
        my $self = $b->{self} // out('a field outside a method');
        out('a field read of no one version') if $b->{unversioned}{ refaddr($v) };
        my $slot = $b->emit(op => 'HGet', type => '%Slot', inputs => [ $self, $b->const_str($key) ]);
        return $sg eq '@' ? $b->emit(op => 'ADeref', type => '%Array*', inputs => [$slot]) : $slot;
    }
    if ($v->is_package_scalar) {
        out('a package scalar read of no one version') if $b->{unversioned}{ refaddr($v) };
        return $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->global_of($v) });
    }
    if ($op eq 'Call' && $v->changes_case) {
        # ASCII CASE: past ASCII perl's case is a character's (refused there).
        $b->{past_ascii} //= scalar grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'string' && ( $_->value // '' ) =~ /[^\x00-\x7f]/ }
            _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        out('a case change where a string goes past ASCII') if $b->{past_ascii};
        my @a = grep { blessed($_) } $v->inputs->@*;
        pop @a if $v->can('memory_input') && $v->memory_input;
        out('a case change of other than one argument') unless @a == 1;
        my %mode = (uc => 0, lc => 1, ucfirst => 2, lcfirst => 3);
        my $m = $b->emit(op => 'Const', type => 'i64', attr => { value => $mode{ $v->name } });
        return $b->emit(op => 'StrCase', type => '%Str', inputs => [ $b->as($b->value($a[0]), '%Str'), $m ]);
    }
    if ($op eq 'Length') {
        # perl's length counts characters; T2's strings are bytes -- the same
        # only while no string constant goes past ASCII.
        $b->{past_ascii} //= scalar grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'string' && ( $_->value // '' ) =~ /[^\x00-\x7f]/ }
            _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        out('a length where a string goes past ASCII') if $b->{past_ascii};
        my $in0 = $v->inputs->[0];
        # LENGTH OF AN ARRAY is its count (the IR's Length of an Array/ArrayRef).
        return $b->as($b->emit(op => 'ALen', type => 'i64', inputs => [ $b->array_of($in0) ]), $ty)
            if ( $in0->stamp // '' ) =~ /\A(?:Array|ArrayRef)\z/ || $b->type_of($in0) eq '%Array*'; # static type
        my $x = $b->value($in0);
        return $b->emit(op => 'SlotLength', type => '%Slot', inputs => [$x]) if $ty eq '%Slot';
        return $b->emit(op => 'StrLen', type => 'i64', inputs => [ $b->as($x, '%Str') ]);
    }
    if ($op eq 'Not') {
        # perl's !: the operand's truth, inverted.
        my $x = $b->as($b->value($v->inputs->[0]), 'i1');
        my $f = $b->emit(op => 'Const', type => 'i1', attr => { value => 0 });
        return $b->as($b->emit(op => 'Cmp', type => 'i1', attr => { op => 'eq' }, inputs => [ $x, $f ]), $ty);
    }
    if ($op eq 'Defined') {
        return $b->emit(op => 'Defined', type => 'i1', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ]);
    }
    if ($op eq 'Increment' || $op eq 'Decrement') {
        # perl's ++ (a string's magic increment too) and --, on a scalar.
        return $b->as($b->emit(op => 'SlotStep', type => '%Slot', attr => { op => $op eq 'Increment' ? 'inc' : 'dec' },
            inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ]), $ty);
    }
    if ($op eq 'Constant') {
        my $c = $v->value;
        return $b->emit(op => 'Undef', type => '%Slot') if $ty eq '%Slot';
        # AN INTEGER PAST WHAT AN i64 HOLDS (a UV perl folded, `~5`): printed as
        # an i64 it wrapped (-6 for 18446744073709551610).
        if ($ty eq 'i64' && defined $c && $c =~ /\A\+?(\d+)\z/) {
            ( my $d = $1 ) =~ s/\A0+(?=\d)//;
            out('an integer constant past what an i64 holds') if length $d > 19 || length $d == 19 && $d gt '9223372036854775807';
        }
        return $b->emit(op => 'Const', type => $ty, attr => { value => $c }) if $ty ne '%Str';
        $b->{strs}{$c} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
    }
    if ( my $m = t2_builtin( $v, 'value' ) ) { return $b->$m($v, $ty) }
    if ($op eq 'Coerce') {
        # TO Undef IS NOT A CONVERSION: undef has no value to convert into, and
        # boxing the value would keep it.
        out('a coercion to Undef') if ( $v->stamp // '' ) eq 'Undef'; # static type
        return $b->emit(op => 'Numify', type => '%Slot', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ])
            if $ty eq '%Slot' && ( $v->stamp // '' ) eq 'Num'; # static type
        # A GLOB READ AS A STRING is its name: *main::x.
        if ( my $g = _glob_name( $v->inputs->[0] ) ) {
            out('a glob read as other than a string') unless ( $v->stamp // '' ) eq 'Str';   # static type
            return $b->as( $b->const_str("*$g"), $ty );
        }
        return $b->as($b->value($v->inputs->[0]), $ty);
    }
    if ($op eq 'Divide') {
        # A DIVISION T1 TYPED Int is T1's error (7/2 is 3.5): not truncated here.
        out('a Divide typed Int') if $ty eq 'i64';
        # PERL DIVIDES AS NUMBERS and dies on a zero divisor, naming where.
        my $msg = "Illegal division by zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
        my $q = $b->emit(op => 'Div', type => 'double',
            inputs => [ map { $b->as($b->value($_), 'double') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        $b->after_call;   # (a zero divisor is a die: an eval's to catch)
        return $b->as($q, $ty);
    }
    if ($op eq 'Modulo') {
        # PERL'S % IS OF INTEGERS, its sign the right side's, and dies on zero.
        out('a % not typed Int') unless $ty eq 'i64';
        my $msg = "Illegal modulus zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
        my $r = $b->emit(op => 'Mod', type => 'i64',
            inputs => [ map { $b->as($b->value($_), 'i64') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        $b->after_call;   # (a zero modulus is a die: an eval's to catch)
        return $r;
    }
    # `ref \$x` (B::SoN's reftype_of_ref): what kind of thing $x holds.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'reftype_of_ref') {
        return $b->as( $b->emit(op => 'KindOfRef', type => '%Slot', inputs => [ $b->as( $b->value( $v->inputs->[0] ), '%Slot' ) ]), $ty );
    }
    # -x: perl's, on the value it has at run time (t2_slot_neg).
    if ($op eq 'Negate') {
        return $b->as( $b->emit(op => 'SlotNeg', type => '%Slot', inputs => [ $b->as( $b->value( $v->inputs->[0] ), '%Slot' ) ]), $ty );
    }
    if (my $a = $ARITH{$op}) {
        if ($ty eq '%Slot') {
            return $b->emit(op => 'SlotArith', type => '%Slot', attr => { op => $a },
                inputs => [ map { $b->as($b->value($_), '%Slot') } $v->inputs->@[0, 1] ]);
        }
        my @in = map { $b->as($b->value($_), $ty) } $v->inputs->@[0, 1];
        # PERL'S INTEGERS DO NOT WRAP: past what an i64 holds its result is a
        # UV or a number, which an Int-typed value cannot be -- stopped by
        # name where it overflows (4611686018427387904 * 2 printed
        # -9223372036854775808 for 9223372036854775808).
        return $b->emit(op => 'IntArith', type => 'i64', inputs => \@in, attr => { op => $a }) if $ty eq 'i64';
        return $b->emit(op => 'Arith', type => $ty, inputs => \@in, attr => { op => $a });
    }
    if (my $c = $CMP{$op}) {
        my @in = map { $b->value($_) } $v->inputs->@[0, 1];
        my $t = ( grep { $_->type ne 'i64' } @in ) ? 'double' : 'i64';
        return $b->emit(op => 'Cmp', type => 'i1', inputs => [ map { $b->as($_, $t) } @in ], attr => { op => $c });
    }
    # <=>: -1, 0 or 1, as (x > y) - (x < y).
    # shortcut: a NaN operand gives 0, perl's undef; return a %Slot if a NaN program needs it.
    if ($op eq 'NumCmp') {
        my @in = map { $b->value($_) } $v->inputs->@[0, 1];
        my $t = ( grep { $_->type ne 'i64' } @in ) ? 'double' : 'i64';
        my ($gt, $lt) = map { my $c = $_; $b->as($b->emit(op => 'Cmp', type => 'i1', inputs => [ map { $b->as($_, $t) } @in ], attr => { op => $c }), 'i64') } qw(gt lt);
        return $b->as($b->emit(op => 'Arith', type => 'i64', inputs => [ $gt, $lt ], attr => { op => 'sub' }), $ty);
    }
    # PERL'S STRING COMPARISONS: bytewise, a shorter prefix first (cmp's
    # -1, 0 or 1; the others it against 0).
    if ($op eq 'StrCmp' || $SCMP{$op}) {
        my $c3 = $b->emit(op => 'StrCmp', type => 'i64', inputs => [ map { $b->as($b->value($_), '%Str') } $v->inputs->@[0, 1] ]);
        return $b->as($c3, $ty) if $op eq 'StrCmp';
        my $z = $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        return $b->as($b->emit(op => 'Cmp', type => 'i1', inputs => [ $c3, $z ], attr => { op => $SCMP{$op} }), $ty);
    }
    if ($op eq 'Concat') {
        return $b->emit(op => 'Concat', type => '%Str', inputs => [ map { $b->as($b->value($_), '%Str') } $v->inputs->@[0, 1] ]);
    }
    if ($op eq 'EnvRead') {
        my $k = $v->key // out('an EnvRead with no key');
        $b->{strs}{$k} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'Env', type => '%Slot', attr => { key => $k, id => $b->{strs}{$k} });
    }
    # A // WHOSE LEFT SIDE IS NOT A %Slot: a number, a string, a truth is never
    # undef in T2 (undef is a %Slot's tag), so it is the left side, and the
    # right side is never evaluated.
    if ($op eq 'DefinedOr') {
        my $lhs = $b->value($v->inputs->[0]);
        return $b->as($lhs, $ty) unless $lhs->type eq '%Slot';
    }
    if ($op eq 'DefinedOr' || $op eq 'TernaryExpr' || $op eq 'And' || $op eq 'Or') {
        # A MERGE: its condition, an arm built in each block, a phi at the join.
        my ($cond, $then, $else);
        if ($op eq 'And' || $op eq 'Or') {
            # (OF A LIST -- `@x && sort ...` in list context -- the value is the
            # list or the left side's count, not one scalar: refused)
            out('an && or || of a list') if grep { _is_list($_) || $b->type_of($_) eq '%Array*' } grep { blessed($_) } $v->inputs->@[0, 1];
            # perl's && and ||: the left side's value when it decides, else
            # the right side's (built only then).
            my $lhs = $b->value($v->inputs->[0]);
            $cond = $b->truth($lhs);
            ($then, $else) = $op eq 'And' ? ( $v->inputs->[1], $lhs ) : ( $lhs, $v->inputs->[1] );
        }
        elsif ($op eq 'TernaryExpr') {
            ($cond, $then, $else) = $v->inputs->@*;
            $cond = $b->truth($b->value($cond));
        }
        else {
            my $lhs = $b->value($v->inputs->[0]);
            $cond = $b->emit(op => 'Defined', type => 'i1', inputs => [$lhs]);
            ($then, $else) = ($lhs, $v->inputs->[1]);
        }
        my $from = $b->{cur};
        # A VALUE MADE IN AN ARM IS THE ARM'S: it does not dominate the join, so
        # it is not seen after it (each arm gets the memo as it was before).
        my $tb = $b->new_block('then');
        my ($tv, $ev);
        { local $b->{memo} = { $b->{memo}->%* };
          local $b->{rx_ok} = $v->operation eq 'TernaryExpr' ? _rx_arm( $b->{rx_ok}, $v->inputs->[0], 0 ) : $b->{rx_ok};
          $tv = $b->as( blessed($then) && $then->isa('Chalk::Target::LLVM::Node') ? $then : $b->value($then), $ty ); }
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        { local $b->{memo} = { $b->{memo}->%* };
          $ev = $b->as( blessed($else) && $else->isa('Chalk::Target::LLVM::Node') ? $else : $b->value($else), $ty ); }
        my $eend = $b->{cur};
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $cond, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => $ty, inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
    if ($op eq 'Power') {
        return $b->as( $b->emit(op => 'Pow', type => '%Slot', inputs => [ map { $b->as( $b->value($_), '%Slot' ) } $v->inputs->@[0, 1] ]), $ty );
    }
    if ($op eq 'Repeat') {
        my ($l, $n) = $v->inputs->@[0, 1];
        my $k = $b->as( $b->value($n), 'i64' );
        # (B::SoN coerces the list to a Str there: the list repeated is the list)
        $l = $l->inputs->[0] while $ty eq '%Array*' && blessed($l) && $l->operation eq 'Coerce' && blessed( $l->inputs->[0] ) && _is_list( $l->inputs->[0] );
        return $b->emit(op => 'ARepeat', type => '%Array*', inputs => [ $b->array_of($l), $k ]) if $ty eq '%Array*';
        out('a Repeat of a list in scalar context') if _is_list($l);
        return $b->as( $b->emit(op => 'Repeat', type => '%Str', inputs => [ $b->as( $b->value($l), '%Str' ), $k ]), $ty );
    }
    return $b->bitwise($v) if $op =~ /\A(?:BitAnd|BitOr|BitXor|Complement|LeftShift|RightShift)\z/;
    # chomp's (or chop's) string of a value, and how many it took off. chomp
    # takes $/ off: "\n", unless the program writes $/ (not T2's). Of a
    # string past ASCII, chop's last character is not its last byte.
    if ($op eq 'Chomp' || $op eq 'ChompValue') {
        my $kind = $v->can('kind') ? $v->kind // 'chomp' : 'chomp';
        out("a $kind of a list") if _is_list( $v->inputs->[0] );
        out('a chomp in a program that writes $/') if $kind eq 'chomp' && grep { $_->operation =~ /\A(?:EntryWrite|LocalAlias)\z/
            && grep { blessed($_) && $_->can('symbol') && ( $_->symbol // '' ) eq '/' } ( $_, $_->inputs->@* ) } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        out('a chop where a string goes past ASCII') if $kind eq 'chop' && $b->past_ascii;
        out("a $kind T2 does not have") unless $kind =~ /\A(?:chomp|chop)\z/;
        my $s = $b->as( $b->value( $v->inputs->[0] ), '%Str' );
        return $b->as( $b->emit(op => $op eq 'Chomp' ? 'Chomp' : 'ChompN', type => $op eq 'Chomp' ? '%Str' : 'i64', inputs => [$s], attr => { chop => $kind eq 'chop' }), $ty );
    }
    # `$o isa C`: through the run-time MOP's @ISA.
    if ($op eq 'IsaOp') {
        my ($o, $c) = $v->inputs->@[0, 1];
        # INHERITANCE `use parent` / `use base` SETS UP is in a use the loader
        # drops: the run-time MOP has no such parent ("n" for perl's "y").
        out('an isa in a program that uses parent or base (inheritance the loader drops)')
            if $Chalk::IR::Serialize::JSON::USED_MODULES{parent} || $Chalk::IR::Serialize::JSON::USED_MODULES{base};
        return $b->as( $b->emit(op => 'IsaOp', type => 'i1', inputs => [ $b->as( $b->value($o), '%Slot' ), $b->as( $b->value($c), '%Str' ) ]), $ty );
    }
    # `A xor B`: their truths differ.
    if ($op eq 'Xor') {
        my ($x, $y) = map { $b->truth( $b->value($_) ) } $v->inputs->@[0, 1];
        return $b->as( $b->emit(op => 'Cmp', type => 'i1', inputs => [ $x, $y ], attr => { op => 'ne' }), $ty );
    }
    if ($op eq 'Call' && $v->does_handle_io) {
        return $b->as( $b->io_value($v), $ty );
    }
    # A REGEX MATCH OF A CONSTANT PATTERN is a call of its own graph
    # (Chalk::Regex::Graph): [start, end, groups...] or undef; it is true when
    # that is defined. A capture reads the offsets of the match it names.
    if ($op eq 'RegexSubst' || $op eq 'Transliterate') {
        # IN PLACE (pinned, of a `my` scalar): how many it replaced. Else --
        # /r, floating, or of a value B::SoN folded a copy into -- the new string.
        return $b->as( $v->is_in_place ? $b->regex_subst_count($v) : $b->regex_subst_part( $v, 0 ), $ty );
    }
    return $b->as( $b->regex_subst_count( $v->inputs->[0] ), $ty ) if $op eq 'RegexSubstCount' || $op eq 'TransliterateCount';
    # pos($s): its cell (undef where no m//g left it)
    return $b->as( $b->emit(op => 'Load', type => '%Slot', inputs => [ ( $b->pos_cells( $v->inputs->[0] ) )[0] ]), $ty )
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'pos';
    return $b->array_of($v) if ( $op eq 'RegexMatch' || $op eq 'Match' ) && _is_list($v);
    return $b->as($b->emit(op => 'Defined', type => 'i1', inputs => [ $b->regex_result($v) ]), $ty) if $op eq 'RegexMatch' || $op eq 'Match';
    return $b->regex_capture($v) if $op eq 'RegexCapture';
    # A REGEX MATCH, literal or a qr value: no engine in T2 yet (the fallback has one).
    out('a regex match: T2 has no regex engine yet') if $op =~ /\A(?:RegexMatch|Match|RegexSubst|Subst|QrConst|Split)\z/;
    out($op . ( $op eq 'Call' ? ' ' . ( $v->dispatch_kind // '' ) . ' ' . ( $v->name // '' ) : '' ));
}

# -d PATH: a directory (1), something else there (''), nothing (undef).
# chdir PATH: 1, or '' where it could not. A require of a file B::SoN
# followed is done -- its subs are compiled in (1); of any other, not T2's.
sub path_value {
    my ($b, $v, $ty) = @_;
    my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
    out( 'a ' . $v->name . ' of no argument' ) unless @a;
    if ( $v->name eq 'require' ) {
        my $f = $a[0];
        out('a require of a file named at run time') unless $f->operation eq 'Constant' && defined $f->value;
        ( my $mod = $f->value ) =~ s{\.pm\z}{}; $mod =~ s{/}{::}g;
        # A BUILT-IN (strict, warnings) loads no file; a module B::SoN followed
        # is compiled in. Either is entered in the registry where the program
        # reads %INC.
        out( 'a require of ' . $f->value . ', not compiled in' )
            unless Chalk::Impl::is_built_in( $f->value )
                || $Chalk::IR::Serialize::JSON::FOLLOWED{ $f->value } || $Chalk::IR::Serialize::JSON::FOLLOWED{$mod};
        $b->impl_call( '%INC', 'enter', $b->as( $b->const_str( Chalk::Impl::inc_key( $f->value ) ), '%Slot' ) )
            if $b->special_containers->{'%INC'};
        return $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), $ty );
    }
    return $b->as( $b->emit(op => $v->name eq 'ftdir' ? 'FtDir' : 'Chdir', type => '%Slot', inputs => [ $b->as( $b->value( $a[0] ), '%Str' ) ]), $ty );
}

# int(X): X's number truncated toward zero. rand(X): a number in [0, X),
# X 1 when absent or 0 (perl's), from libc's generator -- not perl's.
sub number_value {
    my ($b, $v, $ty) = @_;
    my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
    out('an int of no argument (of $_)') if $v->name eq 'int' && !@a;
    my $x = @a ? $b->as( $b->value( $a[0] ), '%Slot' ) : $b->emit(op => 'Undef', type => '%Slot');
    return $b->as( $b->emit(op => $v->name eq 'int' ? 'IntOf' : 'Rand', type => '%Slot', inputs => [$x]), $ty );
}

# substr($s, $off, $len) READ (not an lvalue: B::SoN pins a store): from
# either end, the rest or a length (negative leaves that many off the end);
# undef outside the string, as perl's. index($s, $t, $pos): -1 for none.
sub substr_value {
    my ($b, $v, $ty) = @_;
    my @a = grep { blessed($_) } $v->inputs->@*;
    pop @a if $v->can('memory_input') && $v->memory_input;
    return $b->{memo}{ refaddr($v) } // out('a four-argument substr read before it is made') if $v->name eq 'substr' && @a == 4;
    out('a ' . $v->name . ' of more than three arguments') if @a > 3;
    my $str = $b->as( $b->value( $a[0] ), '%Str' );
    if ($v->name eq 'substr') {
        out('a substr of fewer than two arguments') if @a < 2;
        my $off = $b->as( $b->value( $a[1] ), 'i64' );
        my ( $len, $has ) = @a > 2
            ? ( $b->as( $b->value( $a[2] ), 'i64' ), $b->emit(op => 'Const', type => 'i1', attr => { value => 1 }) )
            : ( $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }), $b->emit(op => 'Const', type => 'i1', attr => { value => 0 }) );
        return $b->emit(op => 'Substr', type => '%Slot', inputs => [ $str, $off, $len, $has ]);
    }
    out('an index of fewer than two arguments') if @a < 2;
    my $pos = @a > 2 ? $b->as( $b->value( $a[2] ), 'i64' ) : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
    return $b->emit(op => 'Index', type => 'i64', inputs => [ $str, $b->as( $b->value( $a[1] ), '%Str' ), $pos ]);
}

# _glob_name($n) -> the qualified name of the glob a constant `*name` is
# (B::SoN leaves main's unqualified), or undef for what is no glob.
sub _glob_name {
    my ($n) = @_;
    return undef unless blessed($n) && $n->operation eq 'Constant' && ( $n->const_type // '' ) eq 'glob' && defined $n->value;
    return $n->value =~ /::/ ? $n->value : 'main::' . $n->value;
}

# _glob_of($n) -> the glob's name where $n is a reference to a glob (`\*name`).
sub _glob_of {
    my ($n) = @_;
    return undef unless blessed($n) && $n->operation eq 'Ref';
    return _glob_name( $n->inputs->[0] );
}

# warn LIST: its message (the list joined) handed to its __WARN__ handler, else
# to STDERR -- t2_warn asks %SIG (the handler table) -- and true. Where it
# runs is its place on the control chain; one B::SoN puts on none runs
# nowhere it says: refused. A message not ending in a newline gets " at FILE
# line N.\n", the site B::SoN gives the warn (as a die's).
sub warn_value {
    my ($b, $v, $ty) = @_;
    out('a warn B::SoN places on no control chain (when it runs is not known)')
        unless $v->can('control_in') && blessed( $v->control_in );
    out('a warn B::SoN gives no file and line (perl names them where its message does not end in a newline)')
        unless defined $v->line;
    my @a = grep { blessed($_) } $v->inputs->@*;
    pop @a if $v->can('memory_input') && $v->memory_input;
    out('a warn of nothing (perl warns of $@, or that something is wrong)') unless @a;
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    for my $e (@a) {
        if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($e) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as( $b->value($e), '%Slot' ) ]) }
    }
    my $m = $b->emit(op => 'Join', type => '%Str', inputs => [ $b->const_str(''), $arr ]);
    my $at = $b->const_str( ' at ' . ( $v->file // '-' ) . ' line ' . $v->line . ".\n" );
    $b->hash_reads_settled('a warn');   # (its handler may store)
    return $b->as( $b->emit_call(op => 'Warn', type => '%Slot', inputs => [ $m, $at ]), $ty );
}

# builtin_value($Call, $ty) -> a builtin of one value: chr, ord, time, -e,
# reverse in scalar context, sprintf, lock.
sub builtin_value {
    my ($b, $v, $ty) = @_;
    my $name = $v->name;
    my @a = grep { blessed($_) } $v->inputs->@*;
    pop @a if $v->can('memory_input') && $v->memory_input;
    return $b->as( $b->emit(op => 'Time', type => 'i64'), $ty ) if $name eq 'time';
    if ($name eq 'reverse') {
        # IN SCALAR CONTEXT (a list's is an array): its list joined, its bytes last first.
        out('a reverse of $_') unless @a;
        out('a reverse past ASCII') if $b->past_ascii;
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@a) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as( $b->value($e), '%Slot' ) ]) }
        }
        my $s = $b->emit(op => 'Join', type => '%Str', inputs => [ $b->const_str(''), $arr ]);
        return $b->as( $b->emit(op => 'StrRev', type => '%Str', inputs => [$s]), $ty );
    }
    return $b->sprintf_value($v, $ty, @a) if $name eq 'sprintf';
    return $b->format_write($v, $ty, @a) if $name eq 'formline';
    if ($name eq 'prototype') {
        # prototype(\&f) OF A SUB NAMED HERE: its prototype as B::SoN gave it, undef for none.
        my $r = $a[0];
        my $c = blessed($r) && $r->operation eq 'Ref' ? $r->inputs->[0] : undef;
        out('a prototype of other than \&name') unless @a == 1 && blessed($c) && $c->operation eq 'Constant' && ( $c->const_type // '' ) eq 'code';
        out('a prototype of a sub the program does not define') unless exists $Chalk::IR::Serialize::JSON::PROTOTYPES{ $c->value // '' };
        my $p = $Chalk::IR::Serialize::JSON::PROTOTYPES{ $c->value };
        return $b->as( defined $p ? $b->as( $b->const_str($p), '%Slot' ) : $b->emit(op => 'Undef', type => '%Slot'), $ty );
    }
    if ($name eq 'pack') {
        # pack of C (a byte each) only: each value's byte, wrapped as pack wraps it.
        my ($t, @vals) = @a;
        out('a pack of a template made at run time') unless blessed($t) && $t->operation eq 'Constant' && defined $t->value;
        out('a pack of a list') if grep { _is_list($_) } @vals;
        my $want = 0;
        for my $item ( $t->value =~ /\G\s*(C(?:\d+|\*)?)/gc ) {
            my ($k) = $item =~ /C(.*)/;
            $want = $k eq '*' ? scalar @vals : $want + ( length $k ? $k : 1 );
        }
        out('a pack template other than C') unless $t->value =~ /\A(?:\s*C(?:\d+|\*)?)+\s*\z/;
        out('a pack of other than one value a byte') unless $want == @vals;
        out('a pack where a string goes past ASCII') if $b->past_ascii;
        my $r = $b->const_str('');
        $r = $b->emit(op => 'Concat', type => '%Str', inputs => [ $r, $b->emit(op => 'PackC', type => '%Str', inputs => [ $b->as( $b->value($_), '%Slot' ) ]) ]) for @vals;
        return $b->as( $r, $ty );
    }
    out("a $name of other than one argument (of \$_)") unless @a == 1;
    out("a $name of a list") if _is_list( $a[0] );
    # lock: perl's without threads is a no-op, its value its argument.
    return $b->as( $b->value( $a[0] ), $ty ) if $name eq 'lock';
    return $b->as( $b->emit(op => 'FtIs', type => '%Slot', inputs => [ $b->as( $b->value( $a[0] ), '%Str' ) ]), $ty ) if $name eq 'ftis';
    # chr, ord: of a byte -- perl's are of a character, the same while no string goes past ASCII.
    out("a $name where a string goes past ASCII") if $b->past_ascii;
    return $b->as( $b->emit(op => 'Chr', type => '%Str', inputs => [ $b->as( $b->value( $a[0] ), '%Slot' ) ]), $ty ) if $name eq 'chr';
    return $b->as( $b->emit(op => 'Ord', type => 'i64', inputs => [ $b->as( $b->value( $a[0] ), '%Str' ) ]), $ty );
}

# BITWISE OPS (pp_bit_and & co.). bitwise($op) -> its %Slot. Perl does & | ^
# ~ on two strings' bytes where no operand holds a number, on numbers
# otherwise (and under feature "bitwise" as the op says: its flavor). An
# operand T2 holds as a number decides it here; else at run time, by what
# the operands hold -- outside a loop or an arm. A result past what an i64
# holds (a UV) stops, unless only another bitwise op reads it.
#
# A NUMERIC READ OF A STRING LEAVES IT A NUMBER to the op after (perl caches
# the number): an operand read by bitwise ops alone (a shift's too) carries
# what those before did -- an i1, the string made a number (bit_numified) --
# and an op over one so made is on numbers. Sound where each reader is
# pinned: B::SoN pins a bitwise op on what may be a string only where each
# operand is one variable, assigned once (a node a copy or a second `my`
# shares stands for two: its op floats, and is refused here). Anything else
# reading the operand as a number is refused.
my %BITOP = (BitAnd => 0, BitOr => 1, BitXor => 2, Complement => 3);
sub bitwise {
    my ($b, $v) = @_;
    my $op = $v->operation;
    my @in = $op eq 'Complement' ? ( $v->inputs->[0] ) : $v->inputs->@[0, 1];
    # (B::SoN's numeric reading of an operand is not perl's: the value is)
    my @leaf = map { _bit_leaf($_) } @in;
    my $inner = _bit_inner($v);
    my @x = map { $b->as( $b->value($_), '%Slot' ) } @leaf;
    # (the operands that may be strings another bitwise op also reads)
    my @shared = grep { $b->type_of( $leaf[$_] ) =~ /\A%(?:Slot|Str)\z/ && $b->_bit_readers( $leaf[$_] ) > 1 } 0 .. $#leaf;
    if ($op =~ /Shift\z/) {
        my $r = $b->emit(op => 'Shift', type => '%Slot', inputs => \@x, attr => { left => $op eq 'LeftShift', inner => $inner });
        $b->bit_numified( $v, $leaf[$_], $x[$_], $b->emit(op => 'Const', type => 'i1', attr => { value => 1 }) ) for @shared;
        return $r;
    }
    my $flavor = $v->can('flavor') ? $v->flavor // '' : '';
    my $mode = $flavor eq 'numeric' ? 1 : $flavor eq 'string' ? 2
             : ( grep { $b->type_of($_) !~ /\A%(?:Slot|Str)\z/ } @leaf ) ? 1 : 0;
    if ($mode == 0) {
        out('a bitwise op on what may be strings, in a loop or an arm') if $b->{depth};
        out('a bitwise op on what may be a string read elsewhere (perl reads it as a number after a numeric read)')
            if grep { $b->_bit_readers($_) < 1 || $b->_bit_source_numified($_) } @leaf;
    }
    push @x, $b->emit(op => 'Undef', type => '%Slot') if @x == 1;
    # (one an op before made a number: on numbers, whatever its tag says)
    my %flag = $mode == 0 ? map { my $f = $b->bit_flag( $v, $leaf[$_] ); defined $f ? ( $_ => $f ) : () } @shared : ();
    my @f = map { $flag{$_} // $b->emit(op => 'Const', type => 'i1', attr => { value => 0 }) } 0, 1;
    my $r = %flag
        ? $b->emit(op => 'BitOpMade', type => '%Slot', inputs => [ @x, @f ], attr => { op => $BITOP{$op}, inner => $inner })
        : $b->emit(op => 'BitOp', type => '%Slot', inputs => \@x, attr => { op => $BITOP{$op}, mode => $mode, inner => $inner });
    if (@shared && $mode != 2) {
        my $num = $mode == 1 ? $b->emit(op => 'Const', type => 'i1', attr => { value => 1 })
                             : $b->emit(op => 'BitNumeric', type => 'i1', inputs => [ @x, @f ], attr => { op => $BITOP{$op} });
        $b->bit_numified( $v, $leaf[$_], $x[$_], $num ) for @shared;
    }
    return $r;
}

# bit_flag($op, $leaf) -> the i1 that says an earlier bitwise op made $leaf (a
# string) a number, where bitwise op $op reads it; undef where none has. Each
# reader of $leaf must be pinned (made in the order perl runs them), and none
# before made where its i1 is not seen here (a loop, an arm, an eval).
sub bit_flag {
    my ($b, $v, $leaf) = @_;
    out('a bitwise op on what may be a string another bitwise op reads, not both pinned where perl runs them')
        if grep { !( $_->can('control_in') && blessed( $_->control_in ) ) } $b->_bit_ops_of($leaf);
    my $f = $b->{bitflag}{ refaddr($leaf) };
    out('a bitwise op on what may be a string an op in a loop, an arm or an eval read as a number') if defined $f && !ref $f;
    return $f;
}

# bit_numified($op, $leaf, $x, $num): bitwise op $op, done on numbers where
# i1 $num, made $leaf (its value $x) a number if it was a string.
sub bit_numified {
    my ($b, $v, $leaf, $x, $num) = @_;
    my $k = refaddr($leaf);
    return if defined $b->{bitflag}{$k} && !ref $b->{bitflag}{$k};
    # (where its i1 would not be seen after: lost)
    if ( $b->{depth} || ( $b->{evals} // [] )->@* ) { $b->{bitflag}{$k} = 'lost'; return }
    my $was = $b->{bitflag}{$k} // $b->emit(op => 'Const', type => 'i1', attr => { value => 0 });
    $b->{bitflag}{$k} = $b->emit(op => 'BitNumified', type => 'i1', inputs => [ $was, $num, $x ]);
}

my $BIT = qr/\A(?:BitAnd|BitOr|BitXor|Complement|LeftShift|RightShift)\z/;

# _value_users($n) -> the nodes that take $n's value (not as their memory).
sub _value_users {
    my ($n) = @_;
    my %seen;
    return grep {
        my $u = $_;
        my @in = $u->inputs->@*;
        my $m = $u->can('memory_operand') ? $u->memory_operand : undef;
        my $uses = grep { blessed($_) && refaddr($_) == refaddr($n) } @in;
        $uses-- if blessed($m) && refaddr($m) == refaddr($n);
        $uses > 0
    } grep { blessed($_) && !$seen{ refaddr($_) }++ } ( $n->consumers // [] )->@*;
}

# _bit_leaf($n) -> $n under B::SoN's numeric Coerces of a bitwise operand.
sub _bit_leaf {
    my ($n) = @_;
    $n = $n->inputs->[0] while blessed($n) && $n->operation eq 'Coerce' && ( $n->stamp // '' ) =~ /\A(?:Int|Num)\z/ && blessed( $n->inputs->[0] );   # static type
    return $n;
}

# _bit_inner($op) -> only other bitwise ops read its value.
sub _bit_inner {
    my ($n) = @_;
    my @u = _value_users($n);
    my @other = grep { $_->operation !~ $BIT && !( $_->operation eq 'Coerce' && ( $_->stamp // '' ) =~ /\A(?:Int|Num)\z/ && _bit_inner($_) ) } @u;   # static type
    return @u && !@other ? 1 : 0;
}

# _bit_readers($leaf) -> how many bitwise ops read it; -1 where something
# else reads it but as a string (print, a join, a concatenation).
sub _bit_readers {
    my ($b, $n) = @_;
    my $k = 0;
    for my $u ($b->value_readers($n)) {
        my $o = $u->operation;
        if ($o =~ $BIT) { $k++; next }
        if ($o eq 'Coerce' && ( $u->stamp // '' ) =~ /\A(?:Int|Num)\z/) {   # static type
            my $r = $b->_bit_readers($u);
            return -1 if $r < 0;
            $k += $r;
            next;
        }
        next if $o eq 'Coerce' && ( $u->stamp // '' ) eq 'Str' && !grep { $_->operation !~ /\A(?:Print|Concat)\z/ } $b->value_readers($u);   # static type
        next if $o =~ /\A(?:Print|Concat)\z/;
        return -1;
    }
    return $k;
}

# _bit_source_numified($leaf) -> true where what $leaf holds is an %ENV value
# or an @ARGV element (itself, or through a `//`'s left side) that the
# program may read as a number elsewhere: perl's numeric read numifies the
# element itself, and a `//` copies it with its number. B::SoN makes one node
# of each `$ENV{K}`; an @ARGV element read counts for each it may be (the
# same index, or one not a constant).
sub _bit_source_numified {
    my ($b, $leaf) = @_;
    my (@src, %chain);
    my @todo = ($leaf);
    while (defined( my $n = shift @todo )) {
        next unless blessed($n);
        $chain{ refaddr($n) } = 1;
        if ( $n->operation eq 'DefinedOr' ) { push @todo, $n->inputs->[0]; next }
        push @src, $n if $n->operation eq 'EnvRead' || _argv_element($n);
    }
    return 0 unless @src;
    my @all = _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} );
    my @same = map {
        my $s = $_;
        $s->operation eq 'EnvRead' ? grep { $_->operation eq 'EnvRead' && $_->key eq $s->key } @all
                                   : grep { _argv_element($_) && _argv_may_be( $_, $s ) } @all
    } @src;
    # (what reads it as no number: a test of definedness, a print, a `.`, a
    # `//` whose value is read so too; the bitwise ops of $leaf itself)
    my %seen;
    my $numifies;
    $numifies = sub ($n) {
        return 0 if $seen{ refaddr($n) }++;
        for my $u ($b->value_readers($n)) {
            my $o = $u->operation;
            next if $o =~ /\A(?:Defined|Print|Concat)\z/;
            next if $o eq 'Coerce' && ( $u->stamp // '' ) eq 'Str' && !grep { $_->operation !~ /\A(?:Print|Concat)\z/ } $b->value_readers($u);   # static type
            next if refaddr($n) == refaddr($leaf) && ( $o =~ $BIT || $o eq 'Coerce' && ( $u->stamp // '' ) =~ /\A(?:Int|Num)\z/ && !grep { $_->operation !~ $BIT } $b->value_readers($u) );   # static type
            if ( $o eq 'DefinedOr' && blessed( $u->inputs->[0] ) && refaddr( $u->inputs->[0] ) == refaddr($n) ) { return 1 if $numifies->($u); next }
            return 1;
        }
        return 0;
    };
    return scalar grep { $numifies->($_) } @same;
}

# _argv_element($n) -> an element of @ARGV read by index.
sub _argv_element {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'Subscript' && blessed( $n->inputs->[0] ) && $n->inputs->[0]->is_argv;
}

# _argv_may_be($x, $y) -> @ARGV elements $x and $y may be one: their indices
# are not two different constants.
sub _argv_may_be {
    my ($x, $y) = @_;
    my @i = map { my $i = $_->inputs->[1]; blessed($i) && $i->operation eq 'Constant' && defined $i->value && $i->value =~ /\A-?\d+\z/ ? $i->value : undef } $x, $y;
    return !( defined $i[0] && defined $i[1] && $i[0] != $i[1] );
}

# _bit_ops_of($leaf) -> the bitwise ops (a shift too) reading $leaf, directly
# or through B::SoN's numeric Coerce.
sub _bit_ops_of {
    my ($b, $n) = @_;
    return map {
        $_->operation =~ $BIT ? ($_) : $b->_bit_ops_of($_)
    } grep { $_->operation =~ $BIT || $_->operation eq 'Coerce' && ( $_->stamp // '' ) =~ /\A(?:Int|Num)\z/ } $b->value_readers($n);   # static type
}

# value_readers($n) -> the nodes of the program that take $n's value (not as
# their memory), found by their inputs: a consumer list may miss a reader
# (a Coerce Analysis remade lists none -- `$ARGV[2] // 6` read by a bitwise
# op had no reader).
sub value_readers {
    my ($b, $n) = @_;
    my $ix = $b->{value_readers} //= do {
        my (%ix, %seen);
        for my $u (grep { blessed($_) && !$seen{ refaddr($_) }++ } _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} )) {
            my $m = $u->can('memory_operand') ? $u->memory_operand : undef;
            my %k;
            $k{ refaddr($_) }++ for grep { blessed($_) } $u->inputs->@*;
            $k{ refaddr($m) }-- if blessed($m);
            push $ix{$_}->@*, $u for grep { $k{$_} > 0 } keys %k;
        }
        \%ix;
    };
    return ( $ix->{ refaddr($n) } // [] )->@*;
}

# format_write($Call, $ty, $picture, @values) -> a format's formline, in the
# sub `write` calls (B::SoN's __FORMAT__:main::STDOUT): its lines made and
# printed -- what write does with what formline accumulates. Each line its
# text and its @<<< / @>>> fields (one value each), its trailing spaces
# chopped, as formline's are. Another field kind, another handle, or a
# formline elsewhere is not T2's.
sub format_write {
    my ($b, $v, $ty, $pic, @vals) = @_;
    out('a formline outside a format of STDOUT') unless ( $b->{format_of} // '' ) =~ /\A(?:main::)?STDOUT\z/;
    out('a format written in a program that selects a handle') if $b->selects;
    out('a formline of a picture made at run time') unless blessed($pic) && $pic->operation eq 'Constant' && defined $pic->value;
    out('a formline of a list') if grep { _is_list($_) } @vals;
    my @out;
    for my $line ( split /(?<=\n)/, $pic->value ) {
        my $nl = $line =~ s/\n\z// ? "\n" : '';
        my @parts;
        pos($line) = 0;
        while ( pos($line) < length $line ) {
            if ( $line =~ /\G([^\@^~]+)/gc ) { push @parts, $b->const_str($1); next }
            $line =~ /\G\@(<*|>*)(?![<>|#*])/gc or out('a format field T2 does not have (' . substr( $line, pos($line), 6 ) . ')');
            my $f = $1;
            out('a format with more fields than values') unless @vals;
            push @parts, $b->emit(op => 'FormField', type => '%Str', inputs => [ $b->as( $b->value( shift @vals ), '%Slot' ),
                $b->emit(op => 'Const', type => 'i64', attr => { value => 1 + length $f }) ], attr => { right => ( $f =~ /\A>/ ? 1 : 0 ) });
        }
        my $l = @parts ? shift @parts : $b->const_str('');
        $l = $b->emit(op => 'Concat', type => '%Str', inputs => [ $l, $_ ]) for @parts;
        $l = $b->emit(op => 'RTrim', type => '%Str', inputs => [$l]) if $nl;
        push @out, $l, ( length $nl ? $b->const_str($nl) : () );
    }
    $b->emit(op => 'Print', type => 'void', inputs => [$_], attr => { fd => 1 }) for @out;
    return $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), $ty );
}

# print_to_handle($Print) -> it prints to an in-memory handle (a `my $fh`,
# or with none in a program that selects one): its value 1 or undef.
sub print_to_handle {
    my ($b, $p) = @_;
    return 1 if !( $p->can('has_filehandle') && $p->has_filehandle ) && $b->selects;
    return 0 unless $p->can('has_filehandle') && $p->has_filehandle;
    my $fh = $p->inputs->[0];
    return blessed($fh) && $fh->operation eq 'PadAccess' ? 1 : 0;
}

# past_ascii -> a string constant of the program goes past ASCII (T2's
# strings are bytes; perl's past ASCII are characters).
sub past_ascii {
    my ($b) = @_;
    return $b->{past_ascii} //= scalar grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'string' && ( $_->value // '' ) =~ /[^\x00-\x7f]/ }
        _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
}

# sprintf_value($Call, $ty, $format, @args) -> sprintf of a constant format:
# its literal text kept, each conversion one snprintf (t2_fmt) of its
# argument -- a * width or precision the next argument, as perl's.
sub sprintf_value {
    my ($b, $v, $ty, $f, @args) = @_;
    out('a sprintf of no format') unless blessed($f);
    out('a sprintf of a format made at run time') unless $f->operation eq 'Constant' && defined $f->value;
    out('a sprintf of a list') if grep { _is_list($_) } @args;
    my $fmt = $f->value;
    my @parts;
    my $next = sub { @args ? $b->as( $b->value( shift @args ), '%Slot' ) : $b->emit(op => 'Undef', type => '%Slot') };
    pos($fmt) = 0;
    while (pos($fmt) < length $fmt) {
        if ($fmt =~ /\G([^%]+)/gc) { push @parts, $b->const_str($1); next }
        if ($fmt =~ /\G%%/gc) { push @parts, $b->const_str('%'); next }
        $fmt =~ /\G%([-+ 0#]*)(\*|\d*)(?:\.(\*|\d*))?([a-zA-Z])/gc
            or out('a sprintf conversion T2 does not read (' . substr($fmt, pos($fmt), 6) . ')');
        my ($flags, $w, $p, $c) = ($1, $2, $3, $4);
        my %kind = (d => 0, i => 0, u => 0, x => 0, X => 0, o => 0, e => 1, E => 1, f => 1, F => 1, g => 1, G => 1, s => 2, c => 3);
        out("a sprintf %$c") unless exists $kind{$c};
        my $wn = $w eq '*' ? $b->as( $next->(), 'i64' ) : $b->emit(op => 'Const', type => 'i64', attr => { value => length $w ? $w : 0 });
        my $pn = !defined $p ? $b->emit(op => 'Const', type => 'i64', attr => { value => -1 })
               : $p eq '*'   ? $b->as( $next->(), 'i64' )
               :               $b->emit(op => 'Const', type => 'i64', attr => { value => length $p ? $p : 0 });
        out('a sprintf %c of a precision') if $c eq 'c' && defined $p;
        # (perl's integers are 64 bits: C's with `l`; %i is %d)
        my $conv = $kind{$c} == 0 ? 'l' . ( $c eq 'i' ? 'd' : $c ) : $c;
        my $spec = '%' . $flags . '*' . ( $c eq 'c' ? '' : '.*' ) . $conv;
        push @parts, $b->emit(op => 'Fmt', type => '%Str', inputs => [ $b->const_str($spec),
            $b->emit(op => 'Const', type => 'i64', attr => { value => $kind{$c} }), $wn, $pn, $next->() ]);
    }
    my $r = @parts ? shift @parts : $b->const_str('');
    $r = $b->emit(op => 'Concat', type => '%Str', inputs => [ $r, $_ ]) for @parts;
    return $b->as( $r, $ty );
}

# truth($node) -> an i1: perl's truth of a value of any slice type.
sub truth {
    my ($b, $n) = @_;
    return $n if $n->type eq 'i1';
    $n = $b->as($n, 'i64') if $n->type eq '%Array*';
    return $b->emit(op => 'Truth', type => 'i1', inputs => [$n]);
}

# as($node, $type) -> the node converted to that type (itself if it is one).
sub as {
    my ($b, $n, $ty) = @_;
    return $n if $n->type eq $ty;
    # AN ARRAY AS A SCALAR is its count (`if (@a)`, `@a + 3`). A list that is
    # no array -- a slice, a range, an unpack, a choice of lists -- is not:
    # perl's scalar of it is its last value, a flip-flop, its first, the
    # arm's own. Refused (a node's consumers need not list every use, so
    # list_only cannot be all of the guard).
    out('a list taken as a scalar (' . $n->op . ')')
        if $n->type eq '%Array*' && ( $n->op =~ /\A(?:ASlice|HSlice|ARange|UnpackC|Glob)\z/ || $n->op eq 'Phi' && $n->attr->{list_choice} );
    $n = $b->emit(op => 'ALen', type => 'i64', inputs => [$n]) if $n->type eq '%Array*';
    return $n if $n->type eq $ty;
    out("a conversion " . $n->type . " -> $ty") unless exists $Chalk::Target::LLVM::Printer::CONVERT{ $n->type . '>' . $ty };
    return $b->emit(op => 'Convert', type => $ty, inputs => [$n], attr => { from => $n->type });
}

1;
