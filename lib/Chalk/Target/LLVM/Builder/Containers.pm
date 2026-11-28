# ABOUTME: The LLVM builder's arrays and hashes: `my` and package aggregates, references to
# ABOUTME: them, their elements, reads and stores (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

require Chalk::Impl;

# make_constant_arrays(@nodes): an array whose literal holds only constants
# (`my @a = (1, 2)`, `my @a`) is made in the entry block -- first made where it
# was first used, in a loop body it was made again each pass. (Not one a merge
# places in an arm or a loop body -- `@p = ()` there: see agg_home.)
sub make_constant_arrays {
    my ($b, @nodes) = @_;
    for my $lit (grep { $_->operation eq 'ArrayLiteral' } @nodes) {
        next if $lit->is_pinned;   # a `my @a` pinned where it runs: made there
        next if $lit->stored_whole_into;   # a package array, read where it is read
        next if grep { !( blessed($_) && $_->operation eq 'Constant' ) } $lit->inputs->@*;
        next unless $b->agg_home_here($lit, 'top');
        # (an arm's items of `\(c ? (...) : ())`: no array, each item referenced -- item_refs)
        next if !defined $lit->symbol && grep { my $t = $_; blessed($t) && $t->operation eq 'TernaryExpr'
            && grep { _refs_each_item($_) } ( $t->consumers // [] )->@* } ( $lit->consumers // [] )->@*;
        $b->value($lit);
    }
    # A `my %h = (...)` of constants, or of @_, is made at entry too.
    for my $lit (grep { $_->operation eq 'HashLiteral' && ( $_->stamp // '' ) eq 'Hash' && !$_->is_pinned && !$_->stored_whole_into } @nodes) { # static type
        next if grep { !( blessed($_) && ( $_->operation =~ /\A(?:Constant|ArgsSource)\z/ || $b->{args}{ refaddr($_) } ) ) } $lit->inputs->@*;
        next unless $b->agg_home_here($lit, 'top');
        $b->value($lit);
    }
}

# WHERE A WHOLE ARRAY OR HASH IS MADE. A `my @a = (...)`, a `%h = ()` -- a new
# aggregate (B::SoN's ArrayLiteral or HashLiteral) that B::SoN does not pin --
# is made once each time its statement runs, and written in place after (a
# push, an element store). Made where it is first needed, it may be made in
# a loop body its statement is not in (made again each pass: the pushes of
# the last pass lost), or before a loop its statement is in (one for every
# pass), or in an arm when it is read after the join too (made again there,
# without what the arm wrote). So:
#   - A MERGE IT IS A WAY INTO says which pass makes it (agg_home): a loop
#     phi's back edge, the loop's body; its entry, outside that loop; an if's
#     merge, the loop the arm is in.
#   - AS AN IF OR A LOOP IS ENTERED (agg_settle), each one of the pass the
#     walk is in -- a merge says so, or none says -- all it holds made (none
#     computed early: it could be guarded), is made, before what needs it.
#   - FIRST NEEDED ELSEWHERE (agg_made_here): in the loop body a merge places
#     it in, or in an arm or a body where what it holds is made (it is that
#     scope's own: its statement is in it). Else refused by name.
#   - A LIST OF NO VARIABLE'S (no symbol: `@p[1 .. $#p]` walked by a foreach)
#     is a value, made where it is needed as any value is.

# scope_key($ctl) -> the key of a loop's body (its Proj, or the Loop of a body
# walked from it), 'top' for the function's own.
sub scope_key { my ($n) = @_; return !blessed($n) || $n->operation eq 'Start' ? 'top' : refaddr($n) }

# _loop_scope($ctl) -> the entry of the loop body the control $ctl stands in
# (a Loop's body Proj, or the Loop whose body hangs off it), or Start: back
# along the control chain, an if's arm and a finished if or loop passed
# through. undef where the chain is not one of these.
sub _loop_scope {
    my ($ctl) = @_;
    my $from;
    for (1 .. 100_000) {
        return undef unless blessed($ctl);
        my $op = $ctl->operation;
        return $ctl if $op eq 'Start';
        if ($op eq 'Loop') {
            # (reached from a statement of its body -- a loop walked from the
            # Loop itself: its body; from its exit: after it)
            return $ctl if blessed($from) && $from->operation ne 'Proj';
            ( $from, $ctl ) = ( $ctl, $ctl->control_in );
            next;
        }
        if ($op eq 'Proj') {
            my $p = $ctl->inputs->[0];
            return undef unless blessed($p) && $p->operation =~ /\A(?:If|Loop)\z/;
            # (a loop's test: Proj 0 its body, Proj 1 its exit -- after the loop)
            if ( $p->operation eq 'If' && ( my $L = _tested_loop($p) ) ) {
                return $ctl if $ctl->index == 0;
                ( $from, $ctl ) = ( $L, $L->control_in );
                next;
            }
            ( $from, $ctl ) = ( $ctl, $p );   # (an if's arm: the if's; a loop's exit: the loop's)
            next;
        }
        if ($op eq 'Region') {   # (a merge: after its if or its loop -- from its first way in)
            ( $from, $ctl ) = ( $ctl, $ctl->inputs->[0] );
            next;
        }
        my $c = $ctl->can('control_in') && blessed( $ctl->control_in ) ? $ctl->control_in : return undef;
        ( $from, $ctl ) = ( $ctl, $c );
    }
    return undef;
}

# agg_home($lit) -> the key of the loop body (or 'top') whose pass makes a
# whole aggregate, where a merge it is a way into says (see above); undef
# where none does, '?' where they disagree or say what is not known.
sub agg_home {
    my ($b, $L) = @_;
    my $k = refaddr($L);
    return $b->{agg_home}{$k} if exists $b->{agg_home}{$k};
    my %at;
    for my $p (grep { blessed($_) && $_->operation eq 'Phi' && !$_->memory } ( $L->consumers // [] )->@*) {
        my $r = $p->region;
        for my $i (grep { blessed( $p->inputs->[$_] ) && refaddr( $p->inputs->[$_] ) == refaddr($L) } 0 .. $p->inputs->$#*) {
            my $e;
            if ( blessed($r) && $r->operation eq 'Loop' ) {
                $e = $i ? ( loop_body_proj($r) // $r )
                        : _loop_scope( $r->control_in );
            }
            else {
                my $pr = $p->predecessors;
                $e = $pr && blessed( $pr->[$i] ) ? _loop_scope( $pr->[$i] ) : undef;
            }
            $at{ blessed($e) ? scope_key($e) : '?' } = 1;
        }
    }
    my @at = keys %at;
    return $b->{agg_home}{$k} = !@at ? undef : @at == 1 ? $at[0] : '?';
}

# agg_home_here($lit, $loop) -> a merge places the aggregate in the loop body
# $loop (a scope_key), or none does.
sub agg_home_here {
    my ($b, $L, $loop) = @_;
    my $h = $b->agg_home($L);
    return !defined $h || $h eq $loop;
}

# _made_in_scope($n, $base, $seen) -> the value $n is made in the scope the
# walk is in, not before it: not in $base (the memo as the scope was entered),
# and not made of what is (a pinned node, a phi, a read at a memory version,
# or what holds one of them, made after the scope began).
sub _made_in_scope {
    my ($b, $n, $base, $seen) = @_;
    return 0 unless blessed($n) && $n->can('operation');
    return 0 if $base->{ refaddr($n) } || $n->operation eq 'Constant';
    return $seen->{ refaddr($n) } if exists $seen->{ refaddr($n) };
    $seen->{ refaddr($n) } = 0;
    my $r = $n->is_pinned || $n->operation eq 'Phi' || blessed( $n->memory_operand ) ? 1
          : scalar grep { $b->_made_in_scope($_, $base, $seen) } $n->inputs->@*;
    return $seen->{ refaddr($n) } = $r ? 1 : 0;
}

# agg_made_here($lit) -> true where a whole aggregate not pinned may be made
# where the walk is (see above).
sub agg_made_here {
    my ($b, $L) = @_;
    return 1 if $b->{agg_settling} || $b->{at_way};
    return 1 unless defined $L->symbol;   # (a list of no variable's: a value)
    my $h = $b->agg_home($L);
    my $loop = $b->{lscope} // 'top';
    my $in = $b->{scope_in};   # (the innermost scope: undef the function's own, else [kind, base memo])
    return !defined $h || $h eq 'top' unless $in;
    return 1 if $in->[0] eq 'loop' && defined $h && $h eq $loop;
    return 0 if defined $h && $h ne $loop;
    return $b->_made_in_scope($L, $in->[1], {});
}

# _refs_made_of_made($n) -> `\(c ? ($x, $y) : ())` whose choice and items are
# made (or constants): references, which cannot die -- made early, the same.
sub _refs_made_of_made {
    my ($b, $n) = @_;
    return 0 unless _refs_each_item($n);
    my ( $c, @arms ) = $n->inputs->[0]->inputs->@*;
    my @parts = ( $c, map { $_->operation eq 'ArrayLiteral' && !defined $_->symbol ? $_->inputs->@* : $_ } @arms );
    return !grep { !( blessed($_) && ( $b->{memo}{ refaddr($_) } || $_->operation eq 'Constant' ) ) } @parts;
}

# _of_constants($n) -> a Constant, or a list, coercion or repetition of
# constants (`(0) x 3`): on no chain, and none of them can die -- made early,
# the same.
sub _of_constants {
    my ($n) = @_;
    return 0 unless blessed($n);
    return 1 if $n->operation eq 'Constant';
    return 0 unless $n->operation =~ /\A(?:ArrayLiteral|Coerce|Repeat)\z/ && !$n->is_pinned && !blessed( $n->mem_in );
    return 0 if $n->operation eq 'ArrayLiteral' && defined $n->symbol;
    return !grep { !_of_constants($_) } $n->inputs->@*;
}

# agg_settle(): AS AN IF OR A LOOP IS ENTERED, each whole aggregate of this
# function not pinned and not made yet that is of the pass the walk is in --
# a merge places it there, or none does -- and all of whose parts are made
# (nothing computed early: one of them could be guarded) is made here, before
# what needs it.
sub agg_settle {
    my ($b) = @_;
    my $loop = $b->{lscope} // 'top';
    for my $L (grep { $_->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && ( $_->stamp // '' ) =~ /\A(?:Array|Hash)\z/   # static type
                      && !$_->is_pinned && defined $_->symbol } +($b->{own_nodes} // [])->@*) {
        next if $b->{memo}{ refaddr($L) } || $L->stored_whole_into || !$b->agg_home_here($L, $loop);
        next if grep { !( blessed($_) && ( $b->{memo}{ refaddr($_) } || _of_constants($_) || $b->_refs_made_of_made($_) ) ) } $L->inputs->@*;
        local $b->{agg_settling} = 1;
        $b->value($L);
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
        # A `my %h` NOT PINNED is made where agg_made_here says its statement
        # is: in another loop body or arm it was made again each pass, or gone after.
        out('a hash first made in an arm or a loop body') if $st eq 'Hash' && !$v->is_pinned && !$b->agg_made_here($v);
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
            out('a list in a {...}') if grep { _is_list($_) } ( $in[$i], $in[ $i + 1 ] ); # static type
            $b->emit(op => 'HSet', type => 'void',
                inputs => [ $h, $b->as($b->value($in[$i]), '%Str'), $b->as($b->value($in[ $i + 1 ]), '%Slot') ]);
        }
        return $h;
    }
    # A `my` HASH READ WHOLE AT A MEMORY VERSION (B::SoN's mem_in): a copy of
    # it as it is there, made where the read is (reads_before).
    if ( $v->is_my_hash && $op eq 'PadAccess' && $v->is_versioned_read ) {
        my $h = $b->emit(op => 'HNew', type => '%Slot');
        my $place = $b->_place_of($v);
        $b->emit(op => 'HFromArray', type => 'void', inputs => [ $h, $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $place ? $b->hash_of($place) : $b->hash_var($v) ]) ]);
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
        # (an undef reference without strict refs is an empty hash, as perl's)
        my $pairs = $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->emit(op => 'HDerefR', type => '%Slot',
            inputs => [ $b->whole_hash($v, $b->as($b->value($in[0]), '%Slot')) ]) ]);
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
    if ($op eq 'Call' && $v->reads_call_stack) {
        my ($n) = grep { blessed($_) } @in;
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
        # (A COPY's -- `my %c = %$h; keys %c` -- is its own hash, made where it
        # stands through whole_hash: not the source as it is here)
        my $h = blessed($in[0]) && $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%' && !$in[0]->copy
            ? $b->emit(op => 'HDerefR', type => '%Slot', inputs => [ $b->whole_hash($in[0], $b->as($b->value( $in[0]->inputs->[0] ), '%Slot')) ])
            : $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]) if $v->lists_a_hash eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar';
        return $b->emit(op => $v->lists_a_hash eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
    }
    # each %h IN A LIST: its next key and value, or none (and it starts over).
    # In scalar context (the key alone) not T2's.
    if ($op eq 'Call' && $v->advances_iterator) {
        out('an each in scalar context') unless ( $v->can('want') ? $v->want // '' : '' ) eq 'list';
        out('an each of what is not a hash') unless $in[0] isa Chalk::IR::Node && $in[0]->is_named_hash;
        # keys AND values START A HASH'S each OVER, but B::SoN places neither
        # (a value made where it is used, or never): where they run against an
        # each is not known. Refused where the program has one of a hash that
        # may be this one -- of no name known, or of this hash's name. (A
        # keys of another named hash resets that one's.)
        my $mine = _hash_name( $in[0] );
        out('an each in a program with a keys or values (which reset it, B::SoN places them nowhere)')
            if grep { $_->operation eq 'Call' && $_->resets_iterator
                      && !( defined $mine && ( _hash_name( $_->inputs->[0] ) // $mine ) ne $mine ) }
                _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        return $b->emit(op => 'Each', type => '%Array*', inputs => [ $b->hash_of($in[0]) ]);
    }
    # sort (by string or by number, either way) and reverse, of a list: a new
    # list. A sort with its own comparator is not T2's yet.
    if ($op eq 'Call' && $v->reorders_list
            && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/) {   # static type
        # A SORT WITH ITS OWN COMPARATOR (a block, a named sub): a function of
        # no arguments, called for each pair with $a and $b -- the sort
        # package's -- set to it; its number orders the pair.
        my $by = ( $v->builtin_kind // '' ) eq 'sorted' && ( ( $v->can('sort_cmp_body') && $v->sort_cmp_body ) || !( $v->can('sort_cmp') && defined $v->sort_cmp ) );
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
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (grep { blessed($_) } @l) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($e), '%Slot') ]) }
        }
        return $b->emit(op => 'ARev', type => '%Array*', inputs => [$arr]) if ( $v->builtin_kind // '' ) eq 'reversed';
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

# _hash_name($n) -> the name of the hash a node is, where it is one by its
# name -- a `my %h` ('my:h'; two of one name are one here), a package hash
# ('pkg:main::h') -- whose iterator none other shares; else undef (a hash
# through a reference may be any).
sub _hash_name {
    my ($n) = @_;
    return undef unless $n isa Chalk::IR::Node;
    my $op = $n->operation;
    if ( $op eq 'HashLiteral' && ( $n->stamp // '' ) eq 'Hash' && defined $n->symbol ) {   # static type
        ( my $sym = $n->symbol ) =~ s/\A%//;
        return $sym =~ /::/ ? "pkg:$sym" : "my:$sym";
    }
    return 'my:' . $n->symbol if $op eq 'PadAccess' && $n->is_my_hash && defined $n->symbol;
    return 'pkg:' . $n->qualified_name if $op eq 'EntryDef' && $n->is_package_aggregate && $n->sigil eq '%';
    return undef;
}

# pkg_agg($n): THE ONE AGGREGATE a global holds, made at its first use from
# any function. A whole store refills it in place, so its pointer stands.
# _place_of($read) -> the variable's own node (no mem_in) a versioned read of a
# `my` aggregate is of: what it lowers to is the variable -- its storage, or
# the arguments `my ($c, @x) = @_` bound it to (args_rest) -- undef if none.
sub _place_of {
    my ($b, $v) = @_;
    my ($p) = grep { $_->operation eq 'PadAccess' && !blessed( $_->mem_in ) && !$_->inputs->@*
                     && $_->name eq $v->name && ( $_->targ // '' ) eq ( $v->targ // '' ) } ( $b->{own_nodes} // [] )->@*;
    return $p;
}

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
    for ( $o, @args ) { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) }
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
        my @pos = grep { blessed( $in[$_] ) && refaddr( $in[$_] ) == refaddr($n) } 0 .. $#in;
        next unless @pos;
        my $op = $u->operation;
        next if $op eq 'TernaryExpr' && !grep { $_ != 0 } @pos;
        next if $op eq 'And' && !grep { $_ != 0 } @pos;
        next if $op =~ /\A(?:If|Not|Defined)\z/;
        return 0;
    }
    return 1;
}

# _count_may_be_undef($Count) -> true for a count of an array through a
# reference where B::SoN says perl may die (its site), without strict refs --
# perl's is undef there of an undef reference -- read other than as a number
# or a truth (_read_as_a_number), where that undef shows.
sub _count_may_be_undef {
    my ($b, $v) = @_;
    my $d = $v->inputs->[0];
    # (a copy is an array of its own, made where it stands: counted, never undef)
    return 0 unless blessed($d) && $d->operation eq 'PostfixDeref' && $d->is_array_deref && defined $d->line && !$d->strict && !$d->copy;
    # (through what a scalar holds -- a variable, an element: an array itself is no reference)
    return 0 unless blessed( $d->inputs->[0] ) && $b->type_of( $d->inputs->[0] ) eq '%Slot';
    return $b->{memo}{ 'count_undef:' . refaddr($v) } //= $b->_read_as_a_number($v) ? 0 : 1;
}

# _read_as_a_number($n) -> true where every reader of $n takes it as a number
# or a truth only (a numeric comparison, + - *, an if's or ?:'s condition, a
# not, an && or || or a merge itself so read), where an undef and a 0 read
# the same.
sub _read_as_a_number {
    my ($b, $n, $seen) = @_;
    return 1 if ( $seen //= {} )->{ refaddr($n) }++;
    for my $u ( $b->value_readers($n) ) {
        my $op = $u->operation;
        next if $op =~ /\A(?:Num(?:Eq|Ne|Lt|Le|Gt|Ge)|Add|Subtract|Multiply|If|Not)\z/;
        next if ( $op =~ /\A(?:And|Or)\z/ || $op eq 'Phi' && !$u->memory ) && $b->_read_as_a_number($u, $seen);
        next if $op eq 'TernaryExpr' && refaddr( $u->inputs->[0] ) == refaddr($n)
            && !grep { blessed($_) && refaddr($_) == refaddr($n) } $u->inputs->@[1, 2];
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
    for ( $o, @args ) { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) }
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
    } grep { $_->operation eq 'Call' && $_->loads_a_file } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
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

# swapped_place($n) -> true where $n reads the name of a package aggregate a
# `local` swaps as the place (no memory version): what it is depends on where
# it is read.
sub swapped_place {
    my ($b, $n) = @_;
    return blessed($n) && $n isa Chalk::IR::Node && $n->operation eq 'EntryDef' && $n->is_package_aggregate
        && !blessed( $n->mem_in ) && $b->swapped->{ _pkg_agg_name($n) } ? 1 : 0;
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
        return $b->whole_hash($n, $b->as($b->value( $n->inputs->[0] ), '%Slot'));
    }
    # THROUGH AN ELEMENT (`$h{x}{y}`): the reference the element holds. A deref
    # for a write B::SoN spells as the element made a hash first (`//= {}`).
    out('a hash element of a named hash') if ( $n->can('sigil') ? $n->sigil // '' : '' ) eq '%'
        || $n->operation eq 'EntryDef' && !$n->is_package_scalar   # a package hash by name: $ENV{K} (not `$a->{k}`: a reference)
        || $n->operation eq 'Constant';
    return $b->as($b->value($n), '%Slot');
}

# _never_numified($n, $reader) -> true where no numeric read can have reached
# what $n holds when $reader reads it (perl caches a string's number, and the
# string is a number after). Known for a constant read only so -- B::SoN folds
# a `my $x = "az"` into its constant, so any reader is the variable's -- and
# an element of a `my` array of such, read only by constant index, so.
sub _never_numified {
    my ($b, $n, $reader) = @_;
    return 0 unless blessed($n);
    # (read by $reader, or so that no number is made: a print, a `.`, a
    # defined -- a numeric Coerce only on the way to $reader)
    my $quiet = sub ($x, $r) {
        for my $u ( $b->value_readers($x) ) {
            next if refaddr($u) == refaddr($r);
            my $o = $u->operation;
            next if $o =~ /\A(?:Print|Concat|Defined)\z/;
            next if $o eq 'Coerce' && !grep { refaddr($_) != refaddr($r) && $_->operation !~ /\A(?:Print|Concat)\z/ } $b->value_readers($u);
            return 0;
        }
        return 1;
    };
    return $quiet->( $n, $reader ) if $n->operation eq 'Constant';
    if ( $n->operation eq 'Subscript' && ( $n->can('kind') ? $n->kind // 'array' : 'array' ) eq 'array' ) {
        my ($a, $i) = $n->inputs->@*;
        return 0 unless blessed($a) && $a->operation eq 'ArrayLiteral' && ( $a->stamp // '' ) eq 'Array'   # static type
            && blessed($i) && $i->operation eq 'Constant';
        return 0 unless $quiet->( $n, $reader );
        # (the array: read only by elements at constant indices -- nothing
        # writes it -- this one's read so; made of constants no numeric read
        # reached)
        for my $u ( $b->value_readers($a) ) {
            return 0 unless $u->operation eq 'Subscript' && blessed( $u->inputs->[1] ) && $u->inputs->[1]->operation eq 'Constant';
            # (another element: two indices not both counted from the front may be one)
            my @ix = map { $_->value // '' } $u->inputs->[1], $i;
            next if refaddr($u) == refaddr($n);
            next if !( grep { !/\A\d+\z/ } @ix ) && $ix[0] != $ix[1];
            return 0 unless $quiet->( $u, $reader );
        }
        return !grep { !( blessed($_) && $_->operation eq 'Constant' && $quiet->( $_, $a ) ) } $a->inputs->@*;
    }
    return 0;
}

# array_value($v, $op) -> the T2 node of an array, or of a read of one; undef
# for what is not.
sub array_value {
    my ($b, $v, $op) = @_;
    my @in = $v->inputs->@*;
    if ($op eq 'ArrayLiteral') {
        # ONE NOT PINNED is made where agg_made_here says its statement is: in
        # another loop body or arm it was made again each pass, or gone after.
        # (a [...] B::SoN does not pin, at the function's own scope only)
        out('an array first made in an arm or a loop body') if !$v->is_pinned
            && ( ( $v->stamp // '' ) eq 'ArrayRef' ? $b->{depth} : !$b->agg_made_here($v) );   # static type: a [...] is made where it runs
        # AN ALIAS LIST holding a place (B::SoN's foreach, map or grep over
        # package scalars or elements), or `values` of a hash (perl aliases
        # each value -- design B, audit 3 N3): an array of aliases, each item
        # the variable or element itself, read and stored through.
        return $b->args_array(@in)
            if ( $v->stamp // '' ) ne 'ArrayRef' && grep { blessed($_) && ( $_->can('place') && $_->place
                || $_->operation eq 'Call' && ( $_->lists_a_hash // '' ) eq 'values' ) } @in;   # static type
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
        # \$h{k}: A REFERENCE TO A HASH ELEMENT is the element's own cell (tag
        # 9), the hash made one of cells (t2_helem_ref): written through either
        # name; a delete or a clear leaves it the hash's no more, as perl's.
        if ( $v->is_hash_element_ref ) {
            if ( my $why = $v->hash_element_ref_unsound ) { out($why) }
            my ($c, $k) = $v->hash_element_subscript->inputs->@[0, 1];
            out('a reference to an element through an element not made a hash first')
                if blessed($c) && $c->operation eq 'Subscript' && !$b->{args}{ refaddr($c) };
            my $key = $b->as($b->value($k), '%Str');
            my $h = $b->hash_of($c);
            # (taking it may make the key: a read of the hash still to be made,
            # of the version before, is made first)
            $b->hash_reads_settled('a reference to a hash element');
            return $b->emit(op => 'HElemRef', type => '%Slot', inputs => [ $h, $key ]);
        }
        # \$a[i]: A REFERENCE TO AN ELEMENT is the element's own cell (tag 9),
        # the array made one of aliases (t2_aelem_ref): written through either
        # name, kept past a grow, a shift, a refill -- where it is the element
        # perl's is wherever it is made (Ref's element_ref_unsound).
        if ( $v->is_element_ref ) {
            if ( my $why = $v->element_ref_unsound ) { out($why) }
            out('a reference to each element taken as a scalar') unless $v->element_subscript;
            my ($c, $k) = $v->element_subscript->inputs->@[0, 1];
            out('a reference to an element through an element not made an array first')
                if blessed($c) && $c->operation eq 'Subscript' && !$b->{args}{ refaddr($c) };
            my $ix = $b->as($b->value($k), 'i64');
            # (an element of a list written out is its item's own: of the list's aliases)
            my $arr = blessed($c) && $c->operation eq 'ArrayLiteral' && !defined $c->symbol && ( $c->stamp // '' ) eq 'Array'   # static type
                ? do { local $b->{alias_strict} = 1; $b->alias_list($c) }
                : do { local $b->{writing} = 1; $b->array_of($c) };
            # PERL DIES before the start, "Modification of non-creatable array
            # value attempted, subscript -N at FILE line N.": one that may
            # names its site (B::SoN), and its die is an eval's to catch. (One
            # that names none cannot die: its index is in the array or a
            # constant past its start -- the message is never printed.)
            my $msg = defined $v->line ? ' at ' . ( $v->file // '-' ) . ' line ' . $v->line . ".\n" : ".\n";
            $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
            my $r = $b->emit(op => 'AElemRef', type => '%Slot', inputs => [ $arr, $ix ], attr => { msg => $msg, id => $b->{strs}{$msg} });
            $b->after_call if defined $v->line;
            return $r;
        }
        # \$x, \"lit", \($c ? $x : 0): a reference to a scalar (scalar_ref).
        return $b->scalar_ref($v, $t) if _scalar_ref_of($t);
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
    # integers from one bound to the other. ONE WHERE NEITHER IS (`"az" ..
    # "bb"`) is perl's choice at run time (t2_range_slots): on numbers where
    # the strings look like them, else the left magic-incremented up to the
    # right. A string a numeric read made a number is one to it: each bound
    # must be one no numeric read reached (_never_numified).
    if ($op eq 'Range') {
        $b->list_only($v, 'a range');
        # (a bound as it is, not as B::SoN coerced it: it numifies both, the
        # strings of `"az" .. "bb"` too)
        my ($lo, $hi) = map { my $x = $_; $x = $x->inputs->[0] while blessed($x) && $x->operation eq 'Coerce'; $x } @in;
        return $b->emit(op => 'ARange', type => '%Array*', inputs => [ map { $b->as($b->value($_), 'i64') } $lo, $hi ])
            if grep { $b->type_of($_) =~ /\A(?:i64|double)\z/ } $lo, $hi;
        out('a range of strings a numeric read may have made numbers') unless $b->_never_numified( $lo, $v ) && $b->_never_numified( $hi, $v );
        return $b->emit(op => 'ARangeSlots', type => '%Array*', inputs => [ map { $b->as($b->value($_), '%Slot') } $lo, $hi ]);
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
        # (READ WHOLE WHERE PERL MAY DIE -- B::SoN names the site and strict
        # refs: an undef there dies under strict, reads empty without)
        local $b->{whole_die} = defined $v->line ? $v : undef;
        # `my @p = @$r` IS A COPY (B::SoN's copy): its own array, of the
        # elements as they are here.
        # (AN RVALUE READ MADE BEFORE A STORE THAT KILLS ITS VERSION --
        # reads_before -- is the array as it is there: a copy too, or a list
        # flattening it later, `my @d = (0, @$l); push @$l, 2`, saw the push)
        return $b->array_of($in[0]) unless $v->can('copy') && $v->copy || ( $b->{snapshot} // 0 ) == refaddr($v) && defined $v->line;
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $b->array_of($in[0]) ]);
        return $a;
    }
    # A `my` ARRAY READ WHOLE AT A MEMORY VERSION: a copy, as for a hash.
    if ( $v->is_my_array && $op eq 'PadAccess' && $v->is_versioned_read ) {
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        my $place = $b->_place_of($v);
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $place ? $b->array_of($place) : $b->array_var($v) ]);
        return $a;
    }
    return $b->array_var($v) if $v->is_my_array;
    return $b->emit(op => 'Argv', type => '%Array*') if $v->is_argv;
    return $b->{argsarr} // out('@_ outside a sub taking it as a list') if $op eq 'ArgsSource';
    # A HASH COUNTED is its keys (perl 5.26+), not its pairs flattened (4 for 2).
    # (a package hash by name -- `our %g; scalar(%g)`, `%g ? :` -- as a `my %h`)
    if ($op eq 'Count' && blessed($in[0]) && ( $in[0]->is_named_hash || $in[0]->is_package_aggregate && $in[0]->sigil eq '%'
                                               || $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%' || $in[0]->operation eq 'FieldAccess' && ( $b->field_of($in[0]) )[1] eq '%' )) {
        # (`my %c = %$h` is a hash of its own: its keys, not the source's now)
        my $h = $in[0]->operation eq 'PostfixDeref' && !$in[0]->copy ? $b->hash_of($in[0]->inputs->[0]) : $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]);
    }
    # A COUNT OF AN ARRAY THROUGH A REFERENCE WITHOUT STRICT REFS, where perl
    # may die under them (B::SoN's site): of an undef reference perl's is
    # undef, not 0 -- read other than as a number or a truth, a %Slot.
    if ($op eq 'Count' && $b->_count_may_be_undef($v)) {
        my $d = $in[0];
        my $r = $b->as($b->value( $d->inputs->[0] ), '%Slot');
        my $n = $b->as($b->emit(op => 'ALen', type => 'i64', inputs => [ $b->whole_deref($d, $r) ]), '%Slot');
        return $b->emit(op => 'Select', type => '%Slot', inputs => [ $b->emit(op => 'Defined', type => 'i1', inputs => [$r]), $n, $b->emit(op => 'Undef', type => '%Slot') ]);
    }
    return $b->emit(op => 'ALen', type => 'i64', inputs => [ $b->array_of($in[0]) ]) if $op eq 'Count';
    if ($op eq 'Subscript') {
        out('a hash element') unless ( $v->can('kind') ? $v->kind // 'array' : 'array' ) eq 'array';
        my $arr = do { local $b->{elem_read} = 1; $b->array_of($in[0]) };   # (an element read: through undef it is undef)
        return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->as($b->value($in[1]), 'i64') ]);
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin') {
        my $name = $v->name // '';
        my $kind = $v->builtin_kind // '';
        if ($v->is_tie_builtin) {
            # (a tie's methods may die, and nothing after them looks: not T2's in a program with an eval)
            out("a $name in a program with an eval") if $b->{has_eval};
            my @args = @in;
            my ($c, $cls, @rest) = @args;
            my $sig = blessed($c) && $c->can('sigil') && defined $c->sigil ? $c->sigil
                : blessed($c) && $c->operation eq 'ArrayLiteral' ? '@' : blessed($c) && $c->operation eq 'HashLiteral' ? '%' : '';
            # A TIE OF A SCALAR Analysis rewrote (its read FETCH on the tie's
            # object, its tied() the object): the class's TIESCALAR, given the
            # class and the arguments -- its object the tie's value.
            if ( $sig eq '$' && $kind eq 'binds' && $Chalk::IR::Analysis::TIED{ refaddr($v) } ) {
                my $r = $b->emit(op => 'NewArray', type => '%Array*');
                for my $e (@rest) {
                    if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $r, $b->array_of($e) ]) }
                    else { $b->emit(op => 'APush', type => 'void', inputs => [ $r, $b->as($b->value($e), '%Slot') ]) }
                }
                return $b->emit(op => 'TieScalar', type => '%Slot', inputs => [ $b->as($b->value($cls), '%Slot'), $r ]);
            }
            out("a $name of a scalar") unless $sig =~ /\A[\@%]\z/;
            my $h = $sig eq '%';
            my $box = $h ? $b->hash_of($c) : $b->array_of($c);
            if ($kind eq 'tied_object') { return $b->emit(op => $h ? 'TiedH' : 'TiedA', type => '%Slot', inputs => [$box]) }
            $b->hash_reads_settled("a $name");
            if ($kind eq 'unbinds') {
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
        if ($kind eq 'unpacked') {
            $b->list_only($v, 'an unpack');
            my @a = grep { blessed($_) } @in;
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
        if ($kind eq 'file_names') {
            $b->list_only($v, 'a glob');
            my @a = grep { blessed($_) } @in;
            out('a glob of other than one pattern') unless @a == 1;
            my $lit = $a[0];
            $lit = $lit->inputs->[0] while $lit->operation eq 'Coerce';
            out('a glob pattern with whitespace (several patterns to perl)') if $lit->operation eq 'Constant' && ( $lit->value // '' ) =~ /\s/;
            out('a glob pattern with a brace (perl keeps its alternatives in order)') if $lit->operation eq 'Constant' && ( $lit->value // '' ) =~ /\{/;
            return $b->emit(op => 'Glob', type => '%Array*', inputs => [ $b->as($b->value($a[0]), '%Str') ]);
        }
        if ( ( $v->builtin_family // '' ) eq 'array' ) {
            return $b->emit(op => $kind eq 'takes_first' ? 'AShift' : 'APop', type => '%Slot', inputs => [ $b->array_of($in[0]) ]);
        }
        if ($kind eq 'joined') {
            my @args = @in;
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

# _scalar_ref_of($t) -> what `\T` is a reference to a scalar of, T2's to make
# (scalar_ref): a `my` scalar kept in memory, a literal, or a choice of such.
sub _scalar_ref_of {
    my ($t) = @_;
    return 0 unless blessed($t);
    return 1 if $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$' && $t->is_location;
    return 1 if $t->operation eq 'Constant' && ( $t->const_type // '' ) =~ /\A(?:integer|number|string|undef)\z/;
    return $t->operation eq 'TernaryExpr' && !_is_list($t) && _scalar_ref_of( $t->inputs->[1] ) && _scalar_ref_of( $t->inputs->[2] ) ? 1 : 0;
}

# scalar_ref($Ref, $t) -> `\T` for a T _scalar_ref_of: a `my` scalar's own
# cell, on the heap (tag 9); a literal's read-only cell, one per site (perl's
# reference is to the constant itself: a store through it dies); a choice of
# such, the reference the arm taken makes.
sub scalar_ref {
    my ($b, $v, $t) = @_;
    my $op = $t->operation;
    if ( $op eq 'PadAccess' ) {
        # (A `my` MADE ANEW EACH PASS -- B::SoN's fresh_each_pass on the Ref,
        # `my $x` in a loop's body, `\$x` taken -- is a cell of its own each
        # pass: fresh_cell. Any other is the function's one variable, its one
        # cell, wherever the reference is made: an arm, a body.)
        out('a reference to a `my` made anew each pass that T2 keeps one of') if $v->fresh_each_pass && !$b->fresh_var($t);
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($t) ]);
    }
    if ( $op eq 'Constant' ) {
        my $k = $b->{ro_cells}{ refaddr($v) . ':' . refaddr($t) } //= $b->{ro_n}++;
        out('more than 256 references to literals') if $k >= 256;
        my $cell = $b->emit(op => 'ROCell', type => '%Slot*', attr => { index => $k });
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->as( $b->value($t), '%Slot' ), $cell ]);
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [$cell]);
    }
    # A CHOICE: each arm's reference made in its own block, the taken one's at the join.
    my ( $cond, $then, $else ) = $t->inputs->@*;
    my $c = $b->truth( $b->value($cond) );
    my $from = $b->{cur};
    my $tb = $b->new_block('then');
    my $tv = do { local $b->{memo} = { $b->{memo}->%* }; local $b->{depth} = ( $b->{depth} // 0 ); $b->scalar_ref( $v, $then ) };
    my $tend = $b->{cur};
    my $eb = $b->new_block('else');
    my $ev = do { local $b->{memo} = { $b->{memo}->%* }; $b->scalar_ref( $v, $else ) };
    my $eend = $b->{cur};
    my $jb = $b->new_block('join');
    $from->{term} = [ 'condbr', $c, $tb, $eb ];
    $tend->{term} = [ 'br', $jb ];
    $eend->{term} = [ 'br', $jb ];
    return $b->emit(op => 'Phi', type => '%Slot', inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
}

# item_refs($Ref) -> the list `\(c ? ($x, $y) : ())` is (_refs_each_item): the
# arm taken's items, a reference to each (scalar_ref), made in its own block.
sub item_refs {
    my ($b, $v) = @_;
    return $b->{memo}{ 'refs:' . refaddr($v) } if $b->{memo}{ 'refs:' . refaddr($v) };
    my ( $cond, $then, $else ) = $v->inputs->[0]->inputs->@*;
    my $c = $b->truth( $b->value($cond) );
    my $from = $b->{cur};
    my $arm = sub ($x) {
        local $b->{memo} = { $b->{memo}->%* };
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        my @items = $x->operation eq 'ArrayLiteral' && !defined $x->symbol ? $x->inputs->@* : ($x);
        $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->scalar_ref( $v, $_ ) ]) for grep { blessed($_) } @items;
        return $a;
    };
    my $tb = $b->new_block('then');
    my $tv = $arm->($then);
    my $tend = $b->{cur};
    my $eb = $b->new_block('else');
    my $ev = $arm->($else);
    my $eend = $b->{cur};
    my $jb = $b->new_block('join');
    $from->{term} = [ 'condbr', $c, $tb, $eb ];
    $tend->{term} = [ 'br', $jb ];
    $eend->{term} = [ 'br', $jb ];
    return $b->{memo}{ 'refs:' . refaddr($v) } = $b->emit(op => 'Phi', type => '%Array*', inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
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
    # THE WHOLE ARRAY READ WHERE B::SoN SAYS PERL MAY DIE (its deref names its
    # site and strict refs): for this array only, not one read to make it.
    my $whole = delete local $b->{whole_die};
    # A split: its fields, from its pattern's graph (the split flavor).
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->regex_split($n) ])
        if blessed($n) && $n->operation eq 'Call' && $n->splits_a_string;
    # A MATCH IN LIST CONTEXT: its groups (or 1), or with /g every match's --
    # the list its pattern's graph (the list or all flavor) makes.
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->regex_list($n) ])
        if blessed($n) && $n->operation =~ /\A(?:RegexMatch|Match)\z/;
    # A SLURPY ARRAY PARAMETER: its copy, made at the sub's entry (args_rest).
    return $b->{memo}{ refaddr($n) } if blessed($n) && $n->operation eq 'Parameter' && $b->{memo}{ refaddr($n) };
    # `\(@a)`: a list of a reference to each element (t2_aelem_refs).
    if (blessed($n) && $n->operation eq 'Ref' && $n->each && $n->is_element_ref) {
        if ( my $why = $n->element_ref_unsound ) { out($why) }
        $b->list_only($n, 'a reference to each element');
        return $b->{memo}{ 'each:' . refaddr($n) } //= $b->emit(op => 'AElemRefs', type => '%Array*', inputs => [ do { local $b->{writing} = 1; $b->array_of( $n->inputs->[0] ) } ]);
    }
    return $b->item_refs($n) if _refs_each_item($n);
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
    # A CALL OF A SUB A GLOB IS GIVEN AT RUN TIME: its wrapper hands back a
    # list's reference in list context, as a method's does (glob_call).
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ]) if $b->is_glob_call($n);
    # A CALL IN LIST CONTEXT: a sub returning a list gives a reference to it; a
    # sub returning one value is a list of it. A method's sub is not known here.
    if (blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'direct' && ( ( $n->name // '' ) !~ /__(?:ANON|EVAL)__/ || $b->plain_anon($n) )) {
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
        if blessed($n) && $n->operation eq 'Call' && ( ( $n->dispatch_kind // '' ) eq 'indirect' || ( $n->name // '' ) =~ /__(?:ANON|EVAL)__/ && !$b->plain_anon($n) );   # (a closure called directly too)
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
    # (one whose arm is a list -- `$x ? ($x) : ()` B::SoN stamps Unknown --
    # is a list here too: the empty arm is no item, not an undef -- fifth
    # final audit, Q16)
    return $b->list_choice($n) if blessed($n) && $n->operation =~ /\A(?:TernaryExpr|And|Or)\z/
        && ( _is_list($n) || $b->type_of($n) eq '%Array*' || $n->operation eq 'TernaryExpr' && grep { blessed($_) && _is_list($_) } $n->inputs->@[1, 2] );
    # A LIST A LOOP BUILDS (a phi of one, map's ListAppend) is its array.
    return $b->value($n) if blessed($n) && $n->operation =~ /\A(?:Phi|ListAppend)\z/ && $b->type_of($n) eq '%Array*';
    # A HASH IN A LIST is its pairs, key then value (`(0, %h)`, `%$r`, a
    # merge of a hash's versions).
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]) if ( $n isa Chalk::IR::Node && ( $n->is_named_hash || $n->is_package_aggregate && $n->sigil eq '%' ) )
        || blessed($n) && $n->operation eq 'Phi' && !$n->memory && ( $b->agg_versions($n) // '' ) eq '%'
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
        # (READ WHOLE WHERE B::SoN SAYS PERL MAY DIE: perl's die, or empty)
        out('an array through an element read whole') unless $b->{writing} || $b->{elem_read} || $b->{whole_stop} || $whole;
        my $w = $b->{writing} || $b->{whole_stop};
        local $b->{elem_read} = 0;
        local $b->{whole_stop} = 0;
        return $b->whole_deref($whole, $b->value($n)) if $whole && !$b->{writing};
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
    return $b->whole_deref($whole, $b->value($n)) if $whole && !$b->{writing};
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ]);
}

# whole_hash($PostfixDeref, $slot) -> the hash reference $slot, read whole
# through $PostfixDeref: where B::SoN says perl may die there (its site and
# strict refs), checked as perl's (t2_hderef_whole); elsewhere as it is.
sub whole_hash {
    my ($b, $d, $r) = @_;
    return $r unless defined $d->line;
    return $b->{memo}{ 'whole:' . refaddr($d) } //= do {
        my $at = $b->deref_at($d);
        my $h = $b->emit(op => 'HDerefWhole', type => '%Slot', inputs => [ $r ],
            attr => { strict => ( $d->strict ? 1 : 0 ), msg => $at->{msg}, id => $at->{id} });
        $b->after_call;
        $h;
    };
}

# whole_deref($PostfixDeref, $value) -> the array $value refers to, read whole
# where B::SoN says perl may die (t2_aderef_whole): its die names the deref's
# site, and an eval around it catches it.
sub whole_deref {
    my ($b, $d, $r) = @_;
    my $at = $b->deref_at($d);
    my $a = $b->emit(op => 'ADerefWhole', type => '%Array*', inputs => [ $b->as($r, '%Slot') ],
        attr => { strict => ( $d->strict ? 1 : 0 ), msg => $at->{msg}, id => $at->{id} });
    $b->after_call;
    return $a;
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
    my $kind = $s->builtin_kind // '';
    if ($kind eq 'adds_last') {
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
    if ($kind eq 'adds_first') {
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

# element_store($Subscript, $value, $Assign): `$a[i] = v`, `$h{k} = v` --
# what it stores made first, then where (element_place), then the store.
sub element_store {
    my ($b, $target, $v, $s) = @_;
    # perl evaluates what it stores, then where, then stores.
    my $val = $b->as($b->value($v), '%Slot');
    $b->element_place( $target->inputs->@[0, 1], ( $target->can('kind') ? $target->kind // 'array' : 'array' ), $s, $target )->($val);
}

# element_place($container, $index, $kind, @site) -> a sub that stores the
# %Slot it is given into that element. The index (or key) and the container
# are made HERE, the store when the sub is called: a list assign makes every
# target's place first and stores after (perl's order -- `($a[0], $a[$a[0]])
# = ...` reads the second index before the first store). @site: the nodes
# that may carry the store's file and line, the first that does.
sub element_place {
    my ($b, $c, $i, $kind, @site) = @_;
    # (STORED THROUGH AN ELEMENT B::SoN did not make a hash or array first -- a
    # reference from elsewhere: refused, not stopped at run time where it is undef)
    out('a store through an element not made a hash or array first')
        if blessed($c) && $c->operation eq 'Subscript' && !$b->{args}{ refaddr($c) }
        # (an argument read from @_ by place, `$_[0]{n} = 1` in a sub handed
        # places: the argument, as the by-value form's is)
        && !( $b->{argsarr} && blessed( $c->inputs->[0] ) && $c->inputs->[0]->operation eq 'ArgsSource' );
    # (AN ELEMENT OF A SLICE -- grep's or map's $_ over `@a[0, 1]` -- is the
    # array's own element in perl; the slice here is a copy: refused)
    out("a store into a slice's element (perl aliases the array's element)")
        if blessed($c) && $c->operation eq 'Slice';
    if ($kind eq 'hash') {
        my $key = $b->as($b->value($i), '%Str');
        my $ref = $b->hash_of($c);
        return sub ($val) {
            # A HASH READ STILL TO BE MADE, of a version this store replaces, would
            # be made after it and see the new value: refused. (reads_before leaves
            # hash reads in place: made early, one could run above its guard.)
            $b->hash_reads_settled('a hash store');
            $b->reads_before($_) for $b->{passed}->@*;
            $b->emit(op => 'HSet', type => 'void', inputs => [ $ref, $key, $val ]);
            return;
        };
    }
    my ($arr, $idx) = ($c, $i);
    # A LIST WRITTEN OUT (`for ($x, @a[1, 2]) { $_ *= 10 }`, no array of its
    # own): perl's elements are its items' own -- stored through their
    # aliases (an array of them, as @_ is). A named array's (`my @n = sort
    # ...`) are its own.
    my $anon = blessed($arr) && $arr->operation eq 'ArrayLiteral' && !defined $arr->symbol && ( $arr->stamp // '' ) eq 'Array';   # static type
    my $ix  = $b->as($b->value($idx), 'i64');
    my $a   = $anon ? do { local $b->{alias_strict} = 1; $b->alias_list($arr) } : $b->array_of($arr);
    my ($at) = grep { blessed($_) && $_->can('line') && defined $_->line } @site;
    # A STORE INTO @_ (or a list's aliases) is the caller's: a literal there is read-only, and
    # perl dies -- its message, caught, names where (no site from B::SoN for
    # this store: refused where an eval may catch it).
    my $into_args = blessed($arr) && $arr->operation eq 'ArgsSource' || $anon;
    out('a store into @_ of no site, in a program with an eval') if $into_args && !$at && $b->{has_eval};
    return sub ($val) {
        $b->hash_reads_settled('an element store');   # it may be an array read through another name
        $b->emit(op => 'ASet', type => 'void',
            inputs => [ $a, $ix, $val ],
            attr => do {
                # PERL DIES on a store before the start, naming the subscript and where.
                my $msg = $at ? " at " . ( $at->file // '-' ) . " line " . $at->line . ".\n" : ".\n";   # no site from B::SoN yet
                $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
                +{ msg => $msg, id => $b->{strs}{$msg} };
            });
        $b->after_call if $into_args;
        return;
    };
}

1;
