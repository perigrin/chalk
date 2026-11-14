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

# phi_type($Phi) -> a merge's T2 type: its stamp's, except a Str (a Num may
# reach it) or a stamp T1 could not give (a recursive sub's result) -- boxed.
sub phi_type {
    my ($b, $phi) = @_;
    my $st = $phi->stamp // ''; # static type
    # THE LIST A SUB RETURNS, merged from its returns (`return` in one arm, a
    # last value in the other): an array, each arm's value a list of it.
    return '%Array*' if grep { blessed($_) && $_->operation eq 'Return' && $_->inputs->@* == 2 && refaddr( $_->inputs->[0] ) == refaddr($phi) }
        ( $phi->consumers // [] )->@*;
    return '%Slot' if $st =~ /\A(?:Str|Unknown|None|Scalar)\z/ || $st =~ /\AMaybe\[/;   # a Maybe: T or undef
    # A LIST A LOOP BUILDS (map, grep): one array, its back edge a ListAppend
    # to it. Another array phi (`@p = ()` in a loop) is not this.
    if ($st =~ /\A(?:Array|List)\z/) {
        out("a phi stamped $st") unless grep { blessed($_) && $_->operation eq 'ListAppend' } $phi->inputs->@*;
        return '%Array*';
    }
    return $SCALAR{$st} // out("a phi stamped $st");
}

# A LOOP PHI'S TYPE: its stamp, except a Str one, which a Num may reach on a
# later pass -- boxed, as a merge of differing arms is.
sub loop_type { my ($b, $phi) = @_; return $b->phi_type($phi) }

# The T2 type a T1 value is, decided once.
sub type_of {
    my ($b, $v) = @_;
    my $op = $v->operation;
    return '%Slot' if $op eq 'EnvRead' || $op eq 'DefinedOr' || $op eq 'RegexCapture';   # may be undef (a capture: its group took no part)
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
    return $v->sigil eq '@' ? '%Array*' : '%Slot' if $v->is_package_aggregate;   # a hash is its %Slot
    return '%Slot' if $op eq 'ArrayLiteral' && ( $v->stamp // '' ) eq 'ArrayRef'; # static type
    return '%Slot' if $op eq 'Ref';
    return '%Slot' if $op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$';
    return '%Array*' if $op eq 'ArrayLiteral' || $v->is_array_deref || $v->is_my_array || $op eq 'ArgsSource' || $op eq 'ListAppend';
    return 'i64' if $op eq 'Count';
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
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'substr';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/;
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:ftdir|chdir|reftype_of_ref)\z/;
    return 'i64' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'require';
    return 'i64'   if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'index';
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        return $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar' ? 'i64' : '%Array*';
    }
    return '%Array*' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:sort|reverse)\z/
        && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/;   # static type
    return '%Slot' if $op eq 'Call' && ( $v->name // '' ) =~ /\A(?:shift|pop)\z/;
    return '%Str' if $op eq 'Call' && $v->changes_case;
    return '%Str' if $op eq 'Call' && ( $v->name // '' ) eq 'join';
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
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) =~ /\A(?:direct|method)\z/;
    # AN OBJECT is its blessed reference; ref() of one its class, or HASH.
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless' || $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'blessed';
    return '%Slot' if $op eq 'Call' && $v->is_tie_builtin;
    return '%Str' if $op eq 'RefType';
    return 'i64' if $op eq 'Print';
    # ARITHMETIC ON A %Slot is perl's: Ints stay Ints until they overflow. Done
    # as doubles (T1 may say Num), fact(20) lost its digits.
    return '%Slot' if $ARITH{$op} && grep { $b->type_of($_) eq '%Slot' } $v->inputs->@[0, 1];
    # NUMIFYING A SCALAR OR A STRING is perl's: an Int stays one, an integer
    # string is parsed whole -- through a double, 9007199254740993 lost its 3.
    return '%Slot' if $op eq 'Coerce' && ( $v->stamp // '' ) eq 'Num' # static type
        && $b->type_of($v->inputs->[0]) =~ /\A%(?:Slot|Str)\z/;
    return $b->phi_type($v) if $op eq 'Phi';
    return '%Slot' if ( $v->stamp // '' ) =~ /\A(?:Unknown|None)\z/; # static type
    if ($op eq 'And' || $op eq 'Or') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[0, 1];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    if ($op eq 'TernaryExpr') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[1, 2];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    my $st = $v->stamp // ''; # static type
    return '%Slot' if $st =~ /\AMaybe\[/;   # T or undef: a %Slot
    return $SCALAR{$st} // out("a value stamped $st ($op)");
}

# value($t1) -> the T2 node for a T1 value, built once.
sub value {
    my ($b, $v) = @_;
    out('a value an eval made, read past its end')
        if delete $b->{past_eval}{ refaddr($v) } and $v->operation ne 'Constant';
    return $b->{memo}{ refaddr($v) } //= $b->_value($v);
}

sub _value {
    my ($b, $v) = @_;
    # $& $` $' $+ @- @+ %+: of the last match that succeeded -- B::SoN gives
    # them as package variables, of no match: never read as one.
    out( 'the match variable ' . ( $v->sigil // '$' ) . $v->symbol . ' (B::SoN ties it to no match)' )
        if $v->operation eq 'EntryDef' && ( $v->symbol // '' ) =~ /\A(?:[&`'+-]|\d+)\z/;
    return $b->pkg_agg($v) if $v->is_package_aggregate;
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
    return $b->emit(op => 'Const', type => 'i64', attr => { value => 1 })
        if $v->operation eq 'Print' && $v->can('control_in') && blessed($v->control_in);
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
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'method') { return $b->method_call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'indirect') {
        my ($code, @args) = $v->inputs->@*;
        pop @args if $v->can('memory_input') && $v->memory_input;
        return $b->code_call($v, $b->as($b->value($code), '%Slot'), @args);
    }
    if ($op eq 'MakeCell') {
        # THE CELL IS THE VARIABLE'S OWN STORAGE (the maker reads and writes it
        # as the closure does). A variable a loop renews, captured in it, is a
        # new one each pass: not this (one storage per call).
        my $var = Chalk::Target::LLVM::Context::_cell_variable($v) // out('a captured variable that is not one kept in memory');
        out('a variable captured in a loop body or an arm') if $b->{depth};
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
    if ($op eq 'RefType') {
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
            _all_nodes($b->{mop}, $b->{ret});
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
            _all_nodes($b->{mop}, $b->{ret});
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
        return $b->emit(op => 'Const', type => $ty, attr => { value => $c }) if $ty ne '%Str';
        $b->{strs}{$c} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
    }
    # -d PATH: a directory (1), something else there (''), nothing (undef).
    # chdir PATH: 1, or '' where it could not. A require of a file B::SoN
    # followed is done -- its subs are compiled in (1); of any other, not T2's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:ftdir|chdir|require)\z/) {
        my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out( 'a ' . $v->name . ' of no argument' ) unless @a;
        if ( $v->name eq 'require' ) {
            my $f = $a[0];
            out('a require of a file named at run time') unless $f->operation eq 'Constant' && defined $f->value;
            ( my $mod = $f->value ) =~ s{\.pm\z}{}; $mod =~ s{/}{::}g;
            out( 'a require of ' . $f->value . ', not compiled in' )
                unless $Chalk::IR::Serialize::JSON::FOLLOWED{ $f->value } || $Chalk::IR::Serialize::JSON::FOLLOWED{$mod};
            return $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), $ty );
        }
        return $b->as( $b->emit(op => $v->name eq 'ftdir' ? 'FtDir' : 'Chdir', type => '%Slot', inputs => [ $b->as( $b->value( $a[0] ), '%Str' ) ]), $ty );
    }
    # int(X): X's number truncated toward zero. rand(X): a number in [0, X),
    # X 1 when absent or 0 (perl's), from libc's generator -- not perl's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/) {
        my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out('an int of no argument (of $_)') if $v->name eq 'int' && !@a;
        my $x = @a ? $b->as( $b->value( $a[0] ), '%Slot' ) : $b->emit(op => 'Undef', type => '%Slot');
        return $b->as( $b->emit(op => $v->name eq 'int' ? 'IntOf' : 'Rand', type => '%Slot', inputs => [$x]), $ty );
    }
    if ($op eq 'Coerce') {
        # TO Undef IS NOT A CONVERSION: undef has no value to convert into, and
        # boxing the value would keep it.
        out('a coercion to Undef') if ( $v->stamp // '' ) eq 'Undef'; # static type
        return $b->emit(op => 'Numify', type => '%Slot', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ])
            if $ty eq '%Slot' && ( $v->stamp // '' ) eq 'Num'; # static type
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
            out('a // whose left side is not a Slot') unless $lhs->type eq '%Slot';
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
    # substr($s, $off, $len) READ (not an lvalue: B::SoN pins a store): from
    # either end, the rest or a length (negative leaves that many off the end);
    # undef outside the string, as perl's. index($s, $t, $pos): -1 for none.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:substr|index)\z/) {
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
    # AN ARRAY AS A SCALAR is its count (`if (@a)`, `@a + 3`).
    $n = $b->emit(op => 'ALen', type => 'i64', inputs => [$n]) if $n->type eq '%Array*';
    return $n if $n->type eq $ty;
    out("a conversion " . $n->type . " -> $ty") unless exists $Chalk::Target::LLVM::Printer::CONVERT{ $n->type . '>' . $ty };
    return $b->emit(op => 'Convert', type => $ty, inputs => [$n], attr => { from => $n->type });
}

1;
