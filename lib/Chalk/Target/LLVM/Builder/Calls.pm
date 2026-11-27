# ABOUTME: The LLVM builder's calls: subs as functions,  and its assignments, method calls
# ABOUTME: through the run-time MOP, constructors, code values (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;


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
    my $go = $f ? $b->eval_catch($f) : $b->rethrow_way // do {
        my $up = $b->new_block('unwind');
        $up->{term} = [ 'retval', $b->emit(op => 'Undef', type => '%Slot') ];
        $up;
    };
    my $cont = $b->new_block('cont');
    $here->{term} = [ 'condbr', $d, $go, $cont ];
    $b->{cur} = $cont;
}

# rethrow_way() -> with no eval open in this function, the block the statement
# being lowered goes to when it comes back dying, where B::SoN gave it a way
# out (design B1: an Exc, the restores of the `local`s live there, an Unwind
# marked rethrow): walked now, in a block of its own, from the values made so
# far; undef where it has none (nothing live: the default unwind is right).
sub rethrow_way ($b) {
    my $s = $b->{stmt};
    my ($x) = blessed($s) ? grep { blessed($_) && $_->operation eq 'Exc' && refaddr( $_->inputs->[0] ) == refaddr($s) } ( $s->consumers // [] )->@* : ();
    return undef unless $x;
    $b->{rethrows_taken}{ refaddr($x) } = 1;
    my $here = $b->{cur};
    my $blk  = $b->new_block('rethrow');
    {
        local $b->{memo}        = { $b->{memo}->%* };
        local $b->{stood}       = { ( $b->{stood} // {} )->%* };
        local $b->{passed}      = [ ( $b->{passed} // [] )->@* ];
        local $b->{arm_settled} = { ( $b->{arm_settled} // {} )->%* };
        local $b->{stmt};
        my $at = $b->walk($x);
        out('a rethrow edge that ends in no rethrow') unless blessed($at) && $at->operation eq 'Unwind' && $at->rethrow;
    }
    $b->{cur} = $here;
    return $blk;
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
        out('a read after `my (...) = @_` of no target') unless blessed( $r->mem_in ) && refaddr( $r->mem_in ) == refaddr($s);
        $b->{args}{ refaddr($r) } = $arg_of{ $r->symbol } // out('a read after `my (...) = @_` of no target');
    }
}

# plain_anon($Call) -> true for a direct call of an anonymous sub that
# CAPTURES NOTHING, its code value folded away (B::SoN keeps no AnonSub for
# `my $f = sub { $_[0] * 3 }; $f->(14)`): a sub as a named one is, called
# directly. (A variable it captures: a CellParam, or an outer `my` aggregate
# it reads -- shared, or of no version of its own.)
sub plain_anon {
    my ($b, $c) = @_;
    return 0 unless ( $c->name // '' ) =~ /__(?:ANON|EVAL)__/;
    my $t = $c->can('target') ? $c->target : undef;
    return 0 unless blessed($t) && $t->can('graph') && $t->graph;
    # (A FILE LEXICAL it reads -- `my @a; my sub t { scalar @a }` -- is no
    # capture: one variable for the program, reached as a named sub reaches it)
    return 0 if grep { $_->operation eq 'CellParam'
        || $_->operation eq 'PadAccess' && !( $_->can('file') && $_->file ) && ( $_->shared || !defined $_->inputs->[0] && !blessed( $_->mem_in ) ) } $t->graph->component;
    return 0 if grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } +($b->{own_nodes} // [])->@*;
    out('a closure called directly and as a code value') if ( $b->{funcs}{ refaddr($t) } // {} )->{closure};
    return 1;
}

# call($Call) -> the %Slot a direct call of a sub returns: its function, made
# once, called with each argument boxed (one not passed is undef).
sub call {
    my ($b, $c) = @_;
    # A DIRECT CALL OF A CLOSURE (`$f->()` B::SoN resolved): through the code
    # value its AnonSub makes in this function -- its cells are there.
    my $plain = $b->plain_anon($c);
    if (( $c->name // '' ) =~ /__(?:ANON|EVAL)__/ && !$plain) {
        my @anon = grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } +($b->{own_nodes} // [])->@*;
        # (ITS CODE VALUE FOLDED AWAY -- `my $c = sub {...}; $c->(1)` -- the
        # AnonSub hangs off the cells it captures, after its statement)
        @anon = grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } Chalk::IR::Graph::own_nodes( $b->{ret} )
            unless @anon;
        out('a direct call of a closure made elsewhere') unless @anon == 1;
        my @args = $c->inputs->@*;
        my $code = $b->value( $anon[0] );
        # A SIGNATURE'S ARITY where the call's count is known: perl dies on
        # another -- refused by name here (its entry's check is a run-time stop).
        my $fn = $b->{funcs}{ refaddr( $c->target // 0 ) };
        if ($fn && defined $fn->{sig_min} && !grep { _is_list($_) } @args) {
            out('a call of a closure\'s signature with another arity (perl dies)')
                if @args < $fn->{sig_min} || defined $fn->{sig_max} && @args > $fn->{sig_max};
        }
        return $b->code_call($c, $code, @args);
    }
    my $sub = $c->target;
    out( $c->name . ' is XS: there is no Perl source to compile' ) if $c->can('xs') && $c->xs;
    # A SUB A GLOB IS GIVEN AT RUN TIME (and no other, here): found in its
    # package's run-time stash where it is called (glob_call).
    return $b->glob_call($c) if $b->is_glob_call($c);
    out('a direct call with no sub') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func($sub, $c->name);
    # A SUB NO PACKAGE DEFINES, ITS PACKAGE'S AUTOLOAD RUN in its place
    # (Analysis's target, the name it autoloads): perl sets that package's $AUTOLOAD to the full name
    # called, first.
    if ( defined( my $full = $c->can('autoloads') ? $c->autoloads : undef ) ) {
        my $pkg = blessed( $sub->class ) ? $sub->class->name : $sub->class // 'main';
        $b->emit(op => 'GStore', type => 'void', inputs => [ $b->as( $b->const_str($full), '%Slot' ) ], attr => { global => $b->global_named("${pkg}::AUTOLOAD") });
    }
    my @args = $c->inputs->@*;
    # A CLOSURE OF A METHOD READING ITS FIELDS is handed the object, last:
    # called from that method only (its name is the closure's prefix).
    my @self;
    if ($fn->{self_arg}) {
        my $in = $b->{func_name} // '';
        out('a closure reading its method\'s fields, called other than from that method')
            unless $b->{self} && length $in && ( $c->name // '' ) =~ /\A\Q$in\E::__ANON__/;
        @self = ( $b->{self} );
    }
    # `&f;` IS CALLED WITH THE CALLER'S OWN @_ (the same array: a shift there
    # is seen here): both must take @_ as an array.
    if ($c->can('shares_args') && $c->shares_args) {
        # (ONE THAT READS NO @_ sees none of it: called with nothing. At the
        # program's top @_ is empty: a new one.)
        if (!$fn->{list} && !$fn->{nargs} && !$fn->{signature}) {
            $b->hash_reads_settled('a call');
            $b->set_want($c) if $fn->{listret};
            return $b->emit_call(op => 'Call', type => '%Slot', inputs => [@self], attr => { fn => $fn->{name} }, site => $c);
        }
        local $b->{argsarr} = $b->{argsarr} // ( $b->{in_func} ? undef : $b->emit(op => 'NewArgs', type => '%Array*') );
        out('an & call sharing @_ of a sub not taking it as a list') unless $fn->{list} && $b->{argsarr};
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $b->{argsarr}, @self ], attr => { fn => $fn->{name} }, site => $c);
    }
    # A SIGNATURE WITH A SLURPY TAIL dies with too few arguments, or an odd
    # count into a slurpy hash (perl's "Too few arguments", "Odd name/value"):
    # refused by name where the call's count is known, as it was before.
    if (defined $fn->{maxargs}) {
        out('a call of a sub with optional parameters passing a list (its count unknown)') if grep { _is_list($_) } @args;
        out('a call of a signature with too many arguments (perl dies)') if @args > $fn->{maxargs};
    }
    if (defined $fn->{minargs} && !grep { _is_list($_) } @args) {
        out('a call of a signature with too few arguments (perl dies)') if @args < $fn->{minargs};
        out('an odd count into a signature\'s slurpy hash (perl dies)') if ( $fn->{slurpy_sigil} // '' ) eq '%' && ( @args - $fn->{minargs} ) % 2;
    }
    if ($fn->{list}) {
        # @_ BUILT HERE: the caller's arguments, aliased.
        my $arr = do { local $b->{arg_call} = $c; local $b->{alias_writes} = $b->call_writes_args($c); local $b->{alias_refs} = $b->call_refs_args($c); $b->args_array(@args) };
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $arr, @self ], attr => { fn => $fn->{name} }, site => $c);
    }
    out('a call of a sub with a signature of another arity (perl dies)')
        if $fn->{signature} && @args != $fn->{nargs};
    my @pass = map { $b->scalar_arg($_) } @args;
    $b->hash_reads_settled('a call');   # the sub may store into a hash
    push @pass, $b->emit(op => 'Undef', type => '%Slot') while @pass < $fn->{nargs};
    splice @pass, $fn->{nargs};
    push @pass, @self;
    $b->set_want($c) if $fn->{listret};
    return $b->emit_call(op => 'Call', type => '%Slot', inputs => \@pass, attr => { fn => $fn->{name} }, site => $c);
}

# A GLOB'S CODE SLOT WRITTEN AT RUN TIME (`*name = sub {...}`, `*name =
# \&other`): the sub is put in its package's run-time stash (the run-time MOP
# make_mop builds) there, where it stands -- a call by that name finds it
# from then on (glob_call), as can() and a method call do. A sub of no body
# here, a closure (its cells are not the stash's to hold), a code value in a
# variable, a sub the package also defines by name (calls of that name are
# bound to it), and a local, are refused by name.
# glob_code_writes -> { "Pkg::name" => [ its EntryWrites ] }.
sub glob_code_writes {
    my ($b) = @_;
    return $b->{glob_code_writes} //= do {
        my %w;
        for my $n ( grep { $_->operation eq 'EntryWrite' } _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} ) ) {
            my $t = $n->inputs->[0];
            next unless $t isa Chalk::IR::Node && $t->operation eq 'EntryDef' && ( $t->sigil // '' ) eq '&';
            push $w{ ( $t->package // 'main' ) . '::' . $t->symbol }->@*, $n;
        }
        \%w;
    };
}

# glob_stashes: at the start, each package whose glob a sub is stored into
# has its run-time stash (make_mop made those of the MOP's classes already).
sub glob_stashes {
    my ($b) = @_;
    my %pkg = map { /\A(.*)::[^:]+\z/ ? ( $1 => 1 ) : () } keys $b->glob_code_writes->%*;
    $b->emit(op => 'MopClass', type => 'void', inputs => [ $b->const_str($_) ]) for grep { !$b->{mop_classes}{$_} } sort keys %pkg;
}

# glob_code_write($EntryWrite): the sub put in its package's stash, here.
sub glob_code_write {
    my ($b, $s) = @_;
    my ($t, $v) = $s->inputs->@*;
    out('a local of a glob') if $s->can('local') && $s->local;
    my ( $pkg, $name ) = ( $t->package // 'main', $t->symbol );
    my $cls = $b->{mop} ? $b->{mop}->for_class($pkg) : undef;
    out("a glob given a sub where its package defines one by that name ($pkg\::$name)") if $cls && grep { $_->name eq $name } $cls->subs;
    my $sub;
    if ( blessed($v) && $v->operation eq 'AnonSub' ) {
        $sub = $v->sub;
        out('a glob given a closure (its cells are not the stash\'s to hold)')
            if blessed($sub) && $sub->graph && grep { $_->operation eq 'CellParam' } $sub->graph->component;
    }
    elsif ( blessed($v) && $v->operation eq 'Ref' && blessed( $v->inputs->[0] ) && $v->inputs->[0]->operation eq 'Constant'
            && ( $v->inputs->[0]->const_type // '' ) eq 'code' ) {
        my $q = $v->inputs->[0]->value // '';
        my ( $qp, $qs ) = $q =~ /\A(.*)::(\w+)\z/ ? ( $1, $2 ) : ( 'main', $q );
        my $qc = $b->{mop} ? $b->{mop}->for_class($qp) : undef;
        ($sub) = $qc ? grep { $_->name eq $qs && $_->graph } $qc->subs : ();
        out("a glob given a reference to a sub not here ($q)") unless $sub;
    }
    else { out('a glob given a code value held in a variable') }
    out('a glob given a sub of no body here') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func( $sub, "$pkg\::$name" );
    out('a glob given a sub T2 calls other than through its stash') if $fn->{closure} || $fn->{self_arg} || $fn->{direct_only} && !$fn->{arity};
    $b->emit(op => 'MopDef', type => 'void', inputs => [ $b->const_str($pkg), $b->const_str($name) ], attr => { fn => $fn->{name} });
}

# is_glob_call($Call) -> true for a direct call of a name no sub here is
# bound to, whose glob a sub is stored into at run time.
sub is_glob_call {
    my ($b, $c) = @_;
    return 0 unless blessed($c) && $c->operation eq 'Call' && ( $c->dispatch_kind // '' ) eq 'direct';
    my $t = $c->target;
    return 0 if blessed($t) && $t->can('graph') && $t->graph;
    return $b->glob_code_writes->{ $c->name // '' } ? 1 : 0;
}

# glob_call($Call) -> a call by name of a sub a glob is given at run time:
# @_ built (aliased), the sub found in its package's run-time stash (or
# perl's die, "Undefined subroutine"), its wrapper called in the call's context.
sub glob_call {
    my ($b, $c) = @_;
    out('an & call of a sub a glob is given at run time') if $c->can('shares_args') && $c->shares_args;
    my ( $pkg, $name ) = ( $c->name // '' ) =~ /\A(.*)::([^:]+)\z/ or out('a call of a glob\'s sub of no package');
    my @args = $c->inputs->@*;
    my $arr = do { local $b->{arg_call} = $c; local $b->{alias_writes} = $b->call_writes_args($c); local $b->{alias_refs} = $b->call_refs_args($c); $b->args_array(@args) };
    $b->hash_reads_settled('a call');
    $b->set_want($c);
    my $at = ' at ' . ( $c->can('file') ? $c->file // '-' : '-' ) . ' line ' . ( $c->can('line') ? $c->line // 0 : 0 ) . ".\n";
    my $fp = $b->emit(op => 'SubFind', type => 'i8*', inputs => [ $b->const_str($pkg), $b->const_str($name), $b->const_str($at) ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ], site => $c);
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
    # A METHOD NAMED AT RUN TIME (`$o->$m`) may be any of them.
    my $dynamic = grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'dynamic_method' } _all_nodes($mop, $b->{ret});
    out('a method named at run time in a program with an AUTOLOAD') if $dynamic && grep { $_->name eq 'AUTOLOAD' } map { ( $_->subs, $_->methods ) } $mop->classes;
    # A TIE'S METHODS are the runtime's to call, by these names.
    $called{$_} = 1 for grep { my $t = $_; grep { $_->operation eq 'Call' && ( $_->builtin_kind // '' ) eq 'binds' } _all_nodes($mop, $b->{ret}) } qw(TIESCALAR TIEARRAY TIEHASH FETCH STORE FETCHSIZE PUSH POP SHIFT UNSHIFT EXISTS DELETE CLEAR EXTEND STORESIZE FIRSTKEY NEXTKEY);
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
        $b->{mop_classes}{ $cls->name } = 1;
        $b->emit(op => 'MopIsa', type => 'void', inputs => [ $cs, $b->const_str($cls->parent_name) ])
            if defined $cls->parent_name && length $cls->parent_name;
        # (A SPECIAL CONTAINER'S METAOBJECT CLASS -- Chalk::Impl::* -- every sub:
        # its new, the container protocol, what its methods call, the runtime's.)
        my $impl = $b->special_classes->{ $cls->name };
        my %sub = map { ( $_->name => $_ ) } grep { ( $impl || $called{can} || $dynamic || $called{ $_->name } ) && $_->graph } ( $cls->subs, $cls->methods );
        for my $sub (@sub{ sort keys %sub }) {
            my $fn = $b->func($sub, $cls->name . '::' . $sub->name);
            out('a sub of a signature T2 checks at its calls, called other than directly') if $fn->{direct_only} && !$fn->{arity};
            out('a closure reading its method\'s fields, in its stash') if $fn->{self_arg};
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
    my @in = $c->inputs->@*;
    my @names = +($c->can('param_names') ? $c->param_names // [] : [])->@*;
    out('a new whose arguments are not name => value') if @names != @in || grep { _is_list($_) } @in;
    my %arg = map { ( $names[$_] => $in[$_] ) } 0 .. $#in;
    return $b->construct_with( $leaf, \@names, sub ($p) { exists $arg{$p} ? $b->as( $b->value( $arg{$p} ), '%Slot' ) : undef } );
}

# construct_with($leaf, \@names, $arg) -> a new object of $leaf made with the
# named arguments @names, each one's %Slot $arg->($name) gives where its field
# is set (a call's `new`, or chalk's start-up making a container's metaobject).
sub construct_with {
    my ($b, $leaf, $names, $argval) = @_;
    my @names = @$names;
    # ITS CLASSES, the root first (:isa): each class's fields, then its
    # ADJUST blocks, in that order, as perl initializes them.
    my @chain;
    for (my $k = $leaf; $k; $k = defined $k->parent_name && length $k->parent_name ? $b->{mop}->for_class( $k->parent_name ) // out('an :isa of a class not here') : undef) {
        out('an :isa of a package not of the class feature') unless _is_feature_class($k);
        out('an :isa cycle') if @chain > 64;
        unshift @chain, $k;
    }
    my %given = map { ( $_ => 1 ) } @names;
    my %param = map { ( $_->param_name => 1 ) } grep { defined $_->param_name } map { $_->fields } @chain;
    out("a new with a parameter its class has not ($_)") for grep { !$param{$_} } @names;
    my $obj = $b->emit(op => 'HNew', type => '%Slot');
    $obj = $b->emit(op => 'Bless', type => '%Slot', inputs => [ $obj, $b->const_str( $leaf->name ) ]);
    for my $cls (@chain) {
        my @byix;   # in field order (no sort block: its $b is the builder here)
        $byix[ $_->fieldix ] = $_ for $cls->fields;
        for my $f (grep { defined } @byix) {
            # (one B::SoN gives no graph of: made undef, perl's was its value)
            out('a field default the producer does not model') if $f->default_unmodeled;
            my $key = $b->const_str( $cls->name . '::' . $f->name );
            if ($f->sigil eq '@') {
                my $a = $b->emit(op => 'NewArray', type => '%Array*');
                $b->field_default_into($a, $f->default_value) if $f->has_default;
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $b->emit(op => 'ARef', type => '%Slot', inputs => [$a]) ]);
                next;
            }
            if ($f->sigil eq '%') {
                my $h = $b->emit(op => 'HNew', type => '%Slot');
                if ($f->has_default) {
                    my $l = $b->emit(op => 'NewArray', type => '%Array*');
                    $b->field_default_into($l, $f->default_value);
                    $b->emit(op => 'HFromArray', type => 'void', inputs => [ $h, $l ]);
                }
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $h ]);
                next;
            }
            out('a ' . $f->sigil . ' field') unless $f->sigil eq '$';
            my $v;
            if (defined $f->param_name && $given{ $f->param_name }) { $v = $argval->( $f->param_name ) }
            elsif ($f->has_default) { $v = $b->field_default( $f->default_value ) }
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

# field_default($node) -> a scalar field's default, made anew for this object
# (perl evaluates it at each construction: `field $r = [...]` is a new array
# each time, `field $b = Box->new` a new call): built with a memo of its own,
# so nothing made for one object is another's. Only a default made of
# itself -- constants, [...] and (...) of them, a method call on a class by
# name -- is T2's: one reading a variable or an earlier field is not.
# field_default_into($array, $node): an aggregate field's default, its list
# pushed onto $array (a new one per object).
sub _self_made {
    my ($n, $seen) = @_;
    return 0 unless blessed($n);
    return 1 if $seen->{ refaddr($n) }++;
    my $op = $n->operation;
    return 0 unless $op eq 'Constant' || $op eq 'ArrayLiteral' && ( $n->stamp // '' ) =~ /\A(?:Array|ArrayRef)\z/   # static type
        || $op eq 'HashLiteral' && ( $n->stamp // '' ) =~ /\A(?:Hash|HashRef)\z/   # (`{...}`: a new hash each object, as `[...]` is)
        || $op eq 'Call' && ( $n->dispatch_kind // '' ) eq 'method' && blessed( $n->inputs->[0] ) && $n->inputs->[0]->operation eq 'Constant';
    return !grep { !_self_made($_, $seen) } grep { blessed($_) } $n->inputs->@*;
}
sub field_default {
    my ($b, $d) = @_;
    out('a field default that is not made of itself') unless _self_made($d, {});
    local $b->{memo} = {};
    local $b->{depth} = 0;   # (made here, for this object: an arm's or a body's is its own)
    local $b->{lscope};
    local $b->{scope_in};
    local $b->{in_field_default} = 1;   # (a {...} in it is made here, each object its own)
    return $b->as($b->value($d), '%Slot');
}
sub field_default_into {
    my ($b, $arr, $d) = @_;
    out('a field default that is not made of itself') unless _self_made($d, {});
    local $b->{memo} = {};
    local $b->{depth} = 0;
    local $b->{lscope};
    local $b->{scope_in};
    for my $e ( $d->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && ( $d->stamp // '' ) =~ /\A(?:Array|Hash)\z/ ? $d->inputs->@* : $d ) {   # static type
        next unless blessed($e);
        if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($e) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($e), '%Slot') ]) }
    }
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
    # `$o->$m(...)`: the method's name is a value, the input after the invocant.
    my $dyn = ( $c->dispatch_kind // '' ) eq 'dynamic_method' ? ( splice @args, 1, 1 ) : undef;
    out('a method named at run time by a list') if $dyn && _is_list($dyn);
    out('a method named at run time in a program that uses parent or base (inheritance the loader drops)')
        if $dyn && ( $Chalk::IR::Serialize::JSON::USED_MODULES{parent} || $Chalk::IR::Serialize::JSON::USED_MODULES{base} );
    out('a method call with no invocant') unless @args && blessed($args[0]);
    out('a method call on a list') if _is_list($args[0]);
    # @_, the invocant and the arguments, aliased.
    my $arr = do { local $b->{arg_call} = $c; local $b->{alias_writes} = $b->call_writes_args($c); local $b->{alias_refs} = $b->call_refs_args($c); $b->args_array(@args) };
    # (A PLACE invocant is read through its alias, @_'s first, as it is now)
    my $inv = blessed( $args[0] ) && $args[0]->can('place') && $args[0]->place
        ? $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ])
        : $b->as($b->value($args[0]), '%Slot');
    $b->hash_reads_settled('a method call');
    $b->set_want($c);   # whichever sub it finds may return a list
    # (where perl dies -- no class, no method -- a die, an eval's to catch)
    my $at = ' at ' . ( $c->can('file') ? $c->file // '-' : '-' ) . ' line ' . ( $c->can('line') ? $c->line // 0 : 0 ) . ".\n";
    # A QUALIFIED NAME starts its lookup at its package (mode 1); Pkg::SUPER::m
    # at the @ISA of Pkg, the package the call is in (mode 2).
    my ($start, $mode, $m) = ( '', 0, $c->name );
    if ($dyn) { $m = undef }
    elsif ($m =~ /\A(.+)::SUPER::(\w+)\z/) { ( $start, $mode, $m ) = ( $1, 2, $2 ) }
    elsif ($m =~ /\A(.+)::(\w+)\z/)     { ( $start, $mode, $m ) = ( $1, 1, $2 ) }
    out('a method name T2 cannot split') if defined $m && $m =~ /::|'/;
    my $mn = $dyn ? $b->emit(op => 'DynName', type => '%Str', inputs => [ $b->as( $b->value($dyn), '%Slot' ) ]) : $b->const_str($m);
    my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => $mode },
        inputs => [ $inv, $mn, $b->const_str($at), $b->const_str($start) ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ], site => $c);
}

# @_ ALIASES THE CALLER'S ARGUMENTS (perigrin): a call taking @_ as one
# array is handed an array of aliases (the runtime's t2_new_args) -- each
# argument the caller's own container: its variable, its element, a fresh
# cell for a temporary, a literal as it is (read-only: perl dies on a store).
# A list's elements are each aliased. Reads of @_ go through the alias;
# stores reach the caller.
sub args_array {
    my ($b, @args) = @_;
    # (WHERE THE CALL MAY WRITE @_ -- alias_writes, its caller's -- an
    # argument perl aliases and T2 cannot reach is refused)
    my $arr = $b->emit(op => 'NewArgs', type => '%Array*');
    for my $a (@args) {
        if (_is_list($a)) { $b->emit(op => 'AAppendAlias', type => 'void', inputs => [ $arr, $b->alias_list($a) ]) }
        else { $b->emit(op => 'APushAlias', type => 'void', inputs => [ $arr, $b->arg_alias($a) ]) }
    }
    return $arr;
}

# _of_args($n) -> @_, or an element of it.
sub _of_args {
    my ($n) = @_;
    return blessed($n) && ( $n->operation eq 'ArgsSource'
        || $n->operation eq 'Subscript' && blessed( $n->inputs->[0] ) && $n->inputs->[0]->operation eq 'ArgsSource' );
}
sub _writes_args_in {
    return scalar grep {
        my $n = $_;
        my $op = $n->operation;
        $op eq 'Assign' && _of_args( $n->inputs->[0] )
            || $op =~ /\A(?:Ref|RegexSubst|Transliterate|Chomp|Chop)\z/ && _of_args( $n->inputs->[0] )
            # (a 4-argument substr replaces part of its string in place)
            || $op eq 'Call' && $n->writes_first_argument
               && do { my $t = $n->inputs->[0]; $t = $t->inputs->[0] while blessed($t) && $t->operation eq 'Coerce'; _of_args($t) }
    } @_;   # (a shift, a push: @_ itself changes, no caller's variable)
}
# writes_args -> some sub of the program stores into @_ (`$_[N] = ...`, an
# op-assign, a substitution on it) or takes a reference into it: an
# argument perl aliases and T2 would copy is then refused.
sub writes_args {
    my ($b) = @_;
    return $b->{writes_args} //= _writes_args_in( _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} ),
        map { $_->graph ? $_->graph->component : () } map { $_->methods } $b->{mop} ? $b->{mop}->classes : () );
}

# refs_into_args -> some sub of the program takes a reference to an element of
# its @_ (`\$_[0]`): the caller's own container. (A foreach alias's never made -- its
# deref read as the element -- is none.)
sub _refs_args_in {
    return scalar grep {
        $_->operation eq 'Ref' && $_->element_subscript && !$_->is_alias_ref && blessed( $_->element_subscript->inputs->[0] )
            && $_->element_subscript->inputs->[0]->operation eq 'ArgsSource'
    } @_;
}
sub refs_into_args {
    my ($b) = @_;
    return $b->{refs_into_args} //= _refs_args_in( _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} ),
        map { $_->graph ? $_->graph->component : () } map { $_->methods } $b->{mop} ? $b->{mop}->classes : () );
}

# call_targets($Call) -> the subs the call may run: a direct call's sub; a
# method call's, every sub or method of the program of its name (whichever
# class the invocant is) -- or () where T2 cannot tell: a method named at run
# time, an AUTOLOAD, one of its name with no body here, a code value.
sub call_targets {
    my ($b, $c) = @_;
    my $k = $c->dispatch_kind // '';
    if ( $k eq 'direct' ) {
        my $t = $c->can('target') ? $c->target : undef;
        return blessed($t) && $t->can('graph') && $t->graph ? ($t) : ();
    }
    return () unless $k eq 'method' && $b->{mop};
    my $m = ( $c->name // '' ) =~ s/\A.*:://r;
    my @all = map { ( $_->subs, $_->methods ) } $b->{mop}->classes;
    return () if grep { ( $_->name // '' ) =~ /(?:\A|::)AUTOLOAD\z/ } @all;
    my @t = grep { ( ( $_->name // '' ) =~ s/\A.*:://r ) eq $m } @all;
    return () if !@t || grep { !( $_->can('graph') && $_->graph ) } @t;
    return @t;
}

# _hands_args_on(@nodes) -> a call among them hands its @_ on (`&g`, `g(@_)`, `g($_[0])`).
sub _hands_args_on {
    return scalar grep {
        $_->operation eq 'Call' && $_->is_sub_call
            && ( $_->can('shares_args') && $_->shares_args || grep { _of_args($_) } $_->inputs->@* )
    } @_;
}

# call_refs_args($Call) -> what it calls may take a reference into its @_:
# a sub it may run does (call_targets), or hands its @_ on where any sub
# does; a call whose subs T2 cannot tell, where any sub does (as
# call_writes_args).
sub call_refs_args {
    my ($b, $c) = @_;
    my @t = $b->call_targets($c) or return $b->refs_into_args;
    for my $t (@t) {
        my @gn = $t->graph->component;
        return 1 if _refs_args_in(@gn);
        return $b->refs_into_args if _hands_args_on(@gn);
    }
    return 0;
}

# may_write_args -> the call whose @_ is being built may write it (or the
# list's aliases are stored through: alias_strict).
sub may_write_args {
    my ($b) = @_;
    return $b->{alias_strict} || ( $b->{alias_writes} // $b->writes_args );
}

# call_writes_args($Call) -> what it calls may write its @_: a sub it may
# run writes it (call_targets), or hands it on (`&g`, `g(@_)`, `g($_[0])`)
# where any sub writes; a call whose subs T2 cannot tell, where any sub writes.
sub call_writes_args {
    my ($b, $c) = @_;
    my @t = $b->call_targets($c) or return $b->writes_args;
    for my $t (@t) {
        my @gn = $t->graph->component;
        return 1 if _writes_args_in(@gn);
        return $b->writes_args if _hands_args_on(@gn);
    }
    return 0;
}

# arg_alias($n) -> what @_ holds for a scalar argument: an alias of the
# caller's container (a scalar reference to a variable, an element alias),
# a literal as it is (read-only), else a fresh cell of the value (a
# temporary). One perl aliases and T2 cannot reach is refused where a sub
# may write @_.
sub arg_alias {
    my ($b, $n) = @_;
    my $op = $n->operation;
    if ($op eq 'Constant' && ( $n->const_type // '' ) =~ /\A(?:integer|number|string|boolean|undef)\z/) {
        # (WHERE A SUB TAKES A REFERENCE INTO @_ -- `\$_[0]` -- perl's is to the
        # literal itself, read-only: a fresh cell of it is told apart only by
        # a store, so it is one where nothing may store through a reference or
        # into @_; else refused)
        if ( $b->{alias_refs} // $b->refs_into_args ) {
            out('a literal passed where a sub takes a reference into @_ and a store may go through one (perl\'s literal is read-only)')
                if $b->{stores_through} //= Chalk::IR::Node::Ref::stores_through( _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} ) );
            return $b->emit(op => 'Fresh', type => '%Slot', inputs => [ $b->as($b->value($n), '%Slot') ]);
        }
        return $b->as($b->value($n), '%Slot');
    }
    if ($op eq 'PadAccess' && ( $n->sigil // '' ) eq '$' && $n->is_location) {
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($n) ]);
    }
    # (a captured variable's place: its cell)
    if ($op eq 'CellRead' && $n->place) {
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->value( $n->inputs->[0] ) ]);
    }
    if ($n->is_package_scalar) {
        out('a package scalar of no one version passed as an argument') if $b->{unversioned}{ refaddr($n) };
        # A READ AT AN OLDER VERSION THAN THE CALL'S, which B::SoN did not
        # pass as a place, is the value it read, not the variable now:
        # `f($g, $g++)` hands f the old $g, a copy -- passed as $g itself,
        # it was read after the increment's store (`2 2` for `2 1`, audit 2,
        # K6). Made at its version (the chain walk's read-before-kill).
        my $call = $b->{arg_call};
        return $b->emit(op => 'Fresh', type => '%Slot', inputs => [ $b->as($b->value($n), '%Slot') ])
            if !$n->place && blessed( $n->mem_in ) && blessed($call) && blessed( $call->mem_in )
            && refaddr( $n->mem_in ) != refaddr( $call->mem_in );
        return $b->topic_raw if $b->is_topic($n) && $b->topic_alias;   # (what $_ is now: its alias)
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->scalar_addr($n) ]);
    }
    # (a foreach alias read, B::SoN's ${ \ $a[i] }: the element)
    $n = $n->alias_element if $op eq 'PostfixDeref' && $n->alias_element;
    # A READ THROUGH AN ELEMENT REFERENCE T2 MAKES -- a foreach alias's,
    # `${ exists $a[i] ? \$a[i] : undef }`, or B::SoN's guard of it again
    # around the read -- is the element: its cell, the reference itself.
    if ( my $r = _element_ref_read($n) ) {
        return $b->emit(op => 'AliasOf', type => '%Slot', inputs => [ $b->as( $b->value($r), '%Slot' ) ]);
    }
    if ($n->operation eq 'Subscript' && !$b->{args}{ refaddr($n) }) {
        my ($c, $k) = $n->inputs->@[0, 1];
        # (ITS READ THROUGH A REFERENCE, if it is one, made here, before the
        # call -- where perl's argument was -- not left waiting across it)
        $b->value($n) if $b->_through_ref($n);
        out('an element of an array B::SoN reads at no version, aliased where it may be written')
            if $b->may_write_args && _folded($c);
        if (( $n->can('kind') ? $n->kind // 'array' : 'array' ) eq 'hash') {
            my $key = $b->as($b->value($k), '%Str');
            return $b->emit(op => ( $n->can('vivify') && $n->vivify ? 'ElvHViv' : 'ElvH' ), type => '%Slot', inputs => [ $b->hash_of($c), $key ]);
        }
        my $ix = $b->as($b->value($k), 'i64');
        # (an element of a list written out -- a foreach's over `($x, @a[1, 2])`
        # -- is its item's own: an element of the list's aliases)
        # (through an element: where @_ may be written, the array it holds --
        # one undef there stops, perl's call makes one; else read as an
        # element is, through undef undef)
        my $arr = blessed($c) && $c->operation eq 'ArrayLiteral' && !defined $c->symbol && ( $c->stamp // '' ) eq 'Array' ? $b->alias_list($c)   # static type
            : do { local $b->{ $b->may_write_args ? 'writing' : 'elem_read' } = 1; $b->array_of($c) };
        return $b->emit(op => ( $n->can('vivify') && $n->vivify ? 'ElvAViv' : 'ElvA' ), type => '%Slot', inputs => [ $arr, $ix ]);
    }
    if ($n->operation eq 'FieldAccess' && ( $b->field_of($n) )[1] eq '$') {
        my $self = $b->{self} // out('a field outside a method');
        return $b->emit(op => 'ElvH', type => '%Slot', inputs => [ $self, $b->const_str( ( $b->field_of($n) )[0] ) ]);
    }
    # A VALUE MADE HERE: a temporary, a fresh cell the callee may write.
    # (one perl would alias -- a `my` T2 holds as a value, an argument this
    # sub took by value, a choice of variables, a deref -- refused where a
    # sub writes @_)
    out('an argument perl aliases (' . $n->operation . ') passed where a sub writes @_')
        if $b->may_write_args && ( $n->operation =~ /\A(?:PadAccess|TernaryExpr|PostfixDeref|Assign|Subscript|And|Or|DefinedOr|Phi)\z/ );
    return $b->emit(op => 'Fresh', type => '%Slot', inputs => [ $b->as($b->value($n), '%Slot') ]);
}

# _element_ref_read($n) -> the element reference $n reads through (a Ref, or
# the foreach alias's guard of one), or undef: $n is `${ R }` of it, or
# `c ? ${ R } : undef` where R is guarded by that same c.
sub _element_ref_read {
    my ($n) = @_;
    return undef unless blessed($n);
    if ( $n->operation eq 'TernaryExpr' ) {
        my ( $c, $d, $u ) = $n->inputs->@*;
        my $r = _element_ref_read($d) or return undef;
        return undef unless $r->operation eq 'TernaryExpr' && blessed( $r->inputs->[0] ) && blessed($c) && refaddr( $r->inputs->[0] ) == refaddr($c);
        # (its other arm: undef, or the element read -- none there)
        my $s = $r->inputs->[1]->element_subscript;
        return $r if blessed($u) && ( $u->operation eq 'Constant' && ( $u->const_type // '' ) eq 'undef'
            || $u->operation eq 'Subscript' && ( $u->kind // '' ) eq 'array'
               && refaddr( $u->inputs->[0] ) == refaddr( $s->inputs->[0] ) && refaddr( $u->inputs->[1] ) == refaddr( $s->inputs->[1] ) );
        return undef;
    }
    return undef unless $n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '$';
    my $r = $n->inputs->[0];
    return $r if blessed($r) && $r->operation eq 'Ref' && ( $r->element_subscript || $r->hash_element_subscript );
    return $r if blessed($r) && $r->operation eq 'TernaryExpr' && blessed( $r->inputs->[1] ) && $r->inputs->[1]->operation eq 'Ref'
        && $r->inputs->[1]->element_subscript && Chalk::IR::Node::Ref::_guards( $r, $r->inputs->[1] );
    return undef;
}

# _folded($aggregate) -> a named array or hash B::SoN reads at no memory
# version anywhere: one it takes for never written, every read of it folded
# to what it was made with -- a store through an alias of its elements (a
# slice handed to a call, a foreach over a list of it) never seen after.
sub _folded {
    my ($n) = @_;
    return 0 unless blessed($n) && $n->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $n->symbol;
    return !grep { my $u = $_; blessed($u) && ( blessed( $u->mem_in ) || grep { blessed($_) && $_->is_memory_version } $u->inputs->@* ) } ( $n->consumers // [] )->@*;
}

# alias_list($n) -> an array whose elements an @_ aliases (AAppendAlias): an
# array itself (each element aliased), or an @_ of the list's own aliases --
# a list written out, a choice of lists, a slice. A list made here (a map's,
# a sort's, a call's) is copied: perl's own may be aliases (grep, sort), so
# it is refused where a sub writes @_.
sub alias_list {
    my ($b, $n) = @_;
    my $op = $n->operation;
    out('an array B::SoN reads at no version, aliased where it may be written')
        if $b->may_write_args && _folded($n);
    # (an array through an element -- `f(@$_)`, `f(@{$h{l}})` -- is the one
    # it holds: perl's call makes it one, T2's stops where it is none)
    return do { local $b->{writing} = 1; $b->array_of($n) } if $op eq 'ArgsSource' || $op eq 'ArrayLiteral' && defined $n->symbol
        || $n->is_my_array || $n->is_array_deref || $n->is_argv || $n->is_package_aggregate && $n->sigil eq '@';
    if ($op eq 'ArrayLiteral' && ( $n->stamp // '' ) eq 'Array') {   # static type
        return $b->args_array( grep { blessed($_) } $n->inputs->@* );
    }
    if ($op eq 'TernaryExpr') {
        my ($cond, $then, $else) = $n->inputs->@*;
        my $c = $b->truth($b->value($cond));
        my $from = $b->{cur};
        my $arm = sub ($x) { _is_list($x) ? $b->alias_list($x) : $b->args_array($x) };
        # (A READ THROUGH A REFERENCE an arm makes -- `$c ? @$x : ()` -- is
        # made there, before the call: settled, not waiting across it. Read
        # again past what settles it, it would be of the later state: refused.)
        my %made;
        my $in_arm = sub ($x) {
            local $b->{memo} = { $b->{memo}->%* };
            my %had = map { ( $_ => 1 ) } keys $b->{memo}->%*;
            my $r = $arm->($x);
            $made{$_} = 1 for grep { !$had{$_} } keys $b->{memo}->%*;
            return $r;
        };
        my $tb = $b->new_block('then');
        my $tv = $in_arm->($then);
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        my $ev = $in_arm->($else);
        my $eend = $b->{cur};
        $b->{made}{$_} = 1 for keys %made;
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $c, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => '%Array*', inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
    # A SLICE: an alias of each element it names (`g($_) for @n[1 .. 2]`).
    if ($op eq 'Slice') {
        $b->list_only($n, 'a slice');
        my @ix = grep { blessed($_) } $n->inputs->@*;
        my $src = pop @ix;
        out('a slice of an array B::SoN reads at no version, aliased where it may be written')
            if $b->may_write_args && _folded($src);
        my $list = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@ix) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
        }
        my $kind = $n->kind // '';
        return $b->emit(op => 'HSliceAlias', type => '%Array*', inputs => [ $b->hash_of($src), $list ]) if $kind eq 'hash';
        out("a slice of kind $kind") unless $kind eq 'array';
        my $arr = do { local $b->{ $b->may_write_args ? 'writing' : 'elem_read' } = 1; $b->array_of($src) };
        return $b->emit(op => 'ASliceAlias', type => '%Array*', inputs => [ $arr, $list ]);
    }
    # `values %h`: AN ALIAS OF EACH VALUE, in its keys' order (perl's values
    # are the hash's own scalars): the hash's slice by its own keys.
    if ( $op eq 'Call' && ( $n->lists_a_hash // '' ) eq 'values' ) {
        my $in0 = $n->inputs->[0];
        my $h = blessed($in0) && $in0->operation eq 'PostfixDeref' && ( $in0->sigil // '' ) eq '%' && !$in0->copy
            ? $b->emit(op => 'HDerefR', type => '%Slot', inputs => [ $b->whole_hash($in0, $b->as($b->value( $in0->inputs->[0] ), '%Slot')) ])
            : $b->hash_of($in0);
        return $b->emit(op => 'HSliceAlias', type => '%Array*', inputs => [ $h, $b->emit(op => 'HKeys', type => '%Array*', inputs => [$h]) ]);
    }
    # (A LIST A SUB RETURNS is of copies, temporaries none else holds -- not an
    # :lvalue sub's, whose list is its variables: its array, aliased, is them)
    if ( $op eq 'Call' && $n->is_sub_call && $b->may_write_args ) {
        my @t = $b->call_targets($n);
        return $b->array_of($n) if @t && !grep { $_->can('lvalue') && $_->lvalue } @t;
    }
    out('a list perl may alias (' . $op . ') passed where a sub writes @_') if $b->may_write_args;
    return $b->array_of($n);
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
    if (( $n->dispatch_kind // '' ) eq 'direct' && !$b->is_glob_call($n) && ( ( $n->name // '' ) !~ /__(?:ANON|EVAL)__/ || $b->plain_anon($n) )) {
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
    if ($b->{tail} && ( ( $b->{tail}{call} // 0 ) == refaddr($c) || $b->{tail}{calls}{ refaddr($c) } )) {   # handed on from this sub's caller
        return $b->emit(op => 'SetWant', type => 'void', inputs => [ $b->{tail}{want} ]);
    }
    my $fn = blessed( $c->target ) ? $b->{funcs}{ refaddr( $c->target ) } : undef;
    out('a call not in list context of a sub\'s list-context copy') if $fn && $fn->{list_copy} && !_list_use($c);
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
    out('a closure called directly and as a code value') if $b->{funcs}{ refaddr($sub) } && !$b->{funcs}{ refaddr($sub) }{closure};
    # (its cells by the name of what each captures, for a `my` aggregate's)
    my %cells = map { my $c = ( $a->inputs->@* )[$_]; blessed($c) && $c->can('cell_name') && defined $c->cell_name ? ( $c->cell_name => $_ ) : () } 0 .. $a->inputs->$#*;
    my $fn = $b->func($sub, $a->name // 'anon', closure => 1, cells => \%cells);
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

# code_ref($Constant) -> `\&name`: a code value (tag 8) of the named sub, its
# wrapper's entry (`_cw`, as a closure's) and no cells. A sub the program
# does not define here (XS, perl's own, one never loaded) is refused.
sub code_ref {
    my ($b, $c) = @_;
    my $q = $c->value // out('a code reference of no name');
    my ($pkg, $short) = $q =~ /\A(.*)::(\w+)\z/ ? ( $1, $2 ) : ( 'main', $q );
    my $cls = $b->{mop} ? $b->{mop}->for_class($pkg) : undef;
    my ($sub) = $cls ? grep { $_->name eq $short && $_->graph } $cls->subs : ();
    out("a reference to a sub not here ($q)") unless $sub;
    my $fn = $b->func($sub, $q);
    out("a reference to a closure's sub ($q)") if $fn->{closure};
    $fn->{coderef} = 1;   # (its `_cw`, the code value's entry, is printed)
    my $env = $b->emit(op => 'EnvNew', type => '%Slot**', inputs => [ $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ]);
    return $b->emit(op => 'CodeNew', type => '%Slot', inputs => [$env], attr => { fn => $fn->{name} });
}

# code_call($Call, $code, @args) -> calling a code value: @_ built (lists
# flattened), its function found (a stop if it is no code), called with its
# cells, in the call's context.
sub code_call {
    my ($b, $c, $code, @args) = @_;
    # `&$code;` IS CALLED WITH THE CALLER'S OWN @_ (the same array): the
    # caller must take @_ as an array.
    if ($c->can('shares_args') && $c->shares_args) {
        out('an & call of a code value sharing @_ of a sub not taking it as a list') unless $b->{argsarr};
        $b->hash_reads_settled('a call of a code value');
        $b->set_want($c);
        return $b->emit_call(op => 'CallCode', type => '%Slot', inputs => [ $code, $b->{argsarr} ], site => $c);
    }
    my $arr = do { local $b->{arg_call} = $c; local $b->{alias_writes} = $b->call_writes_args($c); local $b->{alias_refs} = $b->call_refs_args($c); $b->args_array(@args) };
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
    # EXACTLY ONE: a graph's returns are found by a walk of its nodes, in no
    # fixed order -- of two Returns, "the first" would be either.
    out("sub $name has more than one Return") if ( grep { blessed($_) && $_->operation eq 'Return' } $g->returns->@* ) > 1;
    # (T1's integer intervals over its body, where the analysis has not run)
    Chalk::IR::Analysis::integer_intervals( $g->returns->@* );
    # A LIST RETURN: B::SoN's Return(list, scalar) -- the list, and what the
    # sub gives in scalar context (its last, a count, undef). The caller's
    # context (@t2_want, set before the call) picks one.
    my $valueless = $ret->can('valueless') && $ret->valueless;   # `()`, a bare return
    # `return values %h` (keys too): one input, B::SoN's, in the caller's
    # context -- the list, or its count. A list return as well.
    my $hkv = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && $ret->inputs->[0]->lists_a_hash
        && ( $ret->inputs->[0]->can('want') ? $ret->inputs->[0]->want // '' : '' ) ne 'scalar'   # `scalar(keys %h)`: a count always
        ? $ret->inputs->[0] : undef;
    # `return @a` (one input, an array -- a `my` one, or a class's array
    # field: `method items { return @items }`): in the caller's context, its
    # elements or its count. A list return too.
    my $arrret = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && !$hkv
        && ( $ret->inputs->[0]->is_my_array || $ret->inputs->[0]->operation eq 'ArrayLiteral' && ( $ret->inputs->[0]->stamp // '' ) eq 'Array'   # static type
             || $ret->inputs->[0]->operation eq 'FieldAccess' && ( $b->field_of( $ret->inputs->[0] ) )[1] eq '@'
             # (a package array, read at a version: `sub z { @a }`, `sub z { @a = () }`)
             || $ret->inputs->[0]->is_package_aggregate && $ret->inputs->[0]->sigil eq '@' )
        ? $ret->inputs->[0] : undef;
    # `return /x/` (a match its last statement): its groups in a list, its
    # truth in a scalar.
    my $mret = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation =~ /\A(?:RegexMatch|Match)\z/
        ? $ret->inputs->[0] : undef;
    # A LIST-CONTEXT COPY OF A SUB (Serialize::JSON's CONTEXT_COPY: its
    # caller's-context eval made a list one) returning a list: only a call in
    # list context runs it, and its value is that list.
    my $ctxlist = ( $sub->can('context') ? $sub->context // '' : '' ) eq 'list'
        && $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && _is_list( $ret->inputs->[0] )
        ? $ret->inputs->[0] : undef;
    # `@l = (9)` ITS LAST STATEMENT (a list assign to an array or hash field):
    # in the caller's context, the aggregate's list or the count assigned.
    my $laret = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Assign'
        && $ret->inputs->[0]->can('targets') && defined $ret->inputs->[0]->targets
        ? $ret->inputs->[0] : undef;
    my $listret = $ret->inputs->@* == 2 || $valueless || $hkv || $arrret || $mret || $laret || $ctxlist;
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
        # A SLURPY PARAMETER (`method f ($x, @rest)`, its last): the method
        # takes @_ as one array (its invocant first), the slurpy one a copy of
        # what is past the others; its arity checked by its wrapper.
        my @pnames = map { ref($_) ? $_->{name} // $_->{sigil} // '' : $_ // '' } +($sub->can('params') ? $sub->params // [] : [])->@*;
        my ($sl) = grep { $pnames[$_] =~ /\A[@%]/ } 0 .. $#pnames;
        out("method $name has a slurpy parameter not its last") if defined $sl && $sl != $#pnames;
        out("method $name has a slurpy parameter B::SoN gives not as declared")
            if grep { $_->operation eq 'Parameter' && ( $_->can('sigil') ? $_->sigil // '$' : '$' ) ne '$' && !( defined $sl && ( $_->index // -1 ) == $sl ) } @gn;
        $margs{slurpy} = $sl;
        $margs{ refaddr($_) } = 0 for grep { $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq 'self' } @gn;
        $margs{ refaddr($_) } = $_->index + 1 for grep { $_->operation eq 'Parameter' && ( $_->can('sigil') ? $_->sigil // '$' : '$' ) eq '$' } @gn;
        $margs{np} = $np;
    }
    # A SUB MADE IN A METHOD READING ITS FIELDS (`method n { my $in = sub
    # ($k) { exists $m{$k} } ... }`): perl's closure over the method's pad, a
    # field among it. Called directly (B::SoN resolved it) only from the
    # method that makes it, it is handed that method's object as a last,
    # hidden argument (self_arg): its fields are that object's. As a code
    # value (one that may be called anywhere) it is refused.
    my $self_arg = !$is_method && grep { $_->operation eq 'FieldAccess' } $g->component;
    out("closure $name reads a field of its method's object, as a code value") if $self_arg && $closure;
    out("sub $name reads a field and is no closure of a method") if $self_arg && $name !~ /::__ANON__/;
    require Chalk::Target::LLVM::Builder::Args;
    my $an = bless {}, 'Chalk::Target::LLVM::Builder::Args';
    my @reads = $is_method ? () : eval { $an->_collect_positional_arg_reads($g, $name) };
    # @_ READ AS A LIST (join(@_), "@_", scalar(@_), for (@_)): the sub takes
    # @_ as one %Array its caller builds -- the list convention. A write to
    # $_[N] (the caller's variable) or a signature is not T2's.
    # A CLOSURE takes @_ as one array always (its code value's calling
    # convention), its captured cells as its environment.
    # A SUB THAT HANDS ITS @_ ON (`&f;`, `&$code;`) takes it as one array too.
    my $hands_on = grep { $_->operation eq 'Call' && $_->can('shares_args') && $_->shares_args } $g->component;
    my $list = !$is_method && !$@ && ( $an->{_args_read_as_a_list} || $closure || $hands_on ) && !$an->{_args_written} && !$an->{_args_slurpy} && !$an->{_args_signature};
    # @_ WRITTEN, OR READ OTHER THAN BY ONE POSITIONAL STYLE (shifts and
    # $_[N] mixed, a pop, @_ handed to an op): the sub takes @_ as the array
    # of aliases its caller builds -- a store into it reaches the caller's
    # variable, a read sees it as it is now. (Not a signature's: its
    # parameters are its own.)
    # (One that SHIFTS @_ as well, its other reads where the graph orders
    # none -- `my %a = @_` after a shift -- is not: they would read it whole.)
    my $declared = grep { $_->operation eq 'Parameter' } $g->component;
    my $shifted = grep { $_->operation eq 'Call' && $_->mutates_array && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'ArgsSource' } $g->component;
    $list ||= !$is_method && !$declared && !$shifted && ( $@ || $an->{_args_written} );
    # (A REFERENCE TO AN ELEMENT OF @_ -- `\$_[0]` -- is to the caller's own
    # container: @_ taken as that array of aliases too.)
    $list ||= !$is_method && !$declared && !$shifted
        && grep { $_->operation eq 'Ref' && $_->element_subscript && !$_->is_alias_ref && blessed( $_->element_subscript->inputs->[0] ) && $_->element_subscript->inputs->[0]->operation eq 'ArgsSource' } $g->component;
    # A SUB SOME CALL PASSES A PLACE (B::SoN could not prove the alias
    # private: aliases-as-places): its @_ reads -- `$_[N]`, a shift, `my (...)
    # = @_` -- see the caller's variable as it is when they run, so it takes
    # @_ as the array of aliases its caller builds. (So does a foreach
    # iterator aliased by reference, B::SoN's read through the pass's element
    # reference: perl hands the element -- by value, a store to it before
    # `$_[0]` was lost, `1` for `5`: probe x/xm27.)
    $list ||= !$is_method && !$declared && grep {
        my $k = $_;
        $k->operation eq 'Call' && $k->is_sub_call
            && ( grep { blessed($_) && ( $_->can('place') && $_->place || _element_ref_read($_) ) } $k->inputs->@* )
            && grep { refaddr($_) == refaddr($sub) } $b->call_targets($k)
    } _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} );
    # A SUB A CALL PASSES A LIST (`f(@$r)`): its count is the list's, known at
    # run time only -- @_ as that one array too.
    $list ||= !$is_method && !$declared && grep {
        my $k = $_;
        $k->operation eq 'Call' && ( $k->dispatch_kind // '' ) eq 'direct' && blessed( $k->target ) && refaddr( $k->target ) == refaddr($sub)
            && !( $k->can('shares_args') && $k->shares_args )
            && grep { blessed($_) && !$_->is_memory_version && _is_list($_) } $k->inputs->@*
    } _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} );
    # A SLURPY TAIL (`my ($c, @x) = @_`, `sub f ($c, @x)` -- perigrin: the same)
    # takes @_ as one array: the positional targets its elements 0..k-1, the
    # slurpy one a copy of the rest.
    my $slurpy = !$is_method && !$@ && !$closure && !$an->{_args_written} && !$an->{_args_read_as_a_list} ? $an->{_args_slurpy} : undef;
    my @positional = $slurpy ? @reads : ();
    $list = 1 if $slurpy;
    # A SIGNATURE'S OPTIONAL PARAMETERS (`($a, $b = 3)`): @_ as one array,
    # each such parameter its argument where one was passed, else its default
    # -- one made the same anywhere (a constant), made at entry. Perl dies
    # with too many arguments: the count is checked at each call, so such a
    # sub is called directly only.
    # (B::SoN's `mandatory` counts every positional parameter, optional ones too)
    my $decl = !$is_method && $sub->can('signature') ? $sub->signature // {} : {};
    my @defaulted = grep { $_->operation eq 'Parameter' && blessed( $_->inputs->[0] ) } $g->component;
    # (A DEFAULT THE BODY COMPUTES -- `($x = g())`: B::SoN tests @_'s count
    # and calls g where none was passed -- reads @_ only by counting it.)
    my $counted = grep { $_->operation eq 'ArgsSource' } $g->component;
    $counted &&= !grep { my $s = $_; $s->operation eq 'ArgsSource' && grep { blessed($_) && $_->operation ne 'Count' } ( $s->consumers // [] )->@* } $g->component;
    my $optional = !$is_method && !$closure && !$@ && $an->{_args_signature} && ( $decl->{optional} // 0 ) > 0
        && !$an->{_args_written} && ( !$an->{_args_read_as_a_list} || $counted );
    if ($optional) {
        out("sub $name has an optional parameter of no default") if @defaulted != $decl->{optional} && !$counted;
        out("sub $name has a default that is not made the same anywhere") if grep { !$_->inputs->[0]->all_made_the_same } @defaulted;
        @positional = grep { defined } @reads unless $slurpy;
        $list = 1;
    }
    # A SIGNATURE PARAMETER THE BODY NEVER READS (`sub g ($k, $x)` reading
    # only $k) has its place all the same: its argument passed, unused. (Its
    # arity is checked at each call: called directly only, as above.)
    my $padded;
    if (!$optional && !$is_method && !$closure && !$slurpy && !$@ && $an->{_args_signature} && !( $decl->{optional} // 0 )
           && !$an->{_args_written} && !$an->{_args_read_as_a_list} && ( $decl->{mandatory} // 0 ) >= @reads) {
        $padded = ( $decl->{mandatory} // 0 ) > @reads || grep { !defined } @reads;
        @reads = map { $reads[$_] // bless( {}, 'Chalk::Target::LLVM::Builder::Unread' ) } 0 .. $decl->{mandatory} - 1;
    }
    # A CLOSURE'S SIGNATURE (`sub ($n) {...}`, `sub ($id, @rest)`): its
    # parameters from @_, the one array its code value is called with; its
    # arity checked at its entry, at least and at most -- a run-time stop
    # where perl dies (a call through a code value has no count known here).
    my $sigclosure = $closure && !$@ && $an->{_args_signature} && !$an->{_args_written} && !$an->{_args_read_as_a_list};
    my ($cmin, $cmax);
    if ($sigclosure) {
        $slurpy = $an->{_args_slurpy};
        if (( $decl->{optional} // 0 ) > 0 || @defaulted) {
            out("closure $name has an optional parameter of no default") if $slurpy || defined $decl->{optional} && @defaulted != $decl->{optional};
            out("closure $name has a default that is not made the same anywhere") if grep { !$_->inputs->[0]->all_made_the_same } @defaulted;
        }
        @positional = grep { defined } @reads;
        # (an anon sub's signature record may be missing: its parameters
        # then, by place -- a trailing one never read is not there, and a
        # call passing it stops, loudly)
        my $all = $decl->{mandatory};
        unless (defined $all) {
            $all = 0;   # (not sort: a sort block's $b is the builder here)
            $all < $_->index + 1 and $all = $_->index + 1 for grep { $_->operation eq 'Parameter' && ( $_->sigil // '$' ) eq '$' } $g->component;
        }
        my $opt = defined $decl->{mandatory} ? $decl->{optional} // 0 : scalar @defaulted;
        $cmin = $slurpy ? scalar @positional - $opt : $all - $opt;
        $cmax = $slurpy ? undef : $all;
        # PERL DIES ON ANOTHER ARITY: a call of a code value -- this closure,
        # maybe -- passing another count than it takes, or a list (a count
        # unknown here), is refused by name; the entry's check (a run-time
        # stop) is for what this cannot see.
        for my $k (grep { $_->operation eq 'Call' && ( ( $_->dispatch_kind // '' ) eq 'indirect' || ( $_->name // '' ) eq $name ) } _all_nodes( $b->{mop}, $b->{ret} ), $g->component) {
            my @a = grep { blessed($_) } $k->inputs->@*;
            shift @a if ( $k->dispatch_kind // '' ) eq 'indirect';   # (the code)
            out("a call of a code value that may be closure $name, of a count perl checks against its signature")
                if grep { _is_list($_) } @a or @a < $cmin or defined $cmax && @a > $cmax;
        }
        $list = 1;
    }
    out("closure $name reads \@_ other than T2 takes it") if $closure && !$list;
    # A CAPTURE USED BUT BY A CELL READ OR WRITE: B::SoN spells `$t += 1` on
    # one as Coerce(CellParam) + 1, with no write -- lowered, $t never changed
    # (0 for 16). Refused.
    out("closure $name uses a capture other than by reading or writing it (an op-assign)")
        if grep { my $p = $_; grep { blessed($_) && $_->operation !~ /\A(?:CellRead|CellWrite|MakeCell)\z/ } ( $p->consumers // [] )->@* }
           grep { $_->operation eq 'CellParam' } $g->component;
    out("sub $name captures a variable (a named sub's closure)") if !$closure
        && grep { $_->operation eq 'CellParam' } $g->component;
    # $_[N] READ ANYWHERE is the Nth argument: the binder (Builder/Args.pm) keeps one
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
    if ($sig && !$is_method && !$optional && !$sigclosure) {
        out("sub $name has an optional signature parameter")
            if $decl->{optional} || ( $decl->{mandatory} // scalar @reads ) != ( $slurpy ? @positional : @reads );
    }
    ( my $id = $name ) =~ s/\W+/_/g;
    # Two subs one name (a method call's bare name): the second numbered.
    $id .= '_' . scalar keys $b->{funcs}->%* if grep { $_->{name} eq "\@f_$id" } values +($b->{funcs} // {})->%*;
    $list = 1 if $is_method && defined $margs{slurpy};
    my $nargs = $is_method ? 1 + $margs{np} : $list ? 1 : scalar @reads;
    my $fn = $b->{funcs}{ refaddr($sub) } = { name => "\@f_$id", wrapper => "\@w_$id", nargs => $nargs,
        signature => $sig, list => $list, listret => $listret, list_copy => ( $ctxlist ? 1 : 0 ), closure => $closure, blocks => [] , minargs => ( $optional ? ( $decl->{mandatory} // 0 ) - $decl->{optional} : $slurpy && $sig ? scalar @positional : undef ),
        maxargs => ( $optional && !$slurpy ? $decl->{mandatory} // 0 : undef ),
        direct_only => ( $optional || $padded || $self_arg ? 1 : 0 ), self_arg => ( $self_arg ? 1 : 0 ), sig_min => $cmin, sig_max => $cmax,
        slurpy_sigil => ( $slurpy && $sig ? ( $slurpy->can('sigil') ? $slurpy->sigil // '@' : '@' ) : undef ) };
    # A SIGNATURE'S ARITY, checked by its wrapper (a method call's entry):
    # perl's die naming the sub where another count is passed.
    if (!$is_method && !$closure && $sig) {
        $fn->{arity} = $list ? [ $fn->{minargs} // scalar @positional, $fn->{maxargs} // -1 ] : [ $nargs, $nargs ];
        $fn->{pname} = $name;
        $b->{strs}{$name} //= scalar keys $b->{strs}->%*;
    }
    if ($is_method && $list) {   # (a slurpy method: at least its others, past its invocant)
        $fn->{arity} = [ $margs{slurpy}, -1, 1 ];
        $fn->{pname} = $name;
        $b->{strs}{$name} //= scalar keys $b->{strs}->%*;
    }
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
    local $b->{fresh_vars} = {};
    local $b->{fresh_pass};
    local $b->{memo} = {};
    local $b->{made} = {};
    local $b->{args} = $is_method ? { map { ( $_ => $argn[ $margs{$_} ] ) } grep { $_ ne 'np' && $_ ne 'slurpy' } keys %margs }
                                  : { ( map { ( refaddr( $reads[$_] ) => $argn[$_] ) } 0 .. $#reads ), ( map { ( refaddr( $_->[0] ) => $argn[ $_->[1] ] ) } @also ) };
    local $b->{self} = $is_method ? $argn[0] : undef;   # a field's object
    # (a closure of a method reading its fields: the object it is handed)
    if ($self_arg) { $b->{self} = Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Slot', attr => { index => -1 }); $b->{self}->set_name('%self') }
    local $b->{func_name} = $name;
    local $b->{cells} = $closure ? $o{cells} : undef;
    local $b->{env} = $closure ? do { my $e = Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Slot**', attr => { index => 1 }); $e->set_name('%env'); $e } : undef;
    local $b->{own_nodes} = [ $g->component ];
    local $b->{eval_at} = eval_regions_at( $b->{own_nodes}->@* );
    local $b->{evals} = [];
    local $b->{eval_opened} = {};
    local $b->{stmt};   # (the caller's statement is the caller's: exc_block)
    local $b->{in_func} = 1;
    local $b->{alias_strict};   # (the @_ a caller is building is not this sub's)
    local $b->{alias_writes};
    # A FORMAT's sub (B::SoN's __FORMAT__:<handle>), which `write` calls.
    local $b->{format_of} = $name =~ /__FORMAT__:(.+)\z/ ? $1 : undef;
    local $b->{ret} = $ret;
    local $b->{passed} = [ grep { $_->operation eq 'MemStart' } $g->component ];
    local $b->{readers};
    $b->index_readers($g->component);
    local $b->{depth} = 0;
    local $b->{lscope};   # (its own: 'top')
    local $b->{scope_in};
    local $b->{at_way};
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj|Exc)\z/ ? $start->inputs->[0]
               : out("no way back to Start in $name");
    }
    $b->new_block('entry');
    # THE CALLER'S CONTEXT, read first (a call in the body sets it).
    my $want = $b->emit(op => 'GetWant', type => 'i1');
    if ($is_method && $list) {
        # A SLURPY METHOD'S ARGUMENTS, from @_: $self its first, each other
        # parameter its place, the slurpy one a copy of the rest.
        my %at;
        for my $k (grep { !/\A(?:np|slurpy)\z/ } keys %margs) {
            $b->{args}{$k} = $at{ $margs{$k} } //= $b->emit(op => 'AGet', type => '%Slot',
                inputs => [ $argsarr, $b->emit(op => 'Const', type => 'i64', attr => { value => $margs{$k} }) ]);
        }
        $b->{self} = $at{0} //= $b->emit(op => 'AGet', type => '%Slot', inputs => [ $argsarr, $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ]);
        for my $p (grep { $_->operation eq 'Parameter' && ( $_->index // -1 ) == $margs{slurpy} } $g->component) {
            $b->{memo}{ refaddr($p) } = $b->args_rest($argsarr, $p->index + 1, $p->can('sigil') ? $p->sigil // '@' : '@');
        }
    }
    if ($slurpy || $optional || $sigclosure) {
        # A SIGNATURE'S ARITY: at least its positional parameters (perl dies
        # with fewer -- a run-time stop here, as a signature's wrapper's is).
        $b->emit(op => 'ArgsMin', type => 'void', inputs => [ $argsarr ], attr => { n => $cmin // $fn->{minargs} // scalar @positional }) if $sig;
        $b->emit(op => 'ArgsMax', type => 'void', inputs => [ $argsarr ], attr => { n => $cmax }) if $sig && defined $cmax;
        $b->emit(op => 'ArgsPairs', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional })
            if $sig && $slurpy && ( $slurpy->can('sigil') ? $slurpy->sigil // '' : '' ) eq '%';
        # ITS PARAMETERS, made here: each its argument, the slurpy one the rest.
        for my $p (grep { $_->operation eq 'Parameter' } $g->component) {
            my $sg = $p->can('sigil') ? $p->sigil // '$' : '$';
            my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $p->index });
            my $v = $sg eq '$'
                ? $b->emit(op => 'AGet', type => '%Slot', inputs => [ $argsarr, $ix ])
                : $b->args_rest($argsarr, $p->index, $sg);
            # (an optional one: its argument if passed, else its default)
            $v = $b->emit(op => 'Select', type => '%Slot', inputs => [
                $b->emit(op => 'Cmp', type => 'i1', inputs => [ $b->emit(op => 'ALen', type => 'i64', inputs => [$argsarr]), $ix ], attr => { op => 'gt' }),
                $v, $b->as( $b->value( $p->inputs->[0] ), '%Slot' ) ]) if $sg eq '$' && blessed( $p->inputs->[0] );
            $b->{memo}{ refaddr($p) } = $v;
        }
    }
    # `return g()` IS CALLED IN THE CALLER'S CONTEXT: it is handed on.
    my $tail = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && ( ( $ret->inputs->[0]->dispatch_kind // '' ) eq 'direct'
             # (a method's or a code value's in the caller's context: B::SoN
             # gives it no want. One folded from `my $c = $o->m; return $c`
             # has want=scalar: called so, its scalar returned)
             || ( $ret->inputs->[0]->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/
                && !defined( $ret->inputs->[0]->can('want') ? $ret->inputs->[0]->want : undef ) )
        ? $ret->inputs->[0] : undef;
    # A MERGE RETURNED, ONE WAY A CALL (`if ($x) { return g() } return 7`),
    # B::SoN's stamp a List: each way in the caller's context -- the call's
    # handed on, another's a list of it or it -- and the merge their list's
    # reference or scalar. (Stamped other, a merge of scalars: its value.)
    # (In a sub's list-context copy -- ctxlist -- the same, its caller's
    # context a list.)
    my $rphi = ( !$listret || $ctxlist && refaddr($ctxlist) == refaddr( $ret->inputs->[0] ) ) && !$tail && $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Phi'
        && ( $ret->inputs->[0]->stamp // '' ) =~ /\A(?:List|Array)\z/   # static type
        && !$ret->inputs->[0]->memory && blessed( $ret->inputs->[0]->region ) && $ret->inputs->[0]->region->operation eq 'Region'
        && ( grep { blessed($_) && $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'direct' } $ret->inputs->[0]->inputs->@* )
        ? $ret->inputs->[0] : undef;
    if ($rphi) {
        for my $w ($rphi->inputs->@*) {
            next if blessed($w) && $w->operation eq 'Call' && ( $w->dispatch_kind // '' ) eq 'direct';
            out('a merge returned whose way is a list or a merge') if !blessed($w) || _is_list($w) || $w->operation eq 'Phi';
        }
    }
    local $b->{ret_phi} = $rphi ? { refaddr($rphi) => $want } : undef;
    local $b->{ret_fn} = $fn;
    local $b->{tail} = $tail ? { call => refaddr($tail), want => $want }
                     : $rphi ? { calls => { map { ( refaddr($_) => 1 ) } grep { blessed($_) && $_->operation eq 'Call' } $rphi->inputs->@* }, want => $want }
                     : undef;
    $b->make_constant_arrays($g->component);
    local $b->{jumps} = {};   # this function's early exits
    local $b->{loopx};        # (a loop its caller is walking is not its)
    local $b->{rethrows_taken} = {};
    $b->walk($start);
    # (a way out B::SoN gave that T2 never took would skip its restores)
    out('a rethrow edge T2 never takes (a ' . $_->inputs->[0]->operation . ')')
        for grep { $b->{has_eval} && !$b->{rethrows_taken}{ refaddr($_) } }
            grep { $_->operation eq 'Exc' && grep { blessed($_) && $_->operation eq 'Unwind' && $_->rethrow } ( $_->consumers // [] )->@* } $g->component;
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
    if ($rphi) {
        # (each way made in the caller's context at its end: ret_way)
        $fn->{listret} = 1;
        $r = $b->as($b->value($rphi), '%Slot');
    }
    elsif ($hkv) {
        my $h = $b->hash_of( $hkv->inputs->[0] );
        my $l = $b->emit(op => $hkv->lists_a_hash eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
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
        out("sub $name returns a /g match") if $mret && ( $mret->flags // '' ) =~ /g/;
        my $la = $laret ? $b->{list_assigned}{ refaddr($laret) } // out('the value of a list assignment to scalars') : undef;
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $copy, $mret ? $b->array_of($mret) : $la ? $la->[1] : $b->as_list($v) ]);
        my $l = $b->emit(op => 'ARef', type => '%Slot', inputs => [$copy]);
        # (a list-context copy has no scalar reading: no call takes one)
        my $sv = $mret ? $b->as( $b->value($mret), '%Slot' )
               : $la ? $b->as( $la->[0], '%Slot' )
               : $arrret ? $b->as( $b->emit(op => 'ALen', type => 'i64', inputs => [ $b->array_of($arrret) ]), '%Slot' )
               : blessed( $ret->inputs->[1] ) ? $b->as($b->value( $ret->inputs->[1] ), '%Slot') : $b->emit(op => 'Undef', type => '%Slot');
        $r = $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $l, $sv ]);
    }
    elsif ($tail && ( $tail->dispatch_kind // '' ) ne 'direct') {
        # A TAIL CALL OF A METHOD OR A CODE VALUE: its wrapper gives, by the
        # context handed on, a list's reference or its scalar -- as a sub
        # returning a list does (`return $self->all`: a list of one for
        # perl's three, before).
        $fn->{listret} = 1;
        $r = $b->as($b->value($tail), '%Slot');
    }
    elsif ($tail && $b->is_glob_call($tail)) {
        # A TAIL CALL OF A SUB A GLOB IS GIVEN AT RUN TIME (glob_call): its
        # wrapper's, by the context handed on, as a method's.
        $fn->{listret} = 1;
        $r = $b->as($b->value($tail), '%Slot');
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


# ret_way($want, $way) -> one way into a merge a sub returns (ret_phi), in
# the caller's context $want: a call handed it on gives its list's
# reference or its scalar (a sub of one value: a list of it, or it); another
# value a list of it, or it.
sub ret_way {
    my ($b, $want, $w) = @_;
    my $one = sub ($v) {
        my $l = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'APush', type => 'void', inputs => [ $l, $v ]);
        return $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $b->emit(op => 'ARef', type => '%Slot', inputs => [$l]), $v ]);
    };
    if ( $w->operation eq 'Call' && ( $w->dispatch_kind // '' ) eq 'direct' ) {
        my $t = $w->target;
        my $cf = blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        my $r = $b->as($b->value($w), '%Slot');
        $cf //= blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        out('a merge returned with a call of no sub T2 made') unless $cf;
        # (of itself: whether it gives a list is known only once it is made)
        out('a merge returned with a call of the sub itself') if refaddr($cf) == refaddr( $b->{ret_fn} // 0 );
        return $cf->{listret} ? $r : $one->($r);
    }
    return $one->( $b->as($b->value($w), '%Slot') );
}

# IN-MEMORY HANDLES (perl's open on a reference): open(my $fh, "<", \"...")
# reads the string, open(my $fh, ">" or ">>", \my $buf) writes into $buf;
# DATA reads the program's __DATA__ text. A `my $fh` is a cell of this
# function holding the handle (undef until an open); it is read only as a
# handle -- any other use of it is refused where it is made. A file on disk
# is not T2's.
sub fh_cell {
    my ($b, $fh) = @_;
    out('a filehandle that is not a `my $fh` (or DATA)')
        unless blessed($fh) && $fh->operation eq 'PadAccess' && ( $fh->stamp // '' ) eq 'GlobRef' && ( $fh->sigil // '' ) eq '$';   # static type
    out('a `my $fh` shared with a sub') if $fh->can('shared') && $fh->shared;
    my $key = 'fh:' . $fh->symbol . '#' . ( $fh->can('targ') ? $fh->targ // '' : '' );
    return $b->{locs}{$key} //= $b->emit_entry(op => 'Alloca', type => '%Slot*', attr => { name => '$' . $fh->symbol });
}

# _opens_it($pad) -> the variable is read only as the target of an open.
sub _opens_it {
    my ($pad) = @_;
    my @u = grep { blessed($_) } ( $pad->consumers // [] )->@*;
    return @u && !grep { !( $_->operation eq 'Ref' && !grep { !( $_->operation eq 'Call' && ( $_->builtin_kind // '' ) eq 'opens' ) } grep { blessed($_) } ( $_->consumers // [] )->@* ) } @u;
}

# fh_handle($fh) -> the handle a filehandle operand names, where it is used.
sub fh_handle {
    my ($b, $fh) = @_;
    if ( blessed($fh) && $fh->operation eq 'Constant' && ( $fh->const_type // '' ) eq 'glob' && ( $fh->value // '' ) =~ /\A(?:main::)?DATA\z/ ) {
        my $text = $Chalk::IR::Serialize::JSON::DATA_SECTION // out('DATA in a program with no __DATA__ or __END__ text');
        return $b->emit(op => 'FhData', type => '%Slot', inputs => [ $b->const_str($text) ]);
    }
    return $b->emit(op => 'Load', type => '%Slot', inputs => [ $b->fh_cell($fh) ]);
}

# selects() -> the program selects a handle (select of one argument): a
# print to no handle goes to the one selected.
sub selects {
    my ($b) = @_;
    return $b->{selects} //= scalar grep { $_->operation eq 'Call' && ( $_->builtin_kind // '' ) eq 'selects_output' }
        _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
}

# _after_close($version, $fh, \@nodes) -> the memory version $version stands
# on the control chain after the close of the handle $fh (a `my $fh` opened
# once among @nodes): back along the chain from it, straight, the close is met.
sub _after_close {
    my ($ver, $fh, $nodes) = @_;
    my $sym = $fh->can('symbol') ? $fh->symbol // '' : '';
    my $is_fh = sub ($x) { blessed($x) && $x->operation eq 'PadAccess' && ( $x->symbol // '' ) eq $sym };
    my $opens = grep { $_->operation eq 'Call' && ( $_->builtin_kind // '' ) eq 'opens' && $is_fh->( $_->inputs->[0] ) } @$nodes;
    return 0 unless $opens == 1;
    my %been;
    for ( my $c = $ver; blessed($c) && !$been{ refaddr($c) }++; $c = $c->can('control_in') ? $c->control_in : undef ) {
        return 1 if $c->operation eq 'Call' && ( $c->builtin_kind // '' ) eq 'closes' && $is_fh->( $c->inputs->[0] );
    }
    return 0;
}

# io_value($Call) -> an operation on a handle, by what it does
# (builtin_kind): open, close, eof, readline, select of a handle, and
# four-argument select.
sub io_value {
    my ($b, $v) = @_;
    my $name = $v->name;
    my $kind = $v->builtin_kind // '';
    my @in = grep { blessed($_) } $v->inputs->@*;
    # AN OP ON A HANDLE B::SoN DOES NOT PLACE (a close whose value is read, not
    # on the chain): where it runs against the others is not known.
    out("a $name B::SoN does not place on the chain") if $kind ne 'waits_for_handles' && !$v->is_pinned;
    # (a handle's open, print and close write a variable behind the reads of it)
    $b->reads_before($_) for $b->{passed}->@*;
    if ($kind eq 'opens') {
        out('an open of other than three arguments') unless @in == 3;
        my ($fh, $mode, $to) = @in;
        my $m = $mode->operation eq 'Constant' ? $mode->value // '' : '';
        my $h;
        if ($m eq '<') {
            out('an open of a file (or of what is not a reference to a constant string)')
                unless $to->operation eq 'Constant' && ( $to->const_type // '' ) eq 'ref' && defined $to->value;
            $h = $b->emit(op => 'FhROpen', type => '%Slot', inputs => [ $b->const_str( $to->value ) ]);
        }
        elsif ($m eq '>' || $m eq '>>') {
            my $var = $to->operation eq 'Ref' ? $to->inputs->[0] : undef;
            out('an open for writing of a file (or of what is not a `my` scalar)')
                unless blessed($var) && $var->operation eq 'PadAccess' && ( $var->sigil // '' ) eq '$' && $var->is_location;
            # B::SoN versions no memory at a print to a handle: a read of the
            # variable before the close is one node with any read after the
            # open (a copy taken between two prints read what the last left).
            # Read only after a close, it is what the prints wrote: a read whose
            # memory version stands after the handle's close on the control
            # chain (the close itself, or a statement the chain reaches from
            # it), the handle opened once here.
            out('a variable a handle writes, read other than after a close')
                if ( $var->can('shared') && $var->shared )
                || grep { refaddr($_) != refaddr($var) && ( $_->symbol // '' ) eq $var->symbol && !_opens_it($_)
                          && !_after_close( $_->mem_in, $fh, $b->{own_nodes} ) }
                   grep { $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' } +($b->{own_nodes} // [])->@*;
            $h = $b->emit(op => 'FhWOpen', type => '%Slot', inputs => [ $b->location($var) ], attr => { trunc => $m eq '>' });
        }
        else { out('an open in a mode other than <, > or >>') }
        # A HANDLE REOPENED WHILE SELECTED: perl's select holds the glob (the
        # new handle), T2's the handle it was given (the old one).
        out('a handle opened again in a program that selects one')
            if $b->selects && 1 < grep { $_->operation eq 'Call' && ( $_->builtin_kind // '' ) eq 'opens'
                && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->symbol // '' ) eq ( $fh->symbol // '' ) } +($b->{own_nodes} // [])->@*;
        $b->emit(op => 'Store', type => 'void', inputs => [ $h, $b->fh_cell($fh) ]);
        return $b->emit(op => 'Const', type => 'i64', attr => { value => 1 });
    }
    if ($kind eq 'selects_output') {
        out('a select of other than one argument') unless @in == 1;
        my $x = $in[0];
        out('a select of undef (a `my $fh` never opened)') if $x->operation eq 'Constant' && !defined $x->value;
        my $used = $b->_value_read($v);
        return $b->emit(op => 'FhSelect', type => '%Slot', inputs => [ $b->fh_handle($x) ], attr => { used => $used })
            if $x->operation eq 'PadAccess' && ( $x->stamp // '' ) eq 'GlobRef';   # static type
        return $b->emit(op => 'SelectName', type => '%Slot', inputs => [ $b->as( $b->value($x), '%Slot' ) ], attr => { used => $used });
    }
    if ($kind eq 'waits_for_handles') {
        # select(undef, undef, undef, 0): no handles, no wait -- none ready.
        out('a four-argument select of handles or a wait') unless @in == 4
            && ( grep { $_->operation eq 'Constant' && !defined $_->value } @in[0 .. 2] ) == 3
            && $in[3]->operation eq 'Constant' && ( $in[3]->value // '' ) =~ /\A0+(?:\.0*)?\z/;
        return $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
    }
    out("a $name of no handle (of the last one read)") unless @in == 1;
    my $h = $b->fh_handle( $in[0] );
    return $b->emit(op => 'FhClose', type => 'i1', inputs => [$h]) if $kind eq 'closes';
    return $b->emit(op => 'FhEof', type => 'i1', inputs => [$h]) if $kind eq 'at_end';
    out("a $name T2 does not have") unless $kind eq 'reads_lines';   # (a handle's op the IR names that T2 has no emitter for)
    return $b->emit(op => 'FhReadlines', type => '%Array*', inputs => [$h]) if $b->type_of($v) eq '%Array*';
    return $b->emit(op => 'FhReadline', type => '%Slot', inputs => [$h]);
}

1;
