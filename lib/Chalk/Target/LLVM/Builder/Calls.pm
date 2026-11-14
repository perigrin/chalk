# ABOUTME: The LLVM builder's calls: subs as functions,  and its assignments, method calls
# ABOUTME: through the run-time MOP, constructors, code values (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

use Scalar::Util qw(blessed refaddr);

our $FRAMES;   # the program reads caller: every call of a sub says where it is
sub emit_call {
    my ($b, %a) = @_;
    # THE CALL'S SITE, for caller in the callee: pushed before, popped after
    # (before a dying call unwinds, so the stack stays the calls still open).
    my $site = delete $a{site};
    if ($FRAMES && $site) {
        out('a call caller would read with no site from B::SoN') unless $site->can('line') && defined $site->line;
        $b->emit(op => 'FramePush', type => 'void', inputs => [
            $b->const_str( $site->site_package // 'main' ), $b->const_str( $site->file // '' ),
            $b->emit(op => 'Const', type => 'i64', attr => { value => $site->line }) ]);
    }
    my $r = $b->emit(%a);
    $b->emit(op => 'FramePop', type => 'void') if $FRAMES && $site;
    $b->after_call;
    return $r;
}

# after_call(): a call that may come back dying (a die in it, an eval open up
# the calls): to the open eval's catch, else on up (this function returns).
sub after_call {
    my ($b) = @_;
    return unless $b->{has_eval};
    my $f = ( $b->{evals} // [] )->[-1];
    return unless $f || $b->{in_func};
    my $d = $b->emit(op => 'IsDying', type => 'i1');
    my $here = $b->{cur};
    my $go = $f ? $b->eval_catch($f) : do {
        my $up = $b->new_block('unwind');
        $up->{term} = [ 'retval', $b->emit(op => 'Undef', type => '%Slot') ];
        $up;
    };
    my $cont = $b->new_block('cont');
    $here->{term} = [ 'condbr', $d, $go, $cont ];
    $b->{cur} = $cont;
}

# isa_write($EntryWrite) -> true when it is `our @ISA = (LIST)` (any
# package's), its parents now the list's values, in order.
sub isa_write {
    my ($b, $s) = @_;
    my ($to, $from) = $s->inputs->@*;
    return 0 unless $to isa Chalk::IR::Node && $to->is_isa_array;
    my $pkg = $to->package;
    out('an @ISA of no known package') unless defined $pkg && length $pkg;
    out('an @ISA written from what is not a list of names') unless blessed($from) && $from->operation eq 'ArrayLiteral';
    out('an @ISA of a list') if grep { _is_list($_) } $from->inputs->@*; # static type
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($_), '%Slot') ]) for $from->inputs->@*;
    $b->emit(op => 'MopIsaSet', type => 'void', inputs => [ $b->const_str($pkg), $arr ]);
    return 1;
}

# args_elem($Assign, $read) -> @_'s element a `my (...) = @_` target is.
sub args_elem {
    my ($b, $s, $r) = @_;
    my @t = $s->inputs->@[ 0 .. $s->inputs->$#* - 1 ];
    # (the last may be slurpy: the arguments from its position on)
    out('a `my (...) = @_` of what is not a scalar') if grep { !blessed($_) || $_->operation ne 'PadAccess' || ( $_->sigil // '' ) ne '$' } @t[ 0 .. $#t - 1 ];
    out('a `my (...) = @_` of what is not a variable') unless blessed($t[-1]) && $t[-1]->operation eq 'PadAccess';
    my ($i) = grep { $t[$_]->symbol eq $r->symbol && ( $t[$_]->sigil // '' ) eq ( $r->sigil // '' ) } 0 .. $#t;
    out('a read after `my (...) = @_` of no target') unless defined $i;
    my $sg = $t[$i]->sigil // '$';
    return $b->args_rest($b->{argsarr}, $i, $sg) if $sg ne '$';
    my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $i });
    return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $b->{argsarr}, $ix ]);
}

# args_rest($argsarr, $k, $sigil) -> the arguments from position k on: a fresh
# array, or (sigil %) a fresh hash of those pairs -- a slurpy target's copy.
sub args_rest {
    my ($b, $arr, $k, $sg) = @_;
    my $rest = $b->emit(op => 'ArgsFrom', type => '%Array*', inputs => [ $arr, $b->emit(op => 'Const', type => 'i64', attr => { value => $k }) ]);
    return $rest if $sg eq '@';
    out("a slurpy $sg") unless $sg eq '%';
    my $h = $b->emit(op => 'HNew', type => '%Slot');
    $b->emit(op => 'HFromArray', type => 'void', inputs => [ $h, $rest ]);
    return $h;
}

# list_args_assign($Assign): `my (...) = @_` on the chain in the list
# convention: each target, and each read of one after it, is @_'s element
# now -- made here, before a shift after it.
sub list_args_assign {
    my ($b, $s) = @_;
    for my $r ( $s->inputs->@[ 0 .. $s->inputs->$#* - 1 ], grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@* ) {
        $b->{memo}{ refaddr($r) } //= $b->args_elem($s, $r);
    }
    for my $t (grep { blessed($_) && $_->operation eq 'PadAccess' && $_->is_location } $s->inputs->@[ 0 .. $s->inputs->$#* - 1 ]) {
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->{memo}{ refaddr($t) }, $b->location($t) ]);   # (see args_assign)
    }
}

# args_assign($Assign): `my ($x, $y) = @_` on the chain. Each target is an
# argument; a read of one made after it (its input this Assign) is too. A
# target or read not an argument is not T2's (it would read undef).
sub args_assign {
    my ($b, $s) = @_;
    my @t = $s->inputs->@[ 0 .. $s->inputs->$#* - 1 ];
    out('a `my (...) = @_` of what is not a scalar') if grep { !blessed($_) || $_->operation ne 'PadAccess' || ( $_->sigil // '' ) ne '$' } @t;
    my %arg_of;
    for my $t (@t) {
        my $a = $b->{args}{ refaddr($t) } // out('a `my (...) = @_` target that is not an argument');
        $arg_of{ $t->symbol } = $a;
        $b->{lvals}{ $t->symbol } = $a;
        $b->{args_vals}{ refaddr($a) } = 1;
        # A TARGET KEPT IN MEMORY (a closure captures it): the argument stored
        # there too -- read through its cell, it was undef ("0 0" for "10 50").
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->as($a, '%Slot'), $b->location($t) ]) if $t->is_location;
    }
    for my $r (grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@*) {
        next if $b->{args}{ refaddr($r) };
        next if $r->is_assign_target;   # the next list assign's target, versioned by this one
        out('a read after `my (...) = @_` of no target') unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*;
        $b->{args}{ refaddr($r) } = $arg_of{ $r->symbol } // out('a read after `my (...) = @_` of no target');
    }
}

# call($Call) -> the %Slot a direct call of a sub returns: its function, made
# once, called with each argument boxed (one not passed is undef).
sub call {
    my ($b, $c) = @_;
    # A DIRECT CALL OF A CLOSURE (`$f->()` B::SoN resolved): through the code
    # value its AnonSub makes in this function -- its cells are there.
    if (( $c->name // '' ) =~ /__ANON__/) {
        my @anon = grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } +($b->{own_nodes} // [])->@*;
        out('a direct call of a closure made elsewhere') unless @anon == 1;
        my @args = $c->inputs->@*;
        pop @args if $c->can('memory_input') && $c->memory_input;
        return $b->code_call($c, $b->value( $anon[0] ), @args);
    }
    my $sub = $c->target;
    out( $c->name . ' is XS: there is no Perl source to compile' ) if $c->can('xs') && $c->xs;
    out('a direct call with no sub') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func($sub, $c->name);
    my @args = $c->inputs->@*;
    pop @args if $c->can('memory_input') && $c->memory_input;
    # `&f;` IS CALLED WITH THE CALLER'S OWN @_ (the same array: a shift there
    # is seen here): both must take @_ as an array.
    if ($c->can('shares_args') && $c->shares_args) {
        out('an & call sharing @_ of a sub not taking it as a list') unless $fn->{list} && $b->{argsarr};
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $b->{argsarr} ], attr => { fn => $fn->{name} }, site => $c);
    }
    # A SIGNATURE WITH A SLURPY TAIL dies with too few arguments, or an odd
    # count into a slurpy hash (perl's "Too few arguments", "Odd name/value"):
    # refused by name where the call's count is known, as it was before.
    if (defined $fn->{minargs} && !grep { _is_list($_) } @args) {
        out('a call of a signature with too few arguments (perl dies)') if @args < $fn->{minargs};
        out('an odd count into a signature\'s slurpy hash (perl dies)') if ( $fn->{slurpy_sigil} // '' ) eq '%' && ( @args - $fn->{minargs} ) % 2;
    }
    if ($fn->{list}) {
        # @_ BUILT HERE: each scalar pushed, an array's elements appended.
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $a (@args) {
            if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
        }
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [$arr], attr => { fn => $fn->{name} }, site => $c);
    }
    out('a call of a sub with a signature of another arity (perl dies)')
        if $fn->{signature} && @args != $fn->{nargs};
    my @pass = map { $b->scalar_arg($_) } @args;
    $b->hash_reads_settled('a call');   # the sub may store into a hash
    push @pass, $b->emit(op => 'Undef', type => '%Slot') while @pass < $fn->{nargs};
    splice @pass, $fn->{nargs};
    $b->set_want($c) if $fn->{listret};
    return $b->emit_call(op => 'Call', type => '%Slot', inputs => \@pass, attr => { fn => $fn->{name} }, site => $c);
}

# THE RUN-TIME MOP: perl's classes as data the program holds. Each package is
# a stash (a hash) in @t2_stashes: its subs a method call can find, by name,
# each a code slot (tag 7) holding its wrapper `%Slot (%Array* @_)`; "@ISA" an
# array slot (tag 6) of its parents' names. A method call looks the method up
# from the invocant's class, depth first through @ISA, as perl does.
sub make_mop {
    my ($b) = @_;
    my $mop = $b->{mop} // out('a method call with no MOP');
    my %cls = map { ( $_->name => $_ ) } $mop->classes;
    my @classes = @cls{ sort keys %cls };   # by name (a sort block's $b is the builder here)
    # A CLASS OF THE CLASS FEATURE: its methods go in its stash as subs do;
    # its `new` is made where it is called (method_call). ADJUST is not T2's yet.
    # (ADJUST blocks run in the `new` made where it is called)
    my %called = map { ( $_->name =~ s/\A.*:://r => 1 ) }
        grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'method' } _all_nodes($mop, $b->{ret});
    # A TIE'S METHODS are the runtime's to call, by these names.
    $called{$_} = 1 for grep { my $t = $_; grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'tie' } _all_nodes($mop, $b->{ret}) } qw(TIEARRAY TIEHASH FETCH STORE FETCHSIZE PUSH POP SHIFT UNSHIFT EXISTS DELETE CLEAR EXTEND STORESIZE FIRSTKEY NEXTKEY);
    # A NAME NO PACKAGE DEFINES is UNIVERSAL's (isa, can, DOES, VERSION), else
    # perl's die ("Can't locate object method"), unless an AUTOLOAD answers.
    my %defined = map { ( $_->name => 1 ) } map { ( $_->subs, $_->methods ) } @classes;
    $defined{new} = 1 if grep { _is_feature_class($_) } @classes;   # made where it is called
    out("a method no package defines ($_)") for grep { !$defined{$_} && $defined{AUTOLOAD} } sort keys %called;
    out('an AUTOLOAD') if $defined{AUTOLOAD};
    # UNIVERSAL, at the root of every lookup, first: a package of that name here would be wiped.
    out('a UNIVERSAL package of the program\'s own') if $cls{UNIVERSAL};
    $b->emit(op => 'MopUniversal', type => 'void');
    for my $cls (@classes) {
        my $cs = $b->const_str($cls->name);
        $b->emit(op => 'MopClass', type => 'void', inputs => [$cs]);
        $b->emit(op => 'MopIsa', type => 'void', inputs => [ $cs, $b->const_str($cls->parent_name) ])
            if defined $cls->parent_name && length $cls->parent_name;
        my %sub = map { ( $_->name => $_ ) } grep { ( $called{can} || $called{ $_->name } ) && $_->graph } ( $cls->subs, $cls->methods );
        for my $sub (@sub{ sort keys %sub }) {
            my $fn = $b->func($sub, $cls->name . '::' . $sub->name);
            $b->emit(op => 'MopDef', type => 'void', inputs => [ $cs, $b->const_str($sub->name) ], attr => { fn => $fn->{name} });
        }
        # AN UNLOADED SUB (a module's, never reached) is in its stash by name,
        # for can(): its code is never run, unless a code value can() handed
        # back is called -- refused where one may be.
        my @unloaded = $called{can} ? grep { !$sub{$_} } $cls->unloaded : ();
        out('a code value called where can() may hand back a sub not loaded')
            if @unloaded && grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'indirect' } _all_nodes($mop, $b->{ret});
        $b->emit(op => 'MopDef', type => 'void', inputs => [ $cs, $b->const_str($_) ], attr => { fn => '@t2_unloaded' }) for @unloaded;
    }
    # EACH PACKAGE'S $VERSION, by its name, for UNIVERSAL::VERSION (after the
    # classes: making a class's stash empties it).
    if ($called{VERSION}) {
        my %pkg = map { ( ( $_->package // 'main' ) => $_ ) }
            grep { $_->operation eq 'EntryDef' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq 'VERSION' && $_->can('package') }
            _all_nodes($mop, $b->{ret});
        $b->emit(op => 'MopVar', type => 'void', inputs => [ $b->const_str($_) ], attr => { global => $b->global_of( $pkg{$_} ) }) for sort keys %pkg;
    }
}

sub _is_feature_class {
    my ($cls) = @_;
    return scalar( $cls->fields ) || scalar( $cls->methods ) || ( $cls->can('is_class') && $cls->is_class );
}

# construct($Call, $cls) -> a new object of a class of the class feature:
# blessed, each field (in order) given its named argument, else its default,
# else undef -- an array field an empty array. A name it has no field for, or
# a required one missing, is perl's death: refused (T2 has no die yet).
sub construct {
    my ($b, $c, $leaf) = @_;
    # ITS CLASSES, the root first (:isa): each class's fields, then its
    # ADJUST blocks, in that order, as perl initializes them.
    my @chain;
    for (my $k = $leaf; $k; $k = defined $k->parent_name && length $k->parent_name ? $b->{mop}->for_class( $k->parent_name ) // out('an :isa of a class not here') : undef) {
        out('an :isa of a package not of the class feature') unless _is_feature_class($k);
        out('an :isa cycle') if @chain > 64;
        unshift @chain, $k;
    }
    my @in = $c->inputs->@*;
    pop @in if $c->can('memory_input') && $c->memory_input;
    my @names = +($c->can('param_names') ? $c->param_names // [] : [])->@*;
    out('a new whose arguments are not name => value') if @names != @in || grep { _is_list($_) } @in;
    my %arg = map { ( $names[$_] => $in[$_] ) } 0 .. $#in;
    my %param = map { ( $_->param_name => 1 ) } grep { defined $_->param_name } map { $_->fields } @chain;
    out("a new with a parameter its class has not ($_)") for grep { !$param{$_} } @names;
    my $obj = $b->emit(op => 'HNew', type => '%Slot');
    $obj = $b->emit(op => 'Bless', type => '%Slot', inputs => [ $obj, $b->const_str( $leaf->name ) ]);
    for my $cls (@chain) {
        my @byix;   # in field order (no sort block: its $b is the builder here)
        $byix[ $_->fieldix ] = $_ for $cls->fields;
        for my $f (grep { defined } @byix) {
            my $key = $b->const_str( $cls->name . '::' . $f->name );
            if ($f->sigil eq '@') {
                out('an array field with a default') if $f->has_default;
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->emit(op => 'NewArray', type => '%Array*') ]) ]);
                next;
            }
            if ($f->sigil eq '%') {
                out('a hash field with a default') if $f->has_default;
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $b->emit(op => 'HNew', type => '%Slot') ]);
                next;
            }
            out('a ' . $f->sigil . ' field') unless $f->sigil eq '$';
            my $v;
            if (defined $f->param_name && exists $arg{ $f->param_name }) { $v = $b->as($b->value( $arg{ $f->param_name } ), '%Slot') }
            elsif ($f->has_default) {
                my $d = $f->default_value;
                out('a field default that is not a constant') unless blessed($d) && $d->operation eq 'Constant';
                $v = $b->as($b->value($d), '%Slot');
            }
            elsif (defined $f->param_name) { out('a new missing a required parameter (perl dies)') }
            else { $v = $b->emit(op => 'Undef', type => '%Slot') }
            $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $v ]);
        }
        my $i = 0;
        for my $adj ($cls->adjust_blocks) {
            out('an ADJUST of no graph') unless $adj->can('graph') && $adj->graph;
            my $fn = $b->func($adj, $cls->name . '::ADJUST_' . $i++);
            $b->hash_reads_settled('an ADJUST');
            $b->emit_call(op => 'Call', type => '%Slot', inputs => [$obj], attr => { fn => $fn->{name} });
        }
    }
    return $obj;
}

# method_call($Call) -> a method call: @_ built (the invocant first), the
# method looked up from the invocant's class at run time, its wrapper called.
sub method_call {
    my ($b, $c) = @_;
    if (( $c->name // '' ) eq 'new' && $b->{mop}) {
        # B::SoN's new of a class of the class feature names its class
        # (class_name), its inputs the named arguments' values.
        my $cn = $c->can('class_name') ? $c->class_name : undef;
        my $cls = defined $cn ? $b->{mop}->for_class($cn) : undef;
        return $b->construct($c, $cls) if $cls && _is_feature_class($cls);
        out('a new of a class not named here') if !$cls && grep { _is_feature_class($_) } $b->{mop}->classes;
    }
    my @args = $c->inputs->@*;
    pop @args if $c->can('memory_input') && $c->memory_input;
    out('a method call with no invocant') unless @args && blessed($args[0]);
    out('a method call on a list') if _is_list($args[0]);
    # @_, each argument pushed, a list's elements appended.
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    my $inv = $b->as($b->value($args[0]), '%Slot');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $inv ]);
    for my $a (@args[ 1 .. $#args ]) {
        if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
    }
    $b->hash_reads_settled('a method call');
    $b->set_want($c);   # whichever sub it finds may return a list
    # (where perl dies -- no class, no method -- a die, an eval's to catch)
    my $at = ' at ' . ( $c->can('file') ? $c->file // '-' : '-' ) . ' line ' . ( $c->can('line') ? $c->line // 0 : 0 ) . ".\n";
    # A QUALIFIED NAME starts its lookup at its package (mode 1); Pkg::SUPER::m
    # at the @ISA of Pkg, the package the call is in (mode 2).
    my ($start, $mode, $m) = ( '', 0, $c->name );
    if ($m =~ /\A(.+)::SUPER::(\w+)\z/) { ( $start, $mode, $m ) = ( $1, 2, $2 ) }
    elsif ($m =~ /\A(.+)::(\w+)\z/)     { ( $start, $mode, $m ) = ( $1, 1, $2 ) }
    out('a method name T2 cannot split') if $m =~ /::|'/;
    my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => $mode },
        inputs => [ $inv, $b->const_str($m), $b->const_str($at), $b->const_str($start) ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ], site => $c);
}

# scalar_arg($n) -> a positional argument's %Slot. A call in list context
# (an argument is one) of a sub returning one value is that value; one that
# may return a list (a method, a list return) must give one element -- a
# stop at run time if it gives another number (perl passes them all). A
# list (an array) is refused: positional subs take scalars.
sub scalar_arg {
    my ($b, $n) = @_;
    return $b->as($b->value($n), '%Slot') unless _is_list($n);
    out('a call passing a list') unless $n->operation eq 'Call';
    if (( $n->dispatch_kind // '' ) eq 'direct' && ( $n->name // '' ) !~ /__ANON__/) {
        my $r = $b->value($n);
        my $t = $n->target;
        my $fn = blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        out('a list from a call of no sub T2 made') unless $fn;
        return $r unless $fn->{listret};
        out('a list a call returns passed to a sub taking scalars');
    }
    return $b->value($n) if $b->_constructs($n);   # a class's new: its object
    return $b->emit(op => 'OneOf', type => '%Slot', inputs => [ $b->array_of($n) ]);
}

# _constructs($Call) -> true for a class's `new` made where it is called.
sub _constructs {
    my ($b, $c) = @_;
    return 0 unless ( $c->name // '' ) eq 'new' && $b->{mop};
    my $cn = $c->can('class_name') ? $c->class_name : undef;
    my $cls = defined $cn ? $b->{mop}->for_class($cn) : undef;
    return $cls && _is_feature_class($cls) ? 1 : 0;
}

# as_list($n) -> an %Array* of $n in list context: a list's own, or one of
# the one value.
sub as_list {
    my ($b, $n) = @_;
    return $b->array_of($n) if blessed($n) && ( _is_list($n) || $b->type_of($n) eq '%Array*' );
    my $a = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($n), '%Slot') ]);
    return $a;
}

# set_want($Call): the caller's context, for a sub returning a list.
sub set_want {
    my ($b, $c) = @_;
    if ($b->{tail} && $b->{tail}{call} == refaddr($c)) {   # handed on from this sub's caller
        return $b->emit(op => 'SetWant', type => 'void', inputs => [ $b->{tail}{want} ]);
    }
    my $w = $b->emit(op => 'Const', type => 'i1', attr => { value => _list_use($c) });
    $b->emit(op => 'SetWant', type => 'void', inputs => [$w]);
}

# code_value($AnonSub) -> a code value (%Slot tag 8): its function's wrapper
# and the cells it captured, in its CellParam order.
sub code_value {
    my ($b, $a) = @_;
    # (an AnonSub of the program may hold no sub; a direct call of it names one)
    my ($called) = grep { $_->operation eq 'Call' && ( $_->name // '' ) eq ( $a->name // '' ) && blessed( $_->can('target') ? $_->target : undef ) }
        +($b->{own_nodes} // [])->@*;
    my $sub = $a->sub // ( $called ? $called->target : undef );
    out('a closure of no sub') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func($sub, $a->name // 'anon', closure => 1);
    my @cells = map { $b->value($_) } grep { blessed($_) } $a->inputs->@*;
    out('a closure capturing what is not a cell') if grep { $_->type ne '%Slot*' } @cells;
    my $n = $b->emit(op => 'Const', type => 'i64', attr => { value => scalar @cells });
    my $env = $b->emit(op => 'EnvNew', type => '%Slot**', inputs => [$n]);
    for my $i (0 .. $#cells) {
        my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $i });
        $b->emit(op => 'EnvSet', type => 'void', inputs => [ $env, $ix, $cells[$i] ]);
    }
    return $b->emit(op => 'CodeNew', type => '%Slot', inputs => [$env], attr => { fn => $fn->{name} });
}

# code_call($Call, $code, @args) -> calling a code value: @_ built (lists
# flattened), its function found (a stop if it is no code), called with its
# cells, in the call's context.
sub code_call {
    my ($b, $c, $code, @args) = @_;
    # `&$code;` IS CALLED WITH THE CALLER'S OWN @_: not built here -- refused.
    out('an & call of a code value sharing @_') if $c->can('shares_args') && $c->shares_args;
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    for my $a (@args) {
        if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
    }
    $b->hash_reads_settled('a call of a code value');
    $b->set_want($c);
    return $b->emit_call(op => 'CallCode', type => '%Slot', inputs => [ $code, $arr ], site => $c);
}

# func($sub, $name) -> the T2 function a sub is: `%Slot (%Slot args...)`, its
# body built in its own blocks, made before them so a call of itself finds it.
sub func {
    my ($b, $sub, $name, %o) = @_;
    my $closure = $o{closure};
    # ONE FUNCTION PER SUB: a method's name is not its package's (two
    # classes' `hi` are two subs).
    return $b->{funcs}{ refaddr($sub) } if $b->{funcs}{ refaddr($sub) };
    my $g = $sub->graph;
    my $ret = $g->returns->[0];
    out("sub $name has no Return") unless blessed($ret) && $ret->operation eq 'Return';
    # A LIST RETURN: B::SoN's Return(list, scalar) -- the list, and what the
    # sub gives in scalar context (its last, a count, undef). The caller's
    # context (@t2_want, set before the call) picks one.
    my $valueless = $ret->can('valueless') && $ret->valueless;   # `()`, a bare return
    # `return values %h` (keys too): one input, B::SoN's, in the caller's
    # context -- the list, or its count. A list return as well.
    my $hkv = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && ( $ret->inputs->[0]->dispatch_kind // '' ) eq 'builtin' && ( $ret->inputs->[0]->name // '' ) =~ /\A(?:keys|values)\z/
        && ( $ret->inputs->[0]->can('want') ? $ret->inputs->[0]->want // '' : '' ) ne 'scalar'   # `scalar(keys %h)`: a count always
        ? $ret->inputs->[0] : undef;
    my $listret = $ret->inputs->@* == 2 || $valueless || $hkv;
    out("sub $name returns more than one reading") if $ret->inputs->@* > 2;
    # A METHOD OF THE CLASS FEATURE: $self is its first argument, its signature's
    # parameter i the i+1th (B::SoN's Parameter nodes). One reading @_, or with
    # an optional or slurpy parameter, is not T2's yet. Its arity is checked by
    # its wrapper where it declares parameters (`method m ()` is not checked).
    my %margs;
    my $is_method = blessed($sub) && ( $sub->isa('Chalk::MOP::Method') || $sub->isa('Chalk::MOP::Phaser::Adjust') );   # ADJUST: a method of no parameters
    if ($is_method) {
        my @gn = $g->component;
        out("method $name reads \@_") if grep { $_->operation eq 'ArgsSource' } @gn;
        my $np = $sub->can('params') ? scalar +($sub->params // [])->@* : 0;
        out("method $name has a parameter past its declared ones")
            if grep { $_->operation eq 'Parameter' && ( $_->index // 0 ) >= $np } @gn;
        out("method $name has a slurpy parameter")
            if grep { $_->operation eq 'Parameter' && ( $_->can('sigil') ? $_->sigil // '$' : '$' ) ne '$' } @gn
            or grep { ( ref($_) ? $_->{name} // $_->{sigil} // '' : $_ // '' ) =~ /\A[@%]/ } +($sub->can('params') ? $sub->params // [] : [])->@*;
        $margs{ refaddr($_) } = 0 for grep { $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq 'self' } @gn;
        $margs{ refaddr($_) } = $_->index + 1 for grep { $_->operation eq 'Parameter' } @gn;
        $margs{np} = $np;
    }
    my $an = bless {}, 'Chalk::Target::LLVM::Context';
    my @reads = $is_method ? () : eval { $an->_collect_positional_arg_reads($g, $name) };
    # @_ READ AS A LIST (join(@_), "@_", scalar(@_), for (@_)): the sub takes
    # @_ as one %Array its caller builds -- the list convention. A write to
    # $_[N] (the caller's variable) or a signature is not T2's.
    # A CLOSURE takes @_ as one array always (its code value's calling
    # convention), its captured cells as its environment.
    my $list = !$is_method && !$@ && ( $an->{_args_read_as_a_list} || $closure ) && !$an->{_args_written} && !$an->{_args_slurpy} && !$an->{_args_signature};
    # A SLURPY TAIL (`my ($c, @x) = @_`, `sub f ($c, @x)` -- perigrin: the same)
    # takes @_ as one array: the positional targets its elements 0..k-1, the
    # slurpy one a copy of the rest.
    my $slurpy = !$is_method && !$@ && !$closure && !$an->{_args_written} && !$an->{_args_read_as_a_list} ? $an->{_args_slurpy} : undef;
    my @positional = $slurpy ? @reads : ();
    $list = 1 if $slurpy;
    out("closure $name reads \@_ other than T2 takes it") if $closure && !$list;
    # A CAPTURE USED BUT BY A CELL READ OR WRITE: B::SoN spells `$t += 1` on
    # one as Coerce(CellParam) + 1, with no write -- lowered, $t never changed
    # (0 for 16). Refused, as Context.pm refuses it.
    out("closure $name uses a capture other than by reading or writing it (an op-assign)")
        if grep { my $p = $_; grep { blessed($_) && $_->operation !~ /\A(?:CellRead|CellWrite|MakeCell)\z/ } ( $p->consumers // [] )->@* }
           grep { $_->operation eq 'CellParam' } $g->component;
    out("sub $name captures a variable (a named sub's closure)") if !$closure
        && grep { $_->operation eq 'CellParam' } $g->component;
    # $_[N] READ ANYWHERE is the Nth argument: Context.pm's binder keeps one
    # read per index, and a position never read is a hole it refuses. A sub
    # that reads @_ only so binds every such read -- after a store, twice --
    # to its argument; an unread position is a placeholder (its argument
    # passed, unused).
    my @also;
    if (!$is_method && !$list && !$@ && @reads && !$an->{_args_written} && !$an->{_args_read_as_a_list}
            && !$an->{_args_slurpy} && !$an->{_args_signature}
            && !grep { blessed($_) && !$_->is_arg_element } @reads) {
        my %by;
        push $by{ $_->inputs->[1]->value }->@*, $_ for grep { $_->is_arg_element } $g->component;
        my $max = -1;   # (not sort: a sort block's $b is the builder here)
        $max < $_ and $max = $_ for keys %by;
        @reads = map { $by{$_} ? $by{$_}[0] : bless( {}, 'Chalk::Target::LLVM::Builder::Unread' ) } 0 .. $max;
        @also = map { my $i = $_; map { [ $_, $i ] } $by{$i}->@[ 1 .. $by{$i}->$#* ] } grep { $by{$_} } 0 .. $max;
    }
    out("sub $name reads \@_ other than by shifts, \$_[N] or a signature")
        if !$is_method && !$list && ( $@ || grep { !blessed($_) } @reads
        or $an->{_args_written} || $an->{_args_read_as_a_list} || $an->{_args_slurpy} );
    @reads = () if $list;
    # A SIGNATURE'S OPTIONAL PARAMETER has a default the body computes: not
    # T2's yet (dropped, `($a, $b = 3)` gave $b undef). Its arity is checked
    # at each call (perl dies on another).
    my $sig = $is_method ? $margs{np} > 0 : $an->{_args_signature};
    if ($sig && !$is_method) {
        my $decl = $sub->can('signature') ? $sub->signature // {} : {};
        out("sub $name has an optional signature parameter")
            if $decl->{optional} || ( $decl->{mandatory} // scalar @reads ) != ( $slurpy ? @positional : @reads );
    }
    ( my $id = $name ) =~ s/\W+/_/g;
    # Two subs one name (a method call's bare name): the second numbered.
    $id .= '_' . scalar keys $b->{funcs}->%* if grep { $_->{name} eq "\@f_$id" } values +($b->{funcs} // {})->%*;
    my $nargs = $is_method ? 1 + $margs{np} : $list ? 1 : scalar @reads;
    my $fn = $b->{funcs}{ refaddr($sub) } = { name => "\@f_$id", wrapper => "\@w_$id", nargs => $nargs,
        signature => $sig, list => $list, listret => $listret, closure => $closure, blocks => [] , minargs => ( $slurpy && $sig ? scalar @positional : undef ),
        slurpy_sigil => ( $slurpy && $sig ? ( $slurpy->can('sigil') ? $slurpy->sigil // '@' : '@' ) : undef ) };
    my @argn = map { Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Slot', attr => { index => $_ }) } 0 .. ( $is_method ? $nargs : scalar @reads ) - 1;
    $argn[$_]->set_name("%a$_") for 0 .. $#argn;
    my $argsarr = $list ? Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Array*', attr => { index => 0 }) : undef;
    $argsarr->set_name('%a0') if $argsarr;
    local $b->{argsarr} = $argsarr;
    # A READ OF `my (...) = @_` made where it is used reads @_ then: one the
    # sub shifts first would be of the shifted array.
    local $b->{args_mutated} = $list && scalar grep { $_->operation eq 'Call' && $_->mutates_array
        && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'ArgsSource' }
        $g->component;
    local $b->{blocks} = $fn->{blocks};
    local $b->{cur};
    local $b->{seq} = 0;   # (its own statements' turns: its entry is turn 0)
    local $b->{locs} = {};
    local $b->{memo} = {};
    local $b->{args} = $is_method ? { map { ( $_ => $argn[ $margs{$_} ] ) } grep { $_ ne 'np' } keys %margs }
                                  : { ( map { ( refaddr( $reads[$_] ) => $argn[$_] ) } 0 .. $#reads ), ( map { ( refaddr( $_->[0] ) => $argn[ $_->[1] ] ) } @also ) };
    local $b->{self} = $is_method ? $argn[0] : undef;   # a field's object
    local $b->{env} = $closure ? do { my $e = Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Slot**', attr => { index => 1 }); $e->set_name('%env'); $e } : undef;
    local $b->{own_nodes} = [ $g->component ];
    local $b->{eval_at} = { map { ( refaddr( $_->eval_entry ) => $_ ) } grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } $b->{own_nodes}->@* };
    local $b->{evals} = [];
    local $b->{eval_opened} = {};
    local $b->{in_func} = 1;
    local $b->{ret} = $ret;
    local $b->{passed} = [ grep { $_->operation eq 'MemStart' } $g->component ];
    local $b->{readers};
    $b->index_readers($g->component);
    local $b->{depth} = 0;
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj)\z/ ? $start->inputs->[0]
               : out("no way back to Start in $name");
    }
    $b->new_block('entry');
    # THE CALLER'S CONTEXT, read first (a call in the body sets it).
    my $want = $b->emit(op => 'GetWant', type => 'i1');
    if ($slurpy) {
        # A SIGNATURE'S ARITY: at least its positional parameters (perl dies
        # with fewer -- a run-time stop here, as a signature's wrapper's is).
        $b->emit(op => 'ArgsMin', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional }) if $sig;
        $b->emit(op => 'ArgsPairs', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional })
            if $sig && ( $slurpy->can('sigil') ? $slurpy->sigil // '' : '' ) eq '%';
        # ITS PARAMETERS, made here: each its argument, the slurpy one the rest.
        for my $p (grep { $_->operation eq 'Parameter' } $g->component) {
            my $sg = $p->can('sigil') ? $p->sigil // '$' : '$';
            $b->{memo}{ refaddr($p) } = $sg eq '$'
                ? $b->emit(op => 'AGet', type => '%Slot', inputs => [ $argsarr, $b->emit(op => 'Const', type => 'i64', attr => { value => $p->index }) ])
                : $b->args_rest($argsarr, $p->index, $sg);
        }
    }
    # `return g()` IS CALLED IN THE CALLER'S CONTEXT: it is handed on.
    my $tail = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && ( $ret->inputs->[0]->dispatch_kind // '' ) eq 'direct' ? $ret->inputs->[0] : undef;
    local $b->{tail} = $tail ? { call => refaddr($tail), want => $want } : undef;
    $b->make_constant_arrays($g->component);
    local $b->{jumps} = {};   # this function's early exits
    $b->walk($start);
    out('an early exit to a merge never reached') if $b->{jumps}->%*;
    out('an eval left open at the end') if $b->{evals}->@*;
    my $v = $ret->inputs->[0];
    # ENDED BY AN exit OR A die, NOTHING AFTER IT: the walk ends in a dead
    # block, the Return is never reached, and what B::SoN gives as the sub's
    # value is no value (BAIL_OUT's `exit 255` as its last statement).
    if ($b->{cur}{dead}) {
        $b->{cur}{term} = ['unreachable'];
        return $fn;
    }
    my $r;
    if ($hkv) {
        my $h = $b->hash_of( $hkv->inputs->[0] );
        my $l = $b->emit(op => $hkv->name eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
        my $n = $b->as($b->emit(op => 'HCount', type => 'i64', inputs => [$h]), '%Slot');
        $r = $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $b->emit(op => 'ARef', type => '%Slot', inputs => [$l]), $n ]);
    }
    elsif ($valueless) {   # no element in a list, undef in a scalar
        my $l = $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->emit(op => 'NewArray', type => '%Array*') ]);
        $r = $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $l, $b->emit(op => 'Undef', type => '%Slot') ]);
    }
    elsif ($listret) {
        # A FRESH ARRAY of it: a constant one is made once, at entry, and the
        # caller may write the list it is handed (`for (f()) { $_ = 0 }`).
        my $copy = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $copy, $b->as_list($v) ]);
        my $l = $b->emit(op => 'ARef', type => '%Slot', inputs => [$copy]);
        my $sv = blessed( $ret->inputs->[1] ) ? $b->as($b->value( $ret->inputs->[1] ), '%Slot') : $b->emit(op => 'Undef', type => '%Slot');
        $r = $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $l, $sv ]);
    }
    elsif ($tail) {
        # A TAIL CALL OF A SUB RETURNING A LIST: its result as it is (the
        # list's reference or its scalar, by the context handed on).
        my $t = $tail->target;
        my $cf = blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        out('a tail call of a sub not made yet (recursion)') unless $cf && refaddr($cf) != refaddr($fn);
        if ($cf->{listret}) { $fn->{listret} = 1; $r = $b->value($tail) }
        else { $r = $b->as($b->value($tail), '%Slot') }
    }
    else {
        out("sub $name returns a list as one value") if blessed($v) && _is_list($v);
        $r = blessed($v) ? $b->as($b->value($v), '%Slot') : $b->emit(op => 'Undef', type => '%Slot');
    }
    $b->{cur}{term} = [ 'retval', $r ];
    return $fn;
}

1;
