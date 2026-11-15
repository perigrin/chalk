# ABOUTME: The LLVM builder's arrays and hashes: `my` and package aggregates, references to
# ABOUTME: them, their elements, reads and stores (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

require Chalk::Impl;
use Scalar::Util qw(blessed refaddr);

# make_constant_arrays(@nodes): an array whose literal holds only constants
# (`my @a = (1, 2)`, `my @a`) is made in the entry block -- first made where it
# was first used, in a loop body it was made again each pass.
sub make_constant_arrays {
    my ($b, @nodes) = @_;
    for my $lit (grep { $_->operation eq 'ArrayLiteral' } @nodes) {
        next if $lit->is_pinned;   # a `my @a` pinned where it runs: made there
        next if $lit->stored_whole_into;   # a package array, read where it is read
        next if grep { !( blessed($_) && $_->operation eq 'Constant' ) } $lit->inputs->@*;
        $b->value($lit);
    }
    # A `my %h = (...)` of constants, or of @_, is made at entry too.
    for my $lit (grep { $_->operation eq 'HashLiteral' && ( $_->stamp // '' ) eq 'Hash' && !$_->is_pinned && !$_->stored_whole_into } @nodes) { # static type
        next if grep { !( blessed($_) && ( $_->operation =~ /\A(?:Constant|ArgsSource)\z/ || $b->{args}{ refaddr($_) } ) ) } $lit->inputs->@*;
        $b->value($lit);
    }
}

# hash_value($v, $op) -> the T2 node of a hash reference, or of an element
# read through one; undef for what is not.
sub hash_value {
    my ($b, $v, $op) = @_;
    my @in = $v->inputs->@*;
    if ($op eq 'HashLiteral') {
        my $st = $v->stamp // ''; # static type
        out('a hash that is not a {...} or a `my %h`') unless $st =~ /\A(?:HashRef|Hash)\z/;
        # (one in a field's default is made where the object is: field_default)
        out('a {...} not made where it runs') if $st eq 'HashRef' && !$v->is_pinned && !$b->{in_field_default};
        # A `my %h` NOT MADE AT ENTRY, needed in an arm or a loop body, would be
        # made there -- again each pass, and gone after.
        out('a hash first made in an arm or a loop body') if $st eq 'Hash' && $b->{depth} && !$v->is_pinned;
        my $h = $b->emit(op => 'HNew', type => '%Slot');
        if (grep { _is_list($_) } @in) {   # `my %o = @_`, `{ %$r, k => 1 }`: pairs of a list
            my $l = $b->emit(op => 'NewArray', type => '%Array*');
            for my $e (@in) {
                if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $l, $b->array_of($e) ]) }
                else { $b->emit(op => 'APush', type => 'void', inputs => [ $l, $b->as($b->value($e), '%Slot') ]) }
            }
            $b->emit(op => 'HFromArray', type => 'void', inputs => [ $h, $l ]);
            return $h;
        }
        out('a {...} of an odd list') if @in % 2;
        for (my $i = 0; $i < @in; $i += 2) {
            out('a list in a {...}') if grep { _is_list($_) } @in[ $i, $i + 1 ]; # static type
            $b->emit(op => 'HSet', type => 'void',
                inputs => [ $h, $b->as($b->value($in[$i]), '%Str'), $b->as($b->value($in[ $i + 1 ]), '%Slot') ]);
        }
        return $h;
    }
    return $b->hash_var($v) if $v->is_my_hash;
    # %$r READ WHOLE AS A LIST: its pairs, key then value, as they are where
    # it is read (a read through a reference, ordered as one). Taken as a
    # scalar it is refused; its keys, count and elements go to the hash itself.
    if ($op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '%' && !$v->copy) {
        $b->list_only($v, 'a hash read whole', hash_ok => 1);
        return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($v) ]);
    }
    # `my %p = %$r` (B::SoN's copy): a new hash of r's pairs as they are here
    # -- a later store through r does not reach it. (r no hash: a stop.)
    if ($op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '%' && $v->copy) {
        my $h = $b->emit(op => 'HNew', type => '%Slot');
        my $pairs = $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->as($b->value($in[0]), '%Slot') ]);
        $b->emit(op => 'HFromArray', type => 'void', inputs => [ $h, $pairs ]);
        return $h;
    }
    my $kind = $v->can('kind') ? $v->kind // '' : '';
    if ($op =~ /\A(?:Subscript|Exists|Delete)\z/ && $kind eq 'hash') {
        # (%INC's value is a path, perl's: only its truth is the program's)
        out( 'a value of %' . $in[0]->symbol . ' read as other than a truth (it is perl\'s, not chalk\'s)' )
            if $op eq 'Subscript' && $in[0] isa Chalk::IR::Node && $in[0]->operation eq 'EntryDef' && $in[0]->values_are_only_truths
            && !$b->read_as_a_truth($v);
        my $h = $b->hash_of($in[0]);
        my $k = $b->as($b->value($in[1]), '%Str');
        return $b->emit(op => 'HGet', type => '%Slot', inputs => [ $h, $k ]) if $op eq 'Subscript';
        return $b->emit(op => 'HExists', type => 'i1', inputs => [ $h, $k ]) if $op eq 'Exists';
        return $b->emit(op => 'HDelete', type => '%Slot', inputs => [ $h, $k ]);
    }
    # AN ARRAY ELEMENT EXISTS where its index is in the array and perl made it:
    # not a hole (t2_aexists).
    if ( $op eq 'Exists' && $kind eq 'array' ) {
        return $b->emit(op => 'AExists', type => 'i1', inputs => [ $b->array_of( $in[0] ), $b->as( $b->value( $in[1] ), 'i64' ) ]);
    }
    # caller: the site of the call this sub is in, N frames up (the stack
    # each call pushes). A package in scalar context; (package, file, line).
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'caller') {
        my ($n) = grep { blessed($_) && !( $v->can('memory_input') && $v->memory_input && refaddr($_) == refaddr( $v->memory_input ) ) } @in;
        my $depth = $n ? $b->as( $b->value($n), 'i64' ) : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        return $b->emit(op => 'CallerPkg', type => '%Slot', inputs => [$depth]) if ( $v->stamp // '' ) eq 'Scalar';   # static type
        # caller(N) GIVES ELEVEN; T2 has the first three. Lowered only where
        # what takes the list reads no more (a list assign of up to three).
        out('a caller(N) read past its third value') if $n && grep {
            !( blessed($_) && $_->operation eq 'Assign' && ( $_->can('targets') ? $_->targets // 99 : 99 ) <= 3 )
        } ( $v->consumers // [] )->@*;
        return $b->emit(op => 'Caller', type => '%Array*', inputs => [$depth]);
    }
    if ($op eq 'Call' && $v->lists_a_hash) {
        # %$r READ WHOLE: the hash the reference holds; an undefined one is an
        # empty hash here, as in perl (a store through it would autovivify: not this).
        my $h = blessed($in[0]) && $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%'
            ? $b->emit(op => 'HDerefR', type => '%Slot', inputs => [ $b->as($b->value( $in[0]->inputs->[0] ), '%Slot') ])
            : $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]) if $v->lists_a_hash eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar';
        return $b->emit(op => $v->lists_a_hash eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
    }
    # each %h IN A LIST: its next key and value, or none (and it starts over).
    # In scalar context (the key alone) not T2's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'each') {
        out('an each in scalar context') unless ( $v->can('want') ? $v->want // '' : '' ) eq 'list';
        out('an each of what is not a hash') unless $in[0] isa Chalk::IR::Node && $in[0]->is_named_hash;
        # keys AND values START A HASH'S each OVER, but B::SoN places neither
        # (a value made where it is used, or never): where they run against an
        # each is not known. Refused where the program has one.
        out('an each in a program with a keys or values (which reset it, B::SoN places them nowhere)')
            if grep { $_->operation eq 'Call' && $_->resets_iterator } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        return $b->emit(op => 'Each', type => '%Array*', inputs => [ $b->hash_of($in[0]) ]);
    }
    # sort (by string or by number, either way) and reverse, of a list: a new
    # list. A sort with its own comparator is not T2's yet.
    if ($op eq 'Call' && $v->reorders_list
            && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/) {   # static type
        # A SORT WITH ITS OWN COMPARATOR (a block, a named sub): a function of
        # no arguments, called for each pair with $a and $b -- the sort
        # package's -- set to it; its number orders the pair.
        my $by = $v->name eq 'sort' && ( ( $v->can('sort_cmp_body') && $v->sort_cmp_body ) || !( $v->can('sort_cmp') && defined $v->sort_cmp ) );
        my $cmp_fn;
        my (%cmp_env, $cmp_envpads);
        if ($by) {
            my $sub = $v->can('sort_cmp_sub') ? $v->sort_cmp_sub : undef;
            out('a sort comparator with no body') unless blessed($sub) && $sub->can('graph') && $sub->graph;
            # (one with an effect -- a die, a print, a store, a call -- is called on
            # perl's pairs in perl's order: t2_asort_by runs perl's merge sort)
            # A SUB'S VARIABLES ITS COMPARATOR READS (B::SoN's shared, not the
            # file's): the sorting sub's own, reached through an environment the
            # sort sets for the comparator's calls (@t2_cmp_env), by position.
            my (%idx, @envpad);
            for my $p (grep { $_->operation eq 'PadAccess' && $_->can('shared') && $_->shared && !( $_->can('file') && $_->file ) }
                       $sub->graph->component) {
                my $k = ( $p->sigil // '$' ) . $p->name . '#' . ( $p->can('targ') ? $p->targ // '' : '' );
                $idx{$k} //= do { push @envpad, $p; $#envpad };
                $cmp_env{ refaddr($p) } = $idx{$k};
            }
            $cmp_fn = do { local $b->{cmp_env} = \%cmp_env; $b->func($sub, $v->sort_cmp_body // 'sort comparator') };
            $cmp_envpads = \@envpad;
            out('a sort comparator reading @_') if $cmp_fn->{list} || $cmp_fn->{nargs};
        }
        my @l = @in;
        pop @l if $v->can('memory_input') && $v->memory_input;
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (grep { blessed($_) } @l) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($e), '%Slot') ]) }
        }
        return $b->emit(op => 'ARev', type => '%Array*', inputs => [$arr]) if $v->name eq 'reverse';
        if ($cmp_fn) {
            my $pk = ( $v->can('sort_package') ? $v->sort_package : undef ) // 'main';
            $b->hash_reads_settled('a sort comparator');
            my $env = $b->emit(op => 'NewArray', type => '%Array*');
            for my $p (+($cmp_envpads // [])->@*) {
                my $sg = $p->sigil // '$';
                my $e = $sg eq '$' ? $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($p) ])
                      : $sg eq '%' ? $b->hash_var($p)
                      : $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->array_var($p) ]);
                $b->emit(op => 'APush', type => 'void', inputs => [ $env, $e ]);
            }
            return $b->emit_call(op => 'ASortBy', type => '%Array*', inputs => [ $arr, $env ],
                attr => { fn => $cmp_fn->{name}, ga => $b->global_named("${pk}::a"), gb => $b->global_named("${pk}::b") });
        }
        return $b->emit(op => 'ASort', type => '%Array*', inputs => [$arr],
            attr => { num => ( $v->sort_cmp eq 'numeric' ? 1 : 0 ), desc => ( ( $v->can('sort_order') ? $v->sort_order // '' : '' ) eq 'descending' ? 1 : 0 ) });
    }
    return undef;
}

# pkg_agg($n): THE ONE AGGREGATE a global holds, made at its first use from
# any function. A whole store refills it in place, so its pointer stands.
sub pkg_agg {
    my ($b, $n) = @_;
    my $h = $n->sigil eq '%';
    my $name = _pkg_agg_name($n);
    my %op = (op => $h ? 'GHash' : 'GArray', type => $h ? '%Slot' : '%Array*', attr => { global => $b->global_named($name) });
    # ONE A `local` SWAPS is read where it stands: which aggregate the global
    # holds there is the swap's, before it and after its restore the old one.
    return $b->emit(%op) if $b->swapped->{$name};
    return $b->{locs}{$name} //= $b->emit_entry(%op);
}

# special_key($EntryDef) -> the special container's own name: %SIG, %INC, %main::.
sub special_key { my ($n) = @_; return $n->sigil . $n->symbol }

# special_hash($EntryDef) -> the %Slot of one of perl's special hashes (%SIG,
# a stash): held in a global, its metaobject a MOP object installed at
# start-up (special_startup).
sub special_hash {
    my ($b, $n) = @_;
    my $class = $n->metaobject_class;
    out("a container whose metaobject, $class, is not linked in") unless $b->{mop} && $b->{mop}->for_class($class);
    my $key = special_key($n);
    return $b->{locs}{"special::$key"} //= $b->emit_entry(op => 'GHash', type => '%Slot',
        attr => { global => $b->global_named( ( defined $n->metaobject_package ? 'stash::' : 'pkghash::main::' ) . $n->symbol ) });
}

# special_containers -> { %SIG / %INC / %main:: => an EntryDef of it } for each
# of perl's special containers the program uses (a MOP object its metaobject).
sub special_containers {
    my ($b) = @_;
    return $b->{special} //= { map { ( special_key($_) => $_ ) }
        grep { $_->operation eq 'EntryDef' && $_->metaobject_class } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) };
}

# impl_global($EntryDef) -> the global its metaobject is held in (a stash's by
# its package; %SIG's and %INC's by their class, one each).
sub impl_global {
    my ($b, $n) = @_;
    return $b->global_named( 'impl::' . ( defined $n->metaobject_package ? special_key($n) : $n->metaobject_class ) );
}

# special_classes -> { class => 1 } of the metaobjects' classes.
sub special_classes {
    my ($b) = @_;
    return { map { ( $_->metaobject_class => 1 ) } values $b->special_containers->%* };
}

# const_data($perl) -> a %Slot of a constant structure the builder holds (a
# hash's or an array's reference, a string, an integer), made where it stands.
sub const_data {
    my ($b, $d) = @_;
    if (ref $d eq 'HASH') {
        my $h = $b->emit(op => 'HNew', type => '%Slot');
        for my $k (sort keys %$d) {
            $b->emit(op => 'HSet', type => 'void', inputs => [ $h, $b->const_str($k), $b->const_data( $d->{$k} ) ]);
        }
        return $h;
    }
    if (ref $d eq 'ARRAY') {
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->const_data($_) ]) for @$d;
        return $b->emit(op => 'ARef', type => '%Slot', inputs => [$a]);
    }
    out('a constant structure holding a reference of another kind') if ref $d;
    return $b->emit(op => 'Undef', type => '%Slot') unless defined $d;
    return $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => $d }), '%Slot' ) if $d =~ /\A-?[0-9]{1,18}\z/;
    return $b->as( $b->const_str($d), '%Slot' );
}

# special_startup: before the program's first statement, each special
# container it uses gets its metaobject. A stash's is its package's
# Chalk::MOP::Class -- made as `new(name => ..., mop => undef)` and given the
# symbols the compiler's Class for that package holds (the instance carried
# from the compile into the run); another's an instance of its Impl class
# (new, looked up as a method call is). %SIG's hash is the handler table.
sub special_startup {
    my ($b) = @_;
    my $sp = $b->special_containers;
    # (perl's own warnings reach a __WARN__ handler; chalk raises none)
    if ( $sp->{'%SIG'} and my $why = Chalk::Impl::perl_may_warn( $b->{root_ret} // $b->{ret}, _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) ) ) {
        out("%SIG where perl may raise warnings of its own ($why), which chalk does not raise");
    }
    for my $key (sort keys %$sp) {
        my $n = $sp->{$key};
        my $class = $n->metaobject_class;
        my $h = $b->special_hash($n);
        my $o;
        if ( defined( my $pkg = $n->metaobject_package ) ) {
            # (the symbols are the compile's: a program that may change its stash
            # while it runs -- the loader says how -- would read them stale)
            out("a stash where the program may change it at run time ($Chalk::IR::Serialize::JSON::STASH_CHANGES)")
                if defined $Chalk::IR::Serialize::JSON::STASH_CHANGES;
            my $leaf = $b->{mop}->for_class($class) // out("a stash whose metaobject, $class, is not linked in");
            my %arg = ( name => $b->as( $b->const_str($pkg), '%Slot' ), mop => $b->emit(op => 'Undef', type => '%Slot') );
            $o = $b->construct_with( $leaf, [ 'name', 'mop' ], sub ($p) { $arg{$p} } );
            my $desc = $b->{mop}->for_class($pkg);
            if ( $desc && $desc->knows_symbols ) {
                my %table = map { ( $_ => $desc->symbol($_) ) } $desc->symbol_names;
                $b->method_by_name( $o, 'declare_symbols', $b->const_data( \%table ), $b->const_data( [ $desc->symbols_unknown ] ) );
            }
        }
        else {
            my $cls = $b->as( $b->const_str($class), '%Slot' );
            my $arr = $b->emit(op => 'NewArray', type => '%Array*');
            $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $cls ]);
            # (the registry new is made with: %INC's)
            if ($n->symbol eq 'INC') {
                my ($whole, @keys) = $b->inc_registry;
                $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => $whole }), '%Slot' ) ]);
                $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as( $b->const_str($_), '%Slot' ) ]) for @keys;
            }
            my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => 0 },
                inputs => [ $cls, $b->const_str('new'), $b->const_str(" at chalk's start-up.\n"), $b->const_str('') ]);
            $o = $b->emit(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ]);
        }
        $b->emit(op => 'MopHash', type => 'void', inputs => [ $h, $o ]);
        $b->emit(op => 'GStore', type => 'void', inputs => [$o], attr => { global => $b->impl_global($n) });
        $b->emit(op => 'SigTable', type => 'void', inputs => [$h]) if $n->symbol eq 'SIG';
    }
}

# method_by_name($obj, $method, @args) -> a call of $obj's method by name (the
# run-time MOP's lookup), its arguments %Slots.
sub method_by_name {
    my ($b, $o, $m, @args) = @_;
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) for $o, @args;
    my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => 0 },
        inputs => [ $o, $b->const_str($m), $b->const_str(" at chalk's start-up.\n"), $b->const_str('') ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ]);
}

# read_as_a_truth($n) -> true where every node that takes $n's value takes
# only its truth: a ?:'s choice, an if's, a not, a defined, an &&'s left
# (what it gives back where $n is true is its right).
sub read_as_a_truth {
    my ($b, $n) = @_;
    for my $u (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        my @in = $u->inputs->@*;
        my $m = $u->memory_operand;
        my @pos = grep { blessed( $in[$_] ) && refaddr( $in[$_] ) == refaddr($n) && !( blessed($m) && refaddr($m) == refaddr($n) ) } 0 .. $#in;
        next unless @pos;
        my $op = $u->operation;
        next if $op eq 'TernaryExpr' && !grep { $_ != 0 } @pos;
        next if $op eq 'And' && !grep { $_ != 0 } @pos;
        next if $op =~ /\A(?:If|Not|Defined)\z/;
        return 0;
    }
    return 1;
}

# impl_call($key, $method, @args) -> a call of a method of a special
# container's metaobject (the instance start-up made: %INC's), by name.
sub impl_call {
    my ($b, $key, $m, @args) = @_;
    my $n = $b->special_containers->{$key} // out("a call of the metaobject of $key, which the program does not use");
    my $class = $n->metaobject_class;
    my $o = $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->impl_global($n) });
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) for $o, @args;
    my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => 0 },
        inputs => [ $o, $b->const_str($m), $b->const_str(" at chalk's $class.\n"), $b->const_str('') ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ]);
}

# inc_registry -> (whole, keys): the module registry as the program starts --
# each module a `use` loaded, and, where no require may load another at run
# time, each B::SoN followed (and what those loaded in turn). Whole where the
# program loads only modules that load no other (perl's %INC starts empty).
sub inc_registry {
    my ($b) = @_;
    my %used = map { ( Chalk::Impl::inc_key($_) => 1 ) } keys %Chalk::IR::Serialize::JSON::USED_MODULES;
    my @req = map {
        my ($f) = grep { blessed($_) && $_->operation eq 'Constant' } $_->inputs->@*;
        $f ? $f->value // '' : '';
    } grep { $_->operation eq 'Call' && $_->is_builtin && ( $_->name // '' ) eq 'require' } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
    my $late = grep { !Chalk::Impl::is_built_in($_) } @req;
    my %k = %used;
    unless ($late) { $k{ Chalk::Impl::inc_key($_) } = 1 for keys %Chalk::IR::Serialize::JSON::FOLLOWED }
    my $whole = !%Chalk::IR::Serialize::JSON::FOLLOWED && !grep { !Chalk::Impl::loads_no_other($_) } keys %used, @req;
    return ( $whole ? 1 : 0, sort keys %k );
}

# _pkg_agg_name($n): the name of the global a package aggregate is held in
# (T2's: a hash's apart from an array's of one name).
sub _pkg_agg_name {
    my ($n) = @_;
    return ( $n->sigil eq '%' ? 'pkghash::' : 'pkgarr::' ) . $n->qualified_name;
}

# swapped -> { name => 1 } of the package aggregates a `local` swaps anywhere.
sub swapped {
    my ($b) = @_;
    return $b->{swapped} //= { map { ( _pkg_agg_name( $_->inputs->[0] ) => 1 ) }
        grep { $_->operation eq 'EntryWrite' && $_->binds && ( $_->inputs->[0] isa Chalk::IR::Node && $_->inputs->[0]->is_package_aggregate ) } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) };
}

sub hash_var {
    my ($b, $pad) = @_;
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) { return $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i }) }
    # A FILE'S HASH (shared with a sub, a sort block): one, in a global, made
    # at its first use from any function.
    return $b->{locs}{ '%file#' . $pad->symbol } //= $b->emit_entry(op => 'GHash', type => '%Slot', attr => { global => $b->global_named( 'my::%' . $pad->symbol ) })
        if $pad->can('file') && $pad->file;
    return $b->{locs}{ '%cell#' . $pad->name } //= $b->captured($pad)
        if $b->{env} && defined( ( $b->{cells} // {} )->{ $pad->name } );
    out('a hash a closure shares') if $pad->can('shared') && $pad->shared && !$b->_own_shared($pad);
    my $key = '%' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        my $h = Chalk::Target::LLVM::Node::_n(op => 'HNew', type => '%Slot');
        unshift $b->{blocks}[0]{nodes}->@*, $h;
        $h;
    };
}

# hash_of($n) -> the %Slot of the hash a hash element, exists, delete or keys
# is of: a `my %h`, or the reference a scalar holds (`$h->{k}`). A package
# hash (%ENV, %main::h) and one through an element (perl makes it) are not.
sub hash_of {
    my ($b, $n) = @_;
    # A SLURPY HASH PARAMETER: its hash, made at the sub's entry (args_rest).
    return $b->{memo}{ refaddr($n) } if blessed($n) && $n->operation eq 'Parameter' && $b->{memo}{ refaddr($n) };
    return $b->value($n) if $n isa Chalk::IR::Node && ( $n->is_named_hash || $n->is_package_aggregate && $n->sigil eq '%' );
    return $b->value($n) if $n isa Chalk::IR::Node && $n->operation eq 'EntryDef' && $n->metaobject_class;   # %SIG
    if ($n->operation eq 'FieldAccess') {   # a hash field: its hash
        my (undef, $sg) = $b->field_of($n);
        return $b->value($n) if $sg eq '%';
    }
    # %$r: the hash r refers to; `my %p = %$r` (B::SoN's copy) a hash of its
    # own, made where it is first read (its version's reads keep it in order).
    if ($n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%') {
        return $b->value($n) if $n->copy;
        return $b->as($b->value( $n->inputs->[0] ), '%Slot');
    }
    # THROUGH AN ELEMENT (`$h{x}{y}`): the reference the element holds. A deref
    # for a write B::SoN spells as the element made a hash first (`//= {}`).
    out('a hash element of a named hash') if ( $n->can('sigil') ? $n->sigil // '' : '' ) eq '%'
        || $n->operation eq 'EntryDef' && !$n->is_package_scalar   # a package hash by name: $ENV{K} (not `$a->{k}`: a reference)
        || $n->operation eq 'Constant';
    return $b->as($b->value($n), '%Slot');
}

# array_value($v, $op) -> the T2 node of an array, or of a read of one; undef
# for what is not.
sub array_value {
    my ($b, $v, $op) = @_;
    my @in = $v->inputs->@*;
    if ($op eq 'ArrayLiteral') {
        # ONE NOT MADE AT ENTRY, needed in an arm or a loop body, would be made
        # there -- again each pass, and gone after.
        out('an array first made in an arm or a loop body') if $b->{depth} && !$v->is_pinned;
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@in) {
            # A LIST IN IT is flattened: its elements appended (`(keys %h)`, `(@a, 4)`).
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $b->array_of($e) ]); next }
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($e), '%Slot') ]);
        }
        return ( $v->stamp // '' ) eq 'ArrayRef' ? $b->emit(op => 'ARef', type => '%Slot', inputs => [$a]) : $a; # static type
    }
    if ($op eq 'Ref') {
        # \@a: a reference to the array itself (one array, two names).
        my $t = $in[0];
        # \&name: a code value of the named sub.
        return $b->code_ref($t) if blessed($t) && $t->operation eq 'Constant' && ( $t->const_type // '' ) eq 'code';
        # \$x: a reference to the variable itself, kept on the heap (tag 9).
        # (NOT IN A LOOP BODY OR AN ARM: a `my` there is a new variable each time,
        # and the one cell made at entry would be all of them -- `2,2` for perl's `1,2`)
        out('a reference to a scalar in a loop body or an arm') if $b->{depth}
            && blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$';
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($t) ])
            if blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$' && $t->is_location;
        # \%h: a named hash IS its reference here (a %Slot of tag 5), one hash, two names.
        return $b->value($t) if blessed($t) && ( $t->is_named_hash || $t->is_package_aggregate && $t->sigil eq '%' ) && ( $v->stamp // '' ) eq 'HashRef';   # static type
        out('a reference to a glob read other than by ref (its address and slots are the stash\'s)')
            if blessed($t) && $t->operation eq 'Constant' && ( $t->const_type // '' ) eq 'glob';
        out('a reference to what is not an array') unless blessed($t)
            && ( $t->operation eq 'ArrayLiteral' && ( $t->stamp // '' ) eq 'Array' || $t->is_array_deref || $t->is_my_array || $t->is_argv
                 || $t->operation eq 'Phi' && $b->type_of($t) eq '%Array*'   # a list a loop builds (`my @c = map ...`), a merge of an array's
                 || $t->is_package_aggregate && $t->sigil eq '@' ) # static
            && ( $v->stamp // '' ) eq 'ArrayRef';   # \(@a) is a reference to each element type
        return $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->array_of($t) ]);
    }
    # A SLICE READ (`@a[1, 2]`, `@h{qw(a b)}`, `$r->@[...]`): a new list of
    # the elements its indices name, in their order -- undef where there is
    # none, as perl's. One perl would alias (passed to a sub, referenced) is
    # not this copy.
    if ($op eq 'Slice') {
        $b->list_only($v, 'a slice');
        out('a slice a sub or a reference would alias') if grep {
            $_->operation eq 'Ref' || $_->operation eq 'Call' && $_->is_sub_call
        } grep { my $u = $_; blessed($u) && grep { blessed($_) && refaddr($_) == refaddr($v) } $u->inputs->@* } ( $v->consumers // [] )->@*;
        my @ix = grep { blessed($_) } @in;
        my $src = pop @ix;
        my $list = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@ix) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
        }
        my $kind = $v->kind // '';
        return $b->emit(op => 'HSlice', type => '%Array*', inputs => [ $b->hash_of($src), $list ]) if $kind eq 'hash';
        out("a slice of kind $kind") unless $kind eq 'array';
        my $arr = do { local $b->{elem_read} = 1; $b->array_of($src) };   # (as an element read: through undef, undef)
        return $b->emit(op => 'ASlice', type => '%Array*', inputs => [ $arr, $list ]);
    }
    # A RANGE OF NUMBERS (`1 .. $n`: a bound is a number): a new list of the
    # integers from one bound to the other. A range of strings (perl's magic
    # increment, where neither bound is a number) is not T2's yet.
    if ($op eq 'Range') {
        $b->list_only($v, 'a range');
        # (a bound as it is, not as B::SoN coerced it: it numifies both, the
        # strings of `"az" .. "bb"` too)
        my ($lo, $hi) = map { my $x = $_; $x = $x->inputs->[0] while blessed($x) && $x->operation eq 'Coerce'; $x } @in;
        out('a range of strings') unless grep { $b->type_of($_) =~ /\A(?:i64|double)\z/ } $lo, $hi;
        return $b->emit(op => 'ARange', type => '%Array*', inputs => [ map { $b->as($b->value($_), 'i64') } $lo, $hi ]);
    }
    if ($op eq 'ListAppend') {
        # map's and grep's list, built a pass at a time: the value (a list,
        # flattened) appended -- by grep only where its condition held.
        my ($acc, $x, $cond) = @in;
        my $arr = $b->array_of($acc);
        my $c = $v->can('collector') ? $v->collector // '' : '';
        if ($c eq 'grep') {
            $b->emit(op => 'APushIf', type => 'void', inputs => [ $arr, $b->as($b->value($x), '%Slot'), $b->truth($b->value($cond)) ]);
        }
        # (map's: each value its block yields, in order -- `map { $k => $v }`
        # is [list so far, $k, $v])
        elsif ($c eq 'map') {
            for my $y (grep { blessed($_) } @in[ 1 .. $#in ]) {
                if (_is_list($y)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($y) ]) }
                else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($y), '%Slot') ]) }
            }
        }
        else { out("a list collector $c") }
        return $arr;
    }
    if ($v->is_array_deref) {
        # `my @p = @$r` IS A COPY (B::SoN's copy): its own array, of the
        # elements as they are here.
        return $b->array_of($in[0]) unless $v->can('copy') && $v->copy;
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $b->array_of($in[0]) ]);
        return $a;
    }
    return $b->array_var($v) if $v->is_my_array;
    return $b->emit(op => 'Argv', type => '%Array*') if $v->is_argv;
    return $b->{argsarr} // out('@_ outside a sub taking it as a list') if $op eq 'ArgsSource';
    # A HASH COUNTED is its keys (perl 5.26+), not its pairs flattened (4 for 2).
    if ($op eq 'Count' && blessed($in[0]) && ( $in[0]->is_named_hash || $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%' || $in[0]->operation eq 'FieldAccess' && ( $b->field_of($in[0]) )[1] eq '%' )) {
        my $h = $in[0]->operation eq 'PostfixDeref' ? $b->hash_of($in[0]->inputs->[0]) : $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]);
    }
    return $b->emit(op => 'ALen', type => 'i64', inputs => [ $b->array_of($in[0]) ]) if $op eq 'Count';
    if ($op eq 'Subscript') {
        out('a hash element') unless ( $v->can('kind') ? $v->kind // 'array' : 'array' ) eq 'array';
        my $arr = do { local $b->{elem_read} = 1; $b->array_of($in[0]) };   # (an element read: through undef it is undef)
        return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->as($b->value($in[1]), 'i64') ]);
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin') {
        my $name = $v->name // '';
        if ($v->is_tie_builtin) {
            # (a tie's methods may die, and nothing after them looks: not T2's in a program with an eval)
            out("a $name in a program with an eval") if $b->{has_eval};
            my @args = @in;
            pop @args if $v->can('memory_input') && $v->memory_input;
            my ($c, $cls, @rest) = @args;
            my $sig = blessed($c) && $c->can('sigil') && defined $c->sigil ? $c->sigil
                : blessed($c) && $c->operation eq 'ArrayLiteral' ? '@' : blessed($c) && $c->operation eq 'HashLiteral' ? '%' : '';
            out("a $name of a scalar") unless $sig =~ /\A[\@%]\z/;
            my $h = $sig eq '%';
            my $box = $h ? $b->hash_of($c) : $b->array_of($c);
            if ($name eq 'tied') { return $b->emit(op => $h ? 'TiedH' : 'TiedA', type => '%Slot', inputs => [$box]) }
            $b->hash_reads_settled("a $name");
            if ($name eq 'untie') {
                $b->emit(op => $h ? 'UntieH' : 'UntieA', type => 'void', inputs => [$box]);
                return $b->as($b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), '%Slot');
            }
            my $r = $b->emit(op => 'NewArray', type => '%Array*');
            for my $e (@rest) {
                if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $r, $b->array_of($e) ]) }
                else { $b->emit(op => 'APush', type => 'void', inputs => [ $r, $b->as($b->value($e), '%Slot') ]) }
            }
            return $b->emit(op => $h ? 'TieHash' : 'TieArray', type => '%Slot', inputs => [ $box, $b->as($b->value($cls), '%Slot'), $r ]);
        }
        # unpack WITH A CONSTANT C TEMPLATE (`C`, `C3`, `C*`), in a list: the
        # string's bytes, each a number. Another template, or scalar context
        # (its first value alone), is not T2's; nor a string past ASCII (perl's
        # C is of characters, T2's strings are bytes).
        if ($name eq 'unpack') {
            $b->list_only($v, 'an unpack');
            my @a = grep { blessed($_) && !$_->is_memory_version } @in;
            out('an unpack of other than a template and one string') unless @a == 2;
            my $t = $a[0];
            my ($n) = $t->operation eq 'Constant' && defined $t->value ? $t->value =~ /\AC(\d+|\*)?\z/ : ();
            out('an unpack template other than a constant C, Cn or C*')
                unless $t->operation eq 'Constant' && ( $t->value // '' ) =~ /\AC(?:\d+|\*)?\z/;
            $b->{past_ascii} //= scalar grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'string' && ( $_->value // '' ) =~ /[^\x00-\x7f]/ }
                _all_nodes($b->{mop}, $b->{ret});
            out('an unpack where a string goes past ASCII') if $b->{past_ascii};
            $n = !defined $n ? 1 : $n eq '*' ? -1 : $n;
            return $b->emit(op => 'UnpackC', type => '%Array*', inputs => [ $b->as($b->value($a[1]), '%Str') ], attr => { n => $n });
        }
        # glob PATTERN (`<*.x>`), in a list: the files it matches (t2_glob). In
        # scalar context glob is an iterator: not T2's; nor several patterns.
        if ($name eq 'glob') {
            $b->list_only($v, 'a glob');
            my @a = grep { blessed($_) && !$_->is_memory_version } @in;
            out('a glob of other than one pattern') unless @a == 1;
            my $lit = $a[0];
            $lit = $lit->inputs->[0] while $lit->operation eq 'Coerce';
            out('a glob pattern with whitespace (several patterns to perl)') if $lit->operation eq 'Constant' && ( $lit->value // '' ) =~ /\s/;
            out('a glob pattern with a brace (perl keeps its alternatives in order)') if $lit->operation eq 'Constant' && ( $lit->value // '' ) =~ /\{/;
            return $b->emit(op => 'Glob', type => '%Array*', inputs => [ $b->as($b->value($a[0]), '%Str') ]);
        }
        if ($name eq 'shift' || $name eq 'pop') {
            return $b->emit(op => $name eq 'shift' ? 'AShift' : 'APop', type => '%Slot', inputs => [ $b->array_of($in[0]) ]);
        }
        if ($name eq 'join') {
            my @args = @in;
            pop @args if $v->can('memory_input') && $v->memory_input;
            my ($sep, @list) = @args;
            # ONE ARRAY is joined as it is; scalars (an array literal folded to
            # its elements, `"@a"`) and lists (a call's) go into a fresh array
            # first, each list's elements in its place.
            my $arr = ( @list == 1 && _is_list($list[0]) ) ? $b->array_of($list[0]) : do {
                my $t = $b->emit(op => 'NewArray', type => '%Array*');
                for my $e (@list) {
                    # (a list among them -- a method's, an array -- its elements)
                    if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $t, $b->array_of($e) ]); next }
                    $b->emit(op => 'APush', type => 'void', inputs => [ $t, $b->as($b->value($e), '%Slot') ]);
                }
                $t;
            };
            return $b->emit(op => 'Join', type => '%Str', inputs => [ $b->as($b->value($sep), '%Str'), $arr ]);
        }
    }
    if ($op eq 'EntryDef' && ( $v->symbol // '' ) eq '"') {
        # $" IS " " until written: a program that writes it is not T2's yet.
        out('$" written') if $b->{writes_list_sep} //= scalar grep {
            $_->operation =~ /\A(?:EntryWrite|LocalAlias)\z/ && grep { blessed($_) && $_->can('symbol') && ( $_->symbol // '' ) eq '"' } ( $_, $_->inputs->@* )
        } Chalk::IR::Graph::program_nodes( $b->{ret} );
        $b->{strs}{' '} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => ' ', id => $b->{strs}{' '} });
    }
    return undef;
}

# captured($pad) -> IN A CLOSURE, the reference its maker's `my` array or hash
# put in the cell it captured (the code value's environment, by its place).
sub captured {
    my ($b, $pad) = @_;
    my $ix = $b->emit_entry_end(op => 'Const', type => 'i64', attr => { value => $b->{cells}{ $pad->name } });
    my $cell = $b->emit_entry_end(op => 'EnvGet', type => '%Slot*', inputs => [ $b->{env}, $ix ]);
    return $b->emit_entry_end(op => 'Load', type => '%Slot', inputs => [$cell]);
}

# array_var($pad): a `my @a` named, not made here (is_my_array): one %Array
# per variable, made at its function's entry -- fresh each call. A closure's
# (shared) is not T2's.
sub array_var {
    my ($b, $pad) = @_;
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) { return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i }) ]) }
    # A FILE'S ARRAY: likewise, the global holding its reference.
    return $b->{locs}{ '@file#' . $pad->symbol } //= $b->emit_entry(op => 'GArray', type => '%Array*', attr => { global => $b->global_named( 'my::@' . $pad->symbol ) })
        if $pad->can('file') && $pad->file;
    return $b->{locs}{ '@cell#' . $pad->name } //= $b->emit_entry_end(op => 'ADeref', type => '%Array*', inputs => [ $b->captured($pad) ])
        if $b->{env} && defined( ( $b->{cells} // {} )->{ $pad->name } );
    out('an array a closure shares') if $pad->can('shared') && $pad->shared && !$b->_own_shared($pad);
    my $key = '@' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        my $a = Chalk::Target::LLVM::Node::_n(op => 'NewArray', type => '%Array*');
        unshift $b->{blocks}[0]{nodes}->@*, $a;
        $a;
    };
}

# array_of($n) -> the %Array* a T1 node names (an ArrayLiteral, a deref of one).
sub array_of {
    my ($b, $n) = @_;
    # A split: its fields, from its pattern's graph (the split flavor).
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->regex_split($n) ])
        if blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'builtin' && ( $n->name // '' ) eq 'split';
    # A MATCH IN LIST CONTEXT: its groups (or 1), or with /g every match's --
    # the list its pattern's graph (the list or all flavor) makes.
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->regex_list($n) ])
        if blessed($n) && $n->operation =~ /\A(?:RegexMatch|Match)\z/;
    # A SLURPY ARRAY PARAMETER: its copy, made at the sub's entry (args_rest).
    return $b->{memo}{ refaddr($n) } if blessed($n) && $n->operation eq 'Parameter' && $b->{memo}{ refaddr($n) };
    return $b->array_of($n->inputs->[0]) if blessed($n) && $n->operation eq 'Ref';
    if (blessed($n) && ( $n->operation =~ /\A(?:ArrayLiteral|ArgsSource|Slice|Range)\z/ || $n->is_array_deref || $n->is_my_array || $n->is_argv
                         || $n->is_package_aggregate && $n->sigil eq '@'
                         || $n->operation eq 'FieldAccess' && $b->type_of($n) eq '%Array*'
                         || $n->operation eq 'Repeat' && $b->type_of($n) eq '%Array*'
                         || $n->operation eq 'Call' && $n->returns_a_list )) {
        my $a = $b->value($n);
        return $a if $a->type eq '%Array*';
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [$a]) if $a->type eq '%Slot';   # [...]
        out('not an array');
    }
    # A CALL IN LIST CONTEXT: a sub returning a list gives a reference to it; a
    # sub returning one value is a list of it. A method's sub is not known here.
    if (blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'direct' && ( ( $n->name // '' ) !~ /__ANON__/ || $b->plain_anon($n) )) {
        my $r = $b->value($n);
        my $t = $n->target;
        my $fn = blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        out('a list from a call of no sub T2 made') unless $fn;
        # (IN SCALAR CONTEXT -- `r()->@*`, `@{ r() }`, `r()->[1]`: what it
        # returns is a reference, the array its value refers to; a list of
        # that one value printed "ARRAY(0x...)" for "1 2")
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [$r]) if $fn->{listret} || !_list_use($n);
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'APush', type => 'void', inputs => [ $a, $r ]);
        return $a;
    }
    # A CALL OF A CODE VALUE IN LIST CONTEXT: its wrapper hands back a list's
    # reference, as a method's does.
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ])
        if blessed($n) && $n->operation eq 'Call' && ( ( $n->dispatch_kind // '' ) eq 'indirect' || ( $n->name // '' ) =~ /__ANON__/ && !$b->plain_anon($n) );   # (a closure called directly too)
    # A METHOD IN LIST CONTEXT: its wrapper hands back a reference to a list
    # always (the sub's list, or one of its value) -- but a class's `new`,
    # made here, is its object.
    if (blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'method') {
        if ($b->_constructs($n)) {
            my $a = $b->emit(op => 'NewArray', type => '%Array*');
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->value($n) ]);
            return $a;
        }
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ]);
    }
    # A CHOICE IN LIST CONTEXT (`$c ? @$x : ()`, `$c ? @a : 7`): the list of
    # the arm taken, merged at the join.
    return $b->list_choice($n) if blessed($n) && $n->operation =~ /\A(?:TernaryExpr|And|Or)\z/ && ( _is_list($n) || $b->type_of($n) eq '%Array*' );
    # A LIST A LOOP BUILDS (a phi of one, map's ListAppend) is its array.
    return $b->value($n) if blessed($n) && $n->operation =~ /\A(?:Phi|ListAppend)\z/ && $b->type_of($n) eq '%Array*';
    # A HASH IN A LIST is its pairs, key then value (`(0, %h)`, `%$r`).
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]) if ( $n isa Chalk::IR::Node && $n->is_named_hash )
        || blessed($n) && $n->operation eq 'FieldAccess' && ( $b->field_of($n) )[1] eq '%';
    if (blessed($n) && $n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%') {
        return $b->value($n) unless $n->copy;   # (its pairs, read once)
        return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]);   # (the copy's)
    }
    # THROUGH AN ELEMENT (`$a[1][0]`, `@{$h{l}}`): the array the element holds. A
    # deref for a write B::SoN spells as the element made an array first (`//= []`).
    # (WRITTEN -- push, unshift, ... -- one undef there stops: B::SoN makes it an
    # array first where it can, and a write into a stand-in would be lost)
    # (an ELEMENT read through an undef one is undef, as perl's; read WHOLE --
    # a count, a list -- perl dies under strict and reads undef without: refused)
    if (blessed($n) && $n->operation eq 'Subscript' && !$b->{args}{ refaddr($n) }) {
        # (READ WHOLE WHERE B::SoN PINNED IT -- `scalar @{ $h->{l} }` -- an undef
        # there stops, loudly, where perl dies under strict refs or reads
        # nothing without: never a stand-in)
        out('an array through an element read whole') unless $b->{writing} || $b->{elem_read} || $b->{whole_stop};
        my $w = $b->{writing} || $b->{whole_stop};
        local $b->{elem_read} = 0;
        local $b->{whole_stop} = 0;
        return $b->emit(op => $w ? 'ADeref' : 'ADerefR', type => '%Array*', inputs => [ $b->as($b->value($n), '%Slot') ]);
    }
    # @Pkg::ISA IS THE RUN-TIME MOP'S OWN PARENT LIST: the array method lookup
    # walks, fetched where it is used, so push, shift and the rest change the
    # class's parents (perigrin: @ISA as the class's container; a view needs nothing kept in step).
    if ($n isa Chalk::IR::Node && $n->is_isa_array) {
        my $pkg = $n->package;
        out('an @ISA of no known package') unless defined $pkg && length $pkg;
        return $b->emit(op => 'MopIsaArr', type => '%Array*', inputs => [ $b->const_str($pkg) ]);
    }
    # A SCALAR HOLDING AN ARRAY REFERENCE (a variable, an argument): its
    # array, or a run-time stop when it holds none.
    out('an array that is not a `my` array (' . ( blessed($n) ? $n->operation . ( $n->can('symbol') && defined $n->symbol ? ' ' . $n->symbol : '' ) : 'none' ) . ')')
        unless blessed($n) && $b->type_of($n) eq '%Slot';
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ]);
}

# list_choice($TernaryExpr) -> c ? A : B read as a list: each arm made in its
# own block as a list (a list as it is, a scalar a list of one -- B::SoN folds
# `(7)` to 7), the arm taken's list at the join. Taken as a scalar it is
# refused (list_only). Made once.
# L && R, L || R read as a list: L in scalar context (an array its count)
# decides; where it does, the list is that one value, else R's list.
sub list_choice {
    my ($b, $v) = @_;
    my $key = 'list:' . refaddr($v);
    return $b->{memo}{$key} if $b->{memo}{$key};
    $b->list_only($v, 'a choice of lists');
    my ($cond, $then, $else) = $v->inputs->@*;
    my $c;
    if ( $v->operation =~ /\A(?:And|Or)\z/ ) {
        my $l = $b->as($b->value($cond), '%Slot');
        $c = $b->truth($l);
        ( $then, $else ) = $v->operation eq 'And' ? ( $then, $l ) : ( $l, $then );
    }
    else { $c = $b->truth($b->value($cond)) }
    my $arm = sub {
        my ($x) = @_;
        if ( $x isa Chalk::Target::LLVM::Node ) {   # (the left side's value, made)
            my $a = $b->emit(op => 'NewArray', type => '%Array*');
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $x ]);
            return $a;
        }
        return $b->array_of($x) if _is_list($x) || $b->type_of($x) eq '%Array*';
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($x), '%Slot') ]);
        return $a;
    };
    my $from = $b->{cur};
    # (a value made in an arm is the arm's: not seen after the join)
    my $tb = $b->new_block('then');
    my ($tv, $ev);
    { local $b->{memo} = { $b->{memo}->%* };
      local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $cond, 0 );
      $tv = $arm->($then); }
    my $tend = $b->{cur};
    my $eb = $b->new_block('else');
    { local $b->{memo} = { $b->{memo}->%* };
      $ev = $arm->($else); }
    my $eend = $b->{cur};
    my $jb = $b->new_block('join');
    $from->{term} = [ 'condbr', $c, $tb, $eb ];
    $tend->{term} = [ 'br', $jb ];
    $eend->{term} = [ 'br', $jb ];
    return $b->{memo}{$key} = $b->emit(op => 'Phi', type => '%Array*', inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ], list_choice => 1 });
}

# array_stmt($Call): push or unshift, or a shift or pop whose value is not used, in its
# place -- after every read the array's version had.
sub array_stmt {
    my ($b, $s) = @_;
    local $b->{writing} = 1;
    # ITS OWN ARRAY is read before it runs: one through a reference (`push
    # @{$r->{l}}, 4`) is made first, not refused as a read waiting across it.
    my ($own) = $s->inputs->@*;
    $b->value($own) if blessed($own) && $own->can('operation') && $b->_through_ref($own);
    $b->hash_reads_settled('a ' . $s->name);   # (it may store through a reference: `push @$r, 1`)
    my @in = $s->inputs->@*;
    pop @in if $s->can('memory_input') && $s->memory_input;
    if ($s->name eq 'push') {
        my ($arr, @vals) = @in;
        my $a = $b->array_of($arr);
        # MORE THAN ONE VALUE is one list pushed: a tie's PUSH gets them all at once.
        if (@vals > 1) {
            my $t = $b->emit(op => 'NewArray', type => '%Array*');
            for my $e (@vals) {
                if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $t, $b->array_of($e) ]) }
                else { $b->emit(op => 'APush', type => 'void', inputs => [ $t, $b->as($b->value($e), '%Slot') ]) }
            }
            @vals = ();
            $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $t ]);
        }
        for my $e (@vals) {
            # A LIST PUSHED is its elements (`push @r, f()`, `push @a, @b`).
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $b->array_of($e) ]); next }
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($e), '%Slot') ]);
        }
        # ITS VALUE is the array's new count (an ADJUST's last statement) --
        # counted only where it is read: a tie's FETCHSIZE is a call perl does not make.
        $b->{memo}{ refaddr($s) } = $b->_value_read($s) ? $b->emit(op => 'ALen', type => 'i64', inputs => [$a])
            : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        return;
    }
    if ($s->name eq 'unshift') {
        my ($arr, @vals) = @in;
        my $a = $b->array_of($arr);
        out('a list unshifted') if grep { _is_list($_) } @vals;
        my @v = map { $b->as($b->value($_), '%Slot') } @vals;
        if (@v == 1) { $b->emit(op => 'AUnshift', type => 'void', inputs => [ $a, $v[0] ]) }
        else {   # one list unshifted: a tie's UNSHIFT gets them all at once
            my $t = $b->emit(op => 'NewArray', type => '%Array*');
            $b->emit(op => 'APush', type => 'void', inputs => [ $t, $_ ]) for @v;
            $b->emit(op => 'AUnshiftL', type => 'void', inputs => [ $a, $t ]);
        }
        $b->{memo}{ refaddr($s) } = $b->_value_read($s) ? $b->emit(op => 'ALen', type => 'i64', inputs => [$a])
            : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        return;
    }
    $b->value($s);   # shift, pop: made here, its value memoized for its reader
}

# element_store($Subscript, $value): `$a[i] = v`, the array growing to i.
sub element_store {
    my ($b, $target, $v, $s) = @_;
    # (STORED THROUGH AN ELEMENT B::SoN did not make a hash or array first -- a
    # reference from elsewhere: refused, not stopped at run time where it is undef)
    out('a store through an element not made a hash or array first')
        if blessed( $target->inputs->[0] ) && $target->inputs->[0]->operation eq 'Subscript' && !$b->{args}{ refaddr( $target->inputs->[0] ) };
    # (AN ELEMENT OF A SLICE -- grep's or map's $_ over `@a[0, 1]` -- is the
    # array's own element in perl; the slice here is a copy: refused)
    out("a store into a slice's element (perl aliases the array's element)")
        if blessed( $target->inputs->[0] ) && $target->inputs->[0]->operation eq 'Slice';
    if (( $target->can('kind') ? $target->kind // 'array' : 'array' ) eq 'hash') {
        my ($h, $k) = $target->inputs->@[0, 1];
        # perl evaluates what it stores, then where, then stores.
        my $val = $b->as($b->value($v), '%Slot');
        my $key = $b->as($b->value($k), '%Str');
        my $ref = $b->hash_of($h);
        # A HASH READ STILL TO BE MADE, of a version this store replaces, would
        # be made after it and see the new value: refused. (reads_before leaves
        # hash reads in place: made early, one could run above its guard.)
        $b->hash_reads_settled('a hash store');
        $b->reads_before($_) for $b->{passed}->@*;
        $b->emit(op => 'HSet', type => 'void', inputs => [ $ref, $key, $val ]);
        return;
    }
    my ($arr, $idx) = $target->inputs->@[0, 1];
    # A LIST WRITTEN OUT (`for ($x, @a[1, 2]) { $_ *= 10 }`, no array of its
    # own): perl's elements are its items' own -- stored through their
    # aliases (an array of them, as @_ is). A named array's (`my @n = sort
    # ...`) are its own.
    my $anon = blessed($arr) && $arr->operation eq 'ArrayLiteral' && !defined $arr->symbol && ( $arr->stamp // '' ) eq 'Array';   # static type
    my $val = $b->as($b->value($v), '%Slot');
    my $ix  = $b->as($b->value($idx), 'i64');
    my $a   = $anon ? do { local $b->{alias_strict} = 1; $b->alias_list($arr) } : $b->array_of($arr);
    $b->hash_reads_settled('an element store');   # it may be an array read through another name
    my ($at) = grep { $_->can('line') && defined $_->line } $s, $target;
    # A STORE INTO @_ (or a list's aliases) is the caller's: a literal there is read-only, and
    # perl dies -- its message, caught, names where (no site from B::SoN for
    # this store: refused where an eval may catch it).
    my $into_args = blessed($arr) && $arr->operation eq 'ArgsSource' || $anon;
    out('a store into @_ of no site, in a program with an eval') if $into_args && !$at && $b->{has_eval};
    $b->emit(op => 'ASet', type => 'void',
        inputs => [ $a, $ix, $val ],
        attr => do {
            # PERL DIES on a store before the start, naming the subscript and where.
            my $msg = $at ? " at " . ( $at->file // '-' ) . " line " . $at->line . ".\n" : ".\n";   # no site from B::SoN yet
            $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
            +{ msg => $msg, id => $b->{strs}{$msg} };
        });
    $b->after_call if $into_args;
}

1;
