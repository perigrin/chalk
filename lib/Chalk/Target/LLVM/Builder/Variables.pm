# ABOUTME: The LLVM builder's variables kept in memory: their slots, stores into them,
# ABOUTME: and the reads a store must not overtake (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;


# hash_reads_settled($what): before what may store through a reference (a
# store, a call), no read through one, of a version it replaces, may still be
# to make -- made after, it would see the new value. Refused if one is. Every
# other read waiting is made now (reads_before).
# deref_at($deref) -> { msg, id }: " at FILE line N.\n", for its die.
sub deref_at {
    my ($b, $v) = @_;
    my $msg = " at " . ( $v->can('file') && $v->file // '-' ) . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
    $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
    my $pk = ( $v->can('package') ? $v->package : undef ) // 'main';
    $b->{strs}{$pk} //= scalar keys $b->{strs}->%*;
    return { msg => $msg, id => $b->{strs}{$msg}, pk => $pk, pkid => $b->{strs}{$pk} };
}

# ($only: of the reads waiting, only those it says yes to -- a bless
# replaces what a reference is blessed into and nothing else, so only the
# class reads waiting are made before it.)
sub hash_reads_settled {
    my ($b, $what, $only) = @_;
    # (ONCE AT A TIME: a read made here may itself settle -- a sort with a
    # comparator, made as a read at a version -- and in again it was the same
    # unmade read, without end: "Deep recursion", then out of memory)
    return if $b->{settling};
    local $b->{settling} = 1;
    for my $ver ($b->{passed}->@*) {
        my @waiting = grep { $b->_through_ref($_) && !$b->{memo}{ refaddr($_) } && ( !$only || $only->($_) ) } +($b->{readers}{ refaddr($ver) } // [])->@*;
        # (ONE MADE ALREADY IN A SCOPE NOW CLOSED -- a loop's body, an arm, an
        # arm of @_'s aliases -- was read there, before this: settled. Read
        # again after, refused where it is: value.)
        $b->{arm_settled}{$_} = 1 for grep { $b->{made}{$_} } map { refaddr($_) } @waiting;
        @waiting = grep { !$b->{made}{ refaddr($_) } } @waiting;
        next unless @waiting;
        # MADE HERE WHERE NOTHING RAN BETWEEN: the read's version is the
        # statement just before this one, in this block, and the read is under
        # no ?:, &&, || or // -- so here it reads (or dies) as perl's did there.
        my $at = $b->{at}{ refaddr($ver) }
            // ( $ver->operation eq 'MemStart' ? [ 0, refaddr( $b->{blocks}[0] // 0 ) ] : undef );   # (the function's entry: before its first statement)
        my $next = $at && $at->[0] == $b->{seq} - 1 && $at->[1] == refaddr( $b->{cur} // 0 );
        out("a read through a reference waiting across $what")
            unless $next && !grep { $_->flows_into_choice } @waiting;
        $b->value($_) for @waiting;
    }
    $b->reads_before($_, $only) for $b->{passed}->@*;
}

# class_reads_settled(): a bless replaces what a reference is blessed into,
# so every ref() and blessed() of an earlier memory version still to make is
# made now, before it -- `my $r = ref($h); bless $h, "K"; print $r` is HASH.
sub class_reads_settled {
    my ($b) = @_;
    $b->hash_reads_settled('a bless', sub ($r) { $r->reads_class });
}

# _through_ref($read) -> true for a read through a reference: a hash element,
# or an array's element, count or copy where the array is a scalar's.
sub _through_ref {
    my ($b, $n, $seen) = @_;
    # (A READ MADE ALREADY -- B::SoN pins one that may die where it stands,
    # and the walk makes it there -- stopped, if it was to, there: what reads
    # what it read cannot)
    return 0 if $b->{memo}{ refaddr($n) };
    return 0 if $b->_stood_already($n);
    my $op = $n->operation;
    # (a foreach alias read is its element's read)
    if ( $op eq 'PostfixDeref' && ( my $el = $n->alias_element ) ) { return $b->_through_ref($el, $seen) }
    # (A DEREF OF AN ELEMENT REFERENCE MADE THERE -- `${\ $a[0]}`, a
    # foreach alias's guarded one without strict refs -- reads a cell, or
    # undef: it never stops)
    if ( $op eq 'PostfixDeref' && ( $n->sigil // '' ) eq '$' ) {
        my $r = $n->inputs->[0];
        return 0 if blessed($r) && $r->operation eq 'Ref' && ( $r->element_subscript || $r->hash_element_subscript );
        return 0 if blessed($r) && $r->operation eq 'TernaryExpr' && !$n->strict
            && blessed( $r->inputs->[1] ) && $r->inputs->[1]->operation eq 'Ref' && $r->inputs->[1]->element_subscript
            && Chalk::IR::Node::Ref::_guards( $r, $r->inputs->[1] );
    }
    if ($op =~ /\A(?:Subscript|Exists)\z/ && ( $n->can('kind') ? $n->kind // '' : '' ) eq 'hash') {
        return $n->inputs->[0]->is_named_hash || $n->inputs->[0]->operation eq 'FieldAccess' ? 0 : 1;   # a `my %h`, a hash field: never a stop
    }
    # A READ OF WHAT IS READ THROUGH A REFERENCE (`join "", sort keys
    # %{$s->{k}}`) may stop as that one may: made where it stands too.
    unless ($op =~ /\A(?:Subscript|Count|PostfixDeref)\z/) {
        return 0 if $op =~ /\A(?:Phi|Constant|PadAccess|Parameter|ArgsSource|MemStart)\z/ || ( $seen //= {} )->{ refaddr($n) }++;
        return scalar grep { blessed($_) && !$_->is_memory_version
                             && $b->_through_ref($_, $seen) } $n->inputs->@*;
    }
    my $c = $n->inputs->[0];
    my $derefs = 0;
    while ( $c isa Chalk::IR::Node && $c->is_array_deref ) {
        return 0 if $b->{memo}{ refaddr($c) };   # (made where it stands: see above)
        $c = $c->inputs->[0]; $derefs++;
    }
    return 0 unless blessed($c);
    # (A LIST'S ELEMENT OR COUNT -- foreach over `sort keys %m` -- reads no reference)
    return 0 if !$derefs && $op ne 'PostfixDeref' && _is_list($c) && $c->operation ne 'Phi';
    # (A FRESH {...} is a hash reference: its keys, values, a copy of it never stop)
    return 0 if $op eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%' && $c->operation eq 'HashLiteral' && ( $c->stamp // '' ) eq 'HashRef';   # static type
    return !_own_array($c, {});
}

# _deref_kind($read) -> what a read through a reference needs there: '%' a
# hash, '@' an array, '$' a scalar; undef for what is no such read.
sub _deref_kind {
    my ($n) = @_;
    my $op = $n->operation;
    return $n->sigil // '' if $op eq 'PostfixDeref';
    return ( $n->kind // '' ) eq 'hash' ? '%' : '@' if $op =~ /\A(?:Subscript|Exists)\z/;
    return undef;
}
# _stood_already($read) -> true where a read through the same reference, of
# the same kind, at the same memory -- or the memory this read is at -- was
# pinned where it stands and passed: made, it did not stop, and through that
# same reference, nothing stored between, this cannot; passed unmade (nothing
# took its value), this one is that read -- `my %p = %$h` is B::SoN's copy of
# the deref it pinned -- and stops, if it is to, as T2's read of it does.
sub _stood_already {
    my ($b, $n) = @_;
    my $kind = _deref_kind($n) // return 0;
    my ($c, $m) = ( $n->inputs->[0], $n->memory_operand );
    return 0 unless blessed($c) && blessed($m);
    for my $o (grep { blessed($_) && refaddr($_) != refaddr($n) } ( $c->consumers // [] )->@*) {
        next unless $o->is_pinned && ( $b->{memo}{ refaddr($o) } || $b->{stood}{ refaddr($o) } ) && ( _deref_kind($o) // '' ) eq $kind
            && blessed( $o->inputs->[0] ) && refaddr( $o->inputs->[0] ) == refaddr($c);
        my $om = $o->memory_operand;
        return 1 if refaddr($o) == refaddr($m) || blessed($om) && refaddr($om) == refaddr($m);
    }
    return 0;
}

# _own_array($n) -> true for an array the function has, never a stop: a \@a,
# a [...], @_, a `my @a`, @ARGV -- or a merge (Phi) of only such, a `my @a`
# as a loop or an arm leaves it.
sub _own_array {
    my ($c, $seen) = @_;
    return 0 unless blessed($c);
    return 1 if $c->operation =~ /\A(?:Ref|ArrayLiteral|ArgsSource)\z/ || $c->is_my_array || $c->is_argv;
    # (the list a map or grep builds, a pass at a time: the array it appends to)
    return _own_array($c->inputs->[0], $seen) if $c->operation eq 'ListAppend';
    return 0 unless $c->operation eq 'Phi';
    return 1 if $seen->{ refaddr($c) }++;   # (the loop's own back edge: what the rest says)
    my @in = grep { blessed($_) } $c->inputs->@*;
    return @in && !grep { !_own_array($_, $seen) } @in;
}

# A `my` VARIABLE KEPT IN MEMORY (B::SoN's location: passed to a sub, written
# in a loop around a call) is an alloca'd %Slot in its function's entry,
# undef until stored. Only a plain scalar `my` of this function.
# _own_shared($pad) -> true for a variable B::SoN shares that is this function's
# own: not the file's, in a function that is no closure and makes none -- one
# its sort comparator reads (the sort hands it over: @t2_cmp_env).
sub _own_shared {
    my ($b, $pad) = @_;
    return !( $pad->can('file') && $pad->file ) && !$b->{env}
        && !grep { $_->operation eq 'AnonSub' } +($b->{own_nodes} // [])->@*;
}

sub location {
    my ($b, $pad) = @_;
    # (in a sort comparator, a variable of the sub sorting: its cell, from the env)
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) {
        my $s = $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i });
        return $b->emit(op => 'SCell', type => '%Slot*', inputs => [$s]);
    }
    # A FILE LEXICAL SHARED WITH A NAMED SUB (B::SoN's shared, and no MakeCell
    # here owns it): one variable for the whole program -- the file's scope
    # runs once -- so one global, by its name (B::SoN spells a second `my` of
    # one name apart: `c__2`). The program and each sub reach the same one.
    # shortcut: a file lexical made anew in a loop is one variable here; refuse if a program needs it.
    if (blessed($pad) && $pad->operation eq 'PadAccess' && $pad->can('file') && $pad->file && $pad->is_location
            && ( $pad->sigil // '$' ) eq '$') {
        return $b->emit(op => 'GAddr', type => '%Slot*', attr => { global => $b->global_named( 'my::' . $pad->symbol ) });
    }
    out('a variable that is not a `my` scalar kept here (' . ( blessed($pad) ? $pad->operation . ' ' . ( $pad->can('sigil') ? $pad->sigil // '' : '' )
        . ( $pad->can('symbol') ? $pad->symbol // '' : '' ) . ( $pad->can('shared') && $pad->shared ? ' shared' : '' )
        . ( $pad->can('is_location') && !$pad->is_location ? ' not-location' : '' ) : 'none' ) . ')')
        unless blessed($pad) && $pad->operation eq 'PadAccess' && $pad->is_location
        && ( $pad->sigil // '$' ) eq '$'
        # A SHARED VARIABLE is this function's only where a MakeCell here
        # captures it (it owns it); a named sub's view of an outer `my` is not
        # (its own cell would be another variable: 3 wrong answers).
        && ( !$pad->shared || ( grep { $_->operation eq 'MakeCell' && ( $_->cell_name // '' ) eq $pad->name } +($b->{own_nodes} // [])->@* ) || $b->_own_shared($pad) );
    my $key = $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->fresh_cell($pad, $key) if $b->fresh_var($pad);
    return $b->{locs}{$key} //= do {
        # A VARIABLE A CLOSURE CAPTURES (shared) lives on the heap -- made at
        # its function's entry, fresh each call -- so a closure outliving the
        # call still holds it; the maker and the closure share it.
        # (captured: marked shared, or named by a MakeCell here -- `my ($k) = @_`
        # captured was not marked, and its closure read freed stack: "0 0")
        my $captured = $pad->shared || grep { $_->operation eq 'MakeCell' && ( $_->cell_name // '' ) eq $pad->name } +($b->{own_nodes} // [])->@*;
        # (REFERENCED -- `\$x` -- it outlives the call too)
        $captured ||= grep { $_->operation eq 'Ref' && grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq ( $pad->symbol // '' ) } $_->inputs->@* } +($b->{own_nodes} // [])->@*;
        my $p = Chalk::Target::LLVM::Node::_n(op => ( $captured ? 'HeapCell' : 'Alloca' ), type => '%Slot*', attr => { name => $pad->name });
        unshift $b->{blocks}[0]{nodes}->@*, $p;
        $p;
    };
}

# fresh_var($pad) -> a `my` scalar of this function a reference is taken to
# that B::SoN says is made anew each pass (Ref's fresh_each_pass: `for (...)
# { my $x = $_; push @l, \$x }`), not a closure's: each pass's is a cell
# of its own (fresh_cell). Or one a call is handed as a place B::SoN says is
# made anew each pass (PadAccess fresh_each_pass: the callee may keep
# `\$_[0]`, `3,3,3` for perl's `1,2,3`).
sub fresh_var {
    my ($b, $pad) = @_;
    return 0 unless blessed($pad) && $pad->operation eq 'PadAccess' && ( $pad->sigil // '' ) eq '$' && !$pad->shared;
    return $b->{fresh_vars}{ $pad->name } //= scalar grep {
        $_->operation eq 'Ref' && $_->fresh_each_pass && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'PadAccess'
            && ( $_->inputs->[0]->name // '' ) eq $pad->name
        || $_->operation eq 'PadAccess' && $_->fresh_each_pass && ( $_->name // '' ) eq $pad->name
    } +($b->{own_nodes} // [])->@*;
}

# fresh_made($pad) -> the cell of a fresh_var has been made this pass (or an
# enclosing loop's): its `my` was reached.
sub fresh_made {
    my ($b, $pad) = @_;
    my $key = $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    for ( my $p = $b->{fresh_pass}; $p; $p = $p->{outer} ) { return 1 if $p->{made}{$key} }
    return 0;
}

# fresh_cell($pad, $key) -> the cell of a fresh_var this pass: made where the
# pass first reaches it (its `my`), on the heap -- a reference to it
# outlives the pass -- and held in a slot of the function (a %Slot holding a
# reference to it, made at its entry) for the rest of the pass. First reached
# other than in the body of a loop T2 walks (an arm in it), refused.
sub fresh_cell {
    my ($b, $pad, $key) = @_;
    my $holder = $b->{locs}{"fresh:$key"} //= do {
        my $p = Chalk::Target::LLVM::Node::_n(op => 'Alloca', type => '%Slot*', attr => { name => $pad->name . ' (each pass)' });
        unshift $b->{blocks}[0]{nodes}->@*, $p;
        $p;
    };
    my $pass = $b->{fresh_pass};
    out('a variable made anew each pass first reached outside a loop\'s body') unless $pass;
    # (made by an enclosing loop's pass: an inner loop refers to that one --
    # its own pass made a cell nothing stored, ",,," for "1,1,2,2")
    my $made = 0;
    for ( my $p = $pass; $p && !$made; $p = $p->{outer} ) { $made = $p->{made}{$key} }
    unless ($made) {
        out('a variable made anew each pass first reached in an arm or an inner loop') unless ( $b->{depth} // 0 ) == $pass->{depth};
        my $cell = $b->emit(op => 'NewCell', type => '%Slot*', attr => { name => $pad->name });
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->emit(op => 'SRef', type => '%Slot', inputs => [$cell]), $holder ]);
        $pass->{made}{$key} = 1;
    }
    return $b->emit(op => 'SCell', type => '%Slot*', inputs => [ $b->emit(op => 'Load', type => '%Slot', inputs => [$holder]) ]);
}

# reads_before($version): a store replaces a memory version, so every read
# made AT that version is made now, before it -- built at its first use, a
# read after the store saw the store (`my $x = $i; $i = 5; print $x`).
sub reads_before {
    my ($b, $version, $only) = @_;
    return unless blessed($version);
    # EVERY READ AT IT -- a variable's, an element's, a count -- from the
    # function's own index (readers): a node's consumers need not list every
    # value use, and B::SoN makes one node of a variable at one version, so
    # `my $x = $i; $i = 5` reads the very node it stores to. A read nothing
    # uses costs nothing.
    # A READ IN A LOOP OR AN ARM -- one that needs a phi not yet made, `$a[$i]`
    # in a foreach -- is made in its place: it is there, not here, it is read.
    # A READ THROUGH A REFERENCE may stop (through what is no hash or array
    # reference), so it is made where it stands, under its guard (`return 0
    # unless $t; $t->{v}`); one still to make at a store or a call is refused
    # there (ref_reads_settled), not made after it.
    # (a read pinned on the chain is made where it stands -- a $@ read made
    # early read the inner eval's message after the outer's die: "in" for "out")
    # (A READ AN EVAL'S BODY MADE was made there, before any store after it:
    # its value is dropped only because a die skips it -- not made again here,
    # it is not read here; a use past the eval is refused where it is: value.)
    # (A READ RESTING ON A READ THROUGH A REFERENCE SETTLED IN A SCOPE NOW
    # CLOSED -- `my @l = $c ? $r->@* : ()` in a loop's body, its count at the
    # body's memory -- was made there, of the state there: settled too, not
    # made again here; read again after, refused where it is: value.)
    for my $r (grep { !$only || $only->($_) } +($b->{readers}{ refaddr($version) } // [])->@*) {
        next if $b->{memo}{ refaddr($r) } || !$b->_rests_on_settled($r, {});
        $b->{arm_settled}{ refaddr($r) } = 1;
    }
    do { local $b->{snapshot} = refaddr($_); $b->value($_) } for grep { !$_->is_pinned && !$b->{past_eval}{ refaddr($_) } && !$b->{building}{ refaddr($_) } && !$b->_needs_unmade_phi($_, {}) && !$b->_through_ref($_)
                             && !$b->{arm_settled}{ refaddr($_) } && ( !$only || $only->($_) )
                             # (a variable made anew each pass, read before its `my`: none -- B::SoN's store target;
                             # read after it, this pass, it is made here as any read: a call
                             # storing it through @_ follows -- fifth final audit, Q17, vt87)
                             && !( $_->operation eq 'PadAccess' && $b->fresh_var($_) && !$b->fresh_made($_) ) }
        +($b->{readers}{ refaddr($version) } // [])->@*;
}

# _rests_on_settled($n) -> $n, or a value it is made of (not a memory
# version), is a read through a reference settled where it was made
# (hash_reads_settled) and not made in this scope.
sub _rests_on_settled {
    my ($b, $n, $seen) = @_;
    return 0 unless blessed($n) && $n->can('operation') && !$seen->{ refaddr($n) }++;
    return 0 if $b->{memo}{ refaddr($n) } || $n->is_memory_version;
    return 1 if $b->{arm_settled} && $b->{arm_settled}{ refaddr($n) };
    return scalar grep { $b->_rests_on_settled($_, $seen) } $n->inputs->@*;
}

sub _needs_unmade_phi {
    my ($b, $n, $seen) = @_;
    return 0 unless blessed($n) && $n->can('operation') && !$seen->{ refaddr($n) }++;
    return 0 if $b->{memo}{ refaddr($n) } || $n->is_memory_version;
    return 1 if $n->operation eq 'Phi';
    return scalar grep { $b->_needs_unmade_phi($_, $seen) } $n->inputs->@*;
}

# index_readers(@nodes): each memory version's reads -- the nodes, not on the
# control chain, that take it as an input -- found from the inputs.
sub index_readers {
    my ($b, @nodes) = @_;
    my %r;
    for my $n (@nodes) {
        next if $n->can('control_in') && blessed($n->control_in);
        next if $n->operation =~ /\A(?:Phi|Region|Proj|Start|Return|MemStart)\z/;
        my $m = $n->memory_operand;
        # (A READ AT A CELL MADE -- a closure's capture -- is a read at the
        # version the cell was made at: making a cell writes nothing. Not
        # indexed, `my @k = sort @h` was made after a call of the closure
        # pushing to @h.)
        $m = $m->mem_in while $m isa Chalk::IR::Node && $m->operation eq 'MakeCell';
        push $r{ refaddr($m) }->@*, $n if $m isa Chalk::IR::Node && $m->is_memory_version;
    }
    # A PACKAGE SCALAR READ WITH NO VERSION: B::SoN reads a write's target
    # node (`$x += 1` reads the node it writes). One write: the read is at that
    # write's memory. Several (local's save, store, restore): no one version --
    # refused where it is read. None: the function's starting memory.
    my @starts = grep { $_->operation eq 'MemStart' } @nodes;
    for my $n (grep { ( $_->is_package_scalar || $_->operation eq 'FieldAccess' ) && !blessed( $_->mem_in ) } @nodes) {
        my @w = grep { $_->operation =~ /\A(?:EntryWrite|Assign)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) }
            ( $n->consumers // [] )->@*;
        my %seen; @w = grep { !$seen{ refaddr($_) }++ } @w;
        if (@w > 1) { $b->{unversioned}{ refaddr($n) } = 1; next }
        push $r{ refaddr($_) }->@*, $n for @w ? grep { $_ isa Chalk::IR::Node && $_->is_memory_version } $w[0]->mem_in : @starts;
    }
    $b->{readers} = \%r;
}

# assign($Assign): a store of one value into a variable kept in memory.
sub assign {
    my ($b, $s) = @_;
    return $b->list_assign($s) if $s->can('targets') && defined $s->targets;
    my ($target, $v) = $s->inputs->@[0, 1];
    $b->local_elem($target) if $s->can('local') && $s->local;
    return $b->element_store($target, $v, $s) if blessed($target) && $target->operation eq 'Subscript';
    # $$r = v: into the variable r refers to; perl's die where r is none.
    if (blessed($target) && $target->operation eq 'PostfixDeref' && ( $target->sigil // '' ) eq '$') {
        my $r = $b->as($b->value($target->inputs->[0]), '%Slot');
        my $val = $b->as($b->value($v), '%Slot');
        $b->hash_reads_settled('a store through a reference');
        $b->emit(op => 'SStore', type => 'void', inputs => [ $r, $val ],
            attr => { strict => ( $target->can('strict') && $target->strict ? 1 : 0 ), $b->deref_at($target)->%* });
        $b->after_call;
        return;
    }
    if (blessed($target) && $target->operation eq 'FieldAccess') {
        # A FIELD WRITTEN: what it is given, then the store into its object.
        my ($key, $sg) = $b->field_of($target);
        out("a store to a $sg field") unless $sg eq '$';
        my $self = $b->{self} // out('a field outside a method');
        my $val = $b->as($b->value($v), '%Slot');
        $b->hash_reads_settled('a field store');
        $b->emit(op => 'HSet', type => 'void', inputs => [ $self, $b->const_str($key), $val ]);
        return;
    }
    # A WHOLE AGGREGATE STORED INTO ITS CONTAINER (B::SoN, for a tied one): in
    # place -- CLEAR and STOREs on a tie, else cleared and refilled -- the list
    # its inputs, in order.
    if (blessed($target) && blessed($v) && $v->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/
            && ( $target->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/
                 || $target->operation eq 'PadAccess' && ( $target->sigil // '' ) =~ /\A[\@%]\z/ )) {
        my $h = $target->operation eq 'HashLiteral' || ( $target->can('sigil') && ( $target->sigil // '' ) eq '%' );
        my $list = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (grep { blessed($_) } $v->inputs->@*) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
        }
        $b->hash_reads_settled('a whole assign');
        $b->reads_before($_) for $b->{passed}->@*;
        $b->emit(op => $h ? 'HAssign' : 'AAssign', type => 'void', inputs => [ $h ? $b->hash_of($target) : $b->array_of($target), $list ]);
        return;
    }
    # pos($s) = N: where its next m//g starts
    if (blessed($target) && $target->operation eq 'Call' && $target->gives_match_offset) {
        my ( $pc, $zc ) = $b->pos_cells( $target->inputs->[0] );
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->as($b->value($v), '%Slot'), $pc ]);
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->emit(op => 'Undef', type => '%Slot'), $zc ]);
        return;
    }
    return $b->lvalue_sub_store($target, $v) if blessed($target) && $target->operation eq 'Call' && ( $target->dispatch_kind // '' ) eq 'direct';
    my $ptr = $b->location($target);
    $b->reads_before($target->mem_in);
    my $val = $b->as($b->value($v), '%Slot');
    $b->emit(op => 'Store', type => 'void', inputs => [ $val, $ptr ]);
    $b->pos_reset($target);
}

# lvalue_sub_store($Call, $value): `f() = v` -- perl compiles it only where f
# is an :lvalue sub, whose value is the container it ends at. The value made,
# the sub called, and v stored there: a variable of the file (its global) or
# a package scalar, the same whoever reaches it. Another container -- one of
# the sub's own, an element, a choice -- is refused.
sub lvalue_sub_store {
    my ($b, $c, $v) = @_;
    my $t = $c->target;
    my $ret = blessed($t) && $t->can('graph') && $t->graph ? $t->graph->returns->[0] : undef;
    my $lv = blessed($ret) && $ret->operation eq 'Return' && $ret->inputs->@* == 1 ? $ret->inputs->[0] : undef;
    my $file = blessed($lv) && $lv->operation eq 'PadAccess' && ( $lv->sigil // '' ) eq '$' && $lv->can('file') && $lv->file;
    out('an assignment to an lvalue sub whose value is not a scalar of the file or a package')
        unless $file || blessed($lv) && $lv->is_package_scalar && !( $b->is_topic($lv) && $b->topic_alias );
    my $val = $b->as($b->value($v), '%Slot');
    $b->value($c);
    $b->hash_reads_settled('a store through an lvalue sub');
    $b->reads_before($_) for $b->{passed}->@*;
    # (a package scalar: the one its name holds where the store runs -- a
    # `local`'s or a glob bind's, not the first -- fifth final audit, Q9; one
    # a glob bind may give a literal dies there, which is refused)
    out('an assignment through an lvalue sub to a name a glob bind may give a literal')
        if !$file && $b->bound_scalar($lv) && $b->literal_bound($lv);
    my $ptr = $file ? $b->emit(op => 'GAddr', type => '%Slot*', attr => { global => $b->global_named( 'my::' . $lv->symbol ) })
                    : $b->scalar_addr($lv);
    $b->emit(op => 'Store', type => 'void', inputs => [ $val, $ptr ]);
}

# local_elem($Subscript): `local $r->{k} = ...` -- what the element held and
# whether it existed, saved before the store (the reads B::SoN gives its
# ElemRestore, made now); the ElemRestore at the scope's end puts them back.
# A die unwinding past it would skip the restore: refused where one may.
sub local_elem {
    my ($b, $t) = @_;
    out('a local') unless blessed($t) && $t->operation eq 'Subscript' && ( $t->can('kind') ? $t->kind // '' : '' ) eq 'hash';
    out('a local of an element where a die may unwind past it') if $b->{has_eval};
    # (PERL'S local PUTS A NEW ELEMENT THERE, and the restore the old one back:
    # a reference to the element taken before it keeps the old one. T2 saves
    # and stores the value, into the cell such a reference holds -- refused
    # where the program takes a reference to a hash element, or a sub one into
    # its @_, which may be one.)
    out('a local of a hash element in a program that takes a reference to one (perl\'s local puts a new element there)')
        if $b->{hash_elem_refs} //= ( $b->refs_into_args || scalar grep { $_->operation eq 'Ref' && $_->is_hash_element_ref } _all_nodes( $b->{mop}, $b->{root_ret} // $b->{ret} ) ) ? 1 : 0;
    my @r = grep { $_->operation eq 'ElemRestore' && ( $_->kind // '' ) eq 'hash'
                   && refaddr( $_->inputs->[0] ) == refaddr( $t->inputs->[0] ) && refaddr( $_->inputs->[1] ) == refaddr( $t->inputs->[1] ) }
        +($b->{own_nodes} // [])->@*;
    out('a local of an element restored other than once') unless @r == 1;
    $b->value($_) for $r[0]->inputs->@[2, 3];   # (reads at the version the store replaces: made now, before it)
}

# elem_restore($ElemRestore): the element put back where the scope ends --
# its saved value stored, or (it did not exist) its key deleted.
sub elem_restore {
    my ($b, $s) = @_;
    my ($c, $k, $old, $ex) = $s->inputs->@*;
    out('a restore of an element not saved before its local')
        unless $b->{memo}{ refaddr($old) } && $b->{memo}{ refaddr($ex) };
    my $was = $b->truth( $b->{memo}{ refaddr($ex) } );
    my $sv = $b->as( $b->{memo}{ refaddr($old) }, '%Slot' );
    my $key = $b->as( $b->value($k), '%Str' );
    my $h = $b->hash_of($c);
    $b->hash_reads_settled('a local\'s restore');
    $b->reads_before($_) for $b->{passed}->@*;
    my $from = $b->{cur};
    my $put = $b->new_block('restore');
    $b->emit(op => 'HSet', type => 'void', inputs => [ $h, $key, $sv ]);
    my $del = $b->new_block('unset');
    $b->emit(op => 'HDelete', type => '%Slot', inputs => [ $h, $key ]);
    my $j = $b->new_block('restored');
    $from->{term} = [ 'condbr', $was, $put, $del ];
    $put->{term} = [ 'br', $j ];
    $del->{term} = [ 'br', $j ];
}

# list_assign($Assign): `my ($x, undef, $y) = LIST`. Its inputs are its
# targets (`targets` of them) and then the list's items: the list is made, and
# each target is its element by place (undef past the end, as perl's). A
# target is the node later reads are, so its value is that element; one kept in
# memory is stored too. A `my` array or hash target takes the rest.
sub list_assign {
    my ($b, $s) = @_;
    out('a local') if $s->can('local') && $s->local;
    my @in = $s->inputs->@*;
    my @t = splice @in, 0, $s->targets;
    # @_ ASSIGNED WHOLE (`@_ = ()`, `@_ = (1, 2)`): its elements are the new
    # values, no longer the caller's aliases (audit 3, N2: `@_ = ()` was not
    # applied). The sub's @_ array cleared and refilled where it stands.
    if (@t == 1 && blessed($t[0]) && $t[0]->operation eq 'ArgsSource') {
        my $list = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (grep { blessed($_) } @in) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
        }
        $b->reads_before($_) for $b->{passed}->@*;
        my $args = $b->{argsarr} // out('@_ assigned whole in a sub not taking it as a list');
        $b->emit(op => 'AAssign', type => 'void', inputs => [ $args, $list ]);
        $b->{list_assigned}{ refaddr($s) } = [ $b->emit(op => 'ALen', type => 'i64', inputs => [$list]), $args ];
        push $b->{passed}->@*, $s;
        return;
    }
    # AN ARRAY OR HASH FIELD ASSIGNED WHOLE (`@l = (9)`, `%h = $r->%*`): the
    # list made first (it may read the field), then the field's own
    # aggregate cleared and refilled -- a reference to it sees the new
    # contents. ITS VALUE, a sub's last (`method reset { @l = (9) }`), is by
    # the caller's context: the aggregate as it is now in a list, the count
    # of the list assigned in a scalar (perl's, `%h = ()` 0) -- see func.
    # Taken elsewhere, not T2's.
    if (@t == 1 && blessed($t[0]) && $t[0]->operation eq 'FieldAccess' && ( $b->field_of($t[0]) )[1] =~ /\A[\@%]\z/) {
        my $h = ( $b->field_of($t[0]) )[1] eq '%';
        # (a read after it takes it as its memory; the next statement as its control)
        my @used = grep {
            my $u = $_;
            $u->operation !~ /\A(?:Loop|If|Region|Proj)\z/
                && grep { blessed($_) && refaddr($_) == refaddr($s) } $u->inputs->@*
        } grep { blessed($_) } ( $s->consumers // [] )->@*;
        out('the value of a list assignment to an array or hash') if grep {
            !( $_->operation eq 'Return' && $_->inputs->@* == 1 && blessed( $b->{ret} ) && refaddr($_) == refaddr( $b->{ret} ) && $b->{in_func} )
        } @used;
        my @v = grep { blessed($_) } @in;
        my $list = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@v) {
            if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
        }
        $b->hash_reads_settled('a whole assign');
        $b->reads_before($_) for $b->{passed}->@*;
        my $agg = $h ? $b->hash_of($t[0]) : $b->array_of($t[0]);
        $b->emit(op => $h ? 'HAssign' : 'AAssign', type => 'void', inputs => [ $agg, $list ]);
        # (its value, returned: the count assigned, and the aggregate's list)
        $b->{list_assigned}{ refaddr($s) } = [ $b->emit(op => 'ALen', type => 'i64', inputs => [$list]),
            $h ? $b->emit(op => 'HPairs', type => '%Array*', inputs => [$agg]) : $agg ] if @used;
        push $b->{passed}->@*, $s;
        return;
    }
    # AN ARRAY OR HASH TARGET (`my ($f, @rest) = f()`) takes the rest: a `my`
    # one (the assign is on both chains here, wire v2's L5: its reads are at
    # its version or after). Another (a package's, a closure's) is not T2's.
    # AN ELEMENT, A SLICE, A CAPTURED SCALAR (B::SoN names each by the node
    # that is its place, the Assign on the chain): stored there, see below.
    my $pinned = $s->is_pinned;
    my $is_cell = sub ($t) { $t->operation eq 'MakeCell' && !( blessed( $t->inputs->[0] ) && $t->inputs->[0]->operation eq 'PadAccess' && ( $t->inputs->[0]->sigil // '' ) =~ /\A[\@%]\z/ ) };
    out('a list assignment to an array or hash') if grep {
        !( blessed($_) && ( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$'
                            || $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'undef'
                            || ( $_->is_my_array || $_->is_my_hash ) && !( $_->can('shared') && $_->shared )
                            || $pinned && ( $_->operation =~ /\A(?:Subscript|Slice)\z/ || $is_cell->($_) ) ) )
    } @t;
    my $list = $b->emit(op => 'NewArray', type => '%Array*');
    for my $e (grep { blessed($_) } @in) {
        if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
    }
    # (its value in scalar context: the count of the list assigned)
    $b->{memo}{ refaddr($s) } = $b->emit(op => 'ALen', type => 'i64', inputs => [$list])
        if grep { !( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' ) && $_->operation ne 'Constant' } @t;
    # EVERY PLACE BEFORE ANY STORE, as perl: the list is made, then each
    # target's place (its index or key, its container), then the stores, left
    # to right -- `($a[0], $a[$a[0]]) = ...` reads the second index before the
    # first store. %place: a target => the stores it takes, one per value (a
    # slice one per index, in their order).
    my %place;
    for my $t (@t) {
        if ( $t->operation eq 'Subscript' ) {
            $place{ refaddr($t) } = [ $b->element_place( $t->inputs->@[0, 1], ( $t->can('kind') ? $t->kind // 'array' : 'array' ), $s, $t ) ];
        }
        elsif ( $t->operation eq 'Slice' ) {
            # A SLICE'S INPUTS are its indices (or keys) and then what it is of.
            my @ix = grep { blessed($_) } $t->inputs->@*;
            my $of = pop @ix;
            my $kind = $t->kind // '';
            out("a list assignment to a slice of kind $kind") unless $kind =~ /\A(?:array|hash)\z/;
            # shortcut: how many values a slice takes is how many indices it
            # has, known here only where each is one scalar written out.
            out('a list assignment to a slice whose indices are a list made at run time') if grep { _is_list($_) } @ix;
            out('a list assignment to a slice of @_') if blessed($of) && $of->operation eq 'ArgsSource';
            # B::SoN COUNTS A SLICE AS ONE PLACE: in `(@a[0, 1], $z) = (1, 2, 3)`
            # it binds $z to the 2, and every later read of $z is that constant.
            # Nothing here can put the 3 back: refused.
            out('a list assignment to a slice and then another target (B::SoN binds what follows a slice one place per slice)')
                if @ix != 1 && refaddr($t) != refaddr( $t[-1] );
            $place{ refaddr($t) } = [ map { $b->element_place( $of, $_, $kind, $s, $t ) } @ix ];
        }
        elsif ( $is_cell->($t) ) {
            # A CAPTURED SCALAR: its cell is the variable's own storage (CellWrite).
            my $ptr = $b->value($t);
            $place{ refaddr($t) } = [ sub ($val) {
                $b->hash_reads_settled('a store to a captured variable');
                $b->emit(op => 'Store', type => 'void', inputs => [ $val, $ptr ]);
                return;
            } ];
        }
    }
    my %val;
    my $at = 0;
    for my $t (@t) {
        my $i = $at++;
        if ( my $stores = $place{ refaddr($t) } ) {
            # (each store its value by place, undef past the list's end)
            my $n = 0;
            $_->( $b->emit(op => 'AGet', type => '%Slot', inputs => [ $list, $b->emit(op => 'Const', type => 'i64', attr => { value => $i + $n++ }) ]) ) for $stores->@*;
            $at = $i + $stores->@*;
            next;
        }
        next unless $t->operation eq 'PadAccess';
        if (( $t->sigil // '' ) ne '$') {
            # THE REST, into the variable's own array or hash (in place: a
            # read made before it is made first); nothing is left for a
            # target after it (undef, or empty).
            my $h = $t->sigil eq '%';
            # (A `my` IN A LOOP BODY is a new one each pass, which the wire
            # does not say this is: a reference kept past the pass would see
            # the next pass's -- "3 6 6" for "3 2 6")
            out('a list assignment to an array or hash a reference is taken of, in a loop')
                if $b->{fresh_pass} && grep { blessed($_) && $_->operation eq 'Ref' } ( $t->consumers // [] )->@*;
            my $rest = $b->emit(op => 'ArgsFrom', type => '%Array*', inputs => [ $list, $b->emit(op => 'Const', type => 'i64', attr => { value => $i }) ]);
            # AN ODD LIST INTO A HASH: the last key's value undef, as perl's --
            # which warns of it where warnings may be on, and chalk raises none:
            # stopped there at run time, not answered without the warning.
            if ( $h && Chalk::Impl::warnings_may_be_on( _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) ) ) {
                my $odd = $b->emit(op => 'Arith', type => 'i64', attr => { op => 'and' },
                    inputs => [ $b->emit(op => 'ALen', type => 'i64', inputs => [$rest]), $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }) ]);
                $b->emit(op => 'StopUnless', type => 'void', inputs => [
                    $b->emit(op => 'Cmp', type => 'i1', inputs => [ $odd, $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ], attr => { op => 'eq' }),
                    $b->const_str("an odd number of elements in a hash assignment (perl warns): stopped (chalk, T2)\n") ]);
            }
            $b->hash_reads_settled('a whole assign');
            $b->reads_before($_) for $b->{passed}->@*;
            $b->emit(op => $h ? 'HAssign' : 'AAssign', type => 'void', inputs => [ $h ? $b->hash_of($t) : $b->array_of($t), $rest ]);
            ( $list, $at ) = ( $b->emit(op => 'NewArray', type => '%Array*'), 0 );
            next;
        }
        my $v = $b->emit(op => 'AGet', type => '%Slot', inputs => [ $list, $b->emit(op => 'Const', type => 'i64', attr => { value => $i }) ]);
        $val{ $t->symbol } = $v;
        $b->{lvals}{ $t->symbol } = $v;
        # (A TARGET KEPT IN MEMORY is a read at the version before too, made
        # before this store (Control's walk): it keeps that value -- `($x,$y)
        # = ($y,$x)` with \$x taken gave `2 2` for `2 1` (audit 2026-11-22,
        # risk 4). A read after names this Assign.)
        $b->{memo}{ refaddr($t) } = $v unless blessed( $t->mem_in ) && $b->{memo}{ refaddr($t) };
        $b->emit(op => 'Store', type => 'void', inputs => [ $v, $b->location($t) ]) if $t->is_location;
    }
    # A READ MADE AFTER IT (its input this Assign): the target's element; a
    # variable it does not assign, what the last list assign before it gave
    # (`my ($t) = @_; my ($f) = caller; ... $t`: $t's version is this Assign).
    for my $r (grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' } ( $s->consumers // [] )->@*) {
        next if $b->{memo}{ refaddr($r) } || $b->{args}{ refaddr($r) };
        next if $r->is_assign_target;
        # (B::SoN reads it AT this Assign's version: its mem_in)
        next unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*, $r->mem_in;
        if ( exists $val{ $r->symbol } ) { $b->{memo}{ refaddr($r) } = $val{ $r->symbol }; next }
        # (ONE KEPT IN MEMORY that no list assign gave a value: this one left
        # it as it was, so it is read from its place, as any read of it is --
        # a foreach variable read in a try's catch, stevan/curly brainfuck.pl)
        next if !exists $b->{lvals}{ $r->symbol } && $r->is_location && !$r->place;
        my $last = $b->{lvals}{ $r->symbol } // out('a read after a list assignment of no target (' . $r->symbol . ')');
        # (an argument is read where it is: as `my (...) = @_` reads keep it)
        if ( $b->{args_vals}{ refaddr($last) } ) { $b->{args}{ refaddr($r) } = $last } else { $b->{memo}{ refaddr($r) } = $last }
    }
    push $b->{passed}->@*, $s;
}

# _cell_variable($cell) -> the location a MakeCell holds: the variable of its
# name stored at the memory version it was made at (Values.pm, MakeCell).
sub _cell_variable {
    my ($cell) = @_;
    my $want = $cell->can('cell_name') ? ( $cell->cell_name // '' ) : '';
    my $mem = $cell->mem_in;
    for (1 .. 64) {
        return undef unless blessed($mem);
        my $v = $mem->inputs->[0];
        return $v if blessed($v) && $v->operation eq 'PadAccess' && $v->is_location && $v->name eq $want;
        # (`my ($x, $y) = (1, 2)`: any of a list assign's targets)
        if ( $mem->operation eq 'Assign' && defined $mem->targets ) {
            my ($t) = grep { blessed($_) && $_->operation eq 'PadAccess' && $_->is_location && $_->name eq $want } $mem->inputs->@[ 0 .. $mem->targets - 1 ];
            return $t if $t;
        }
        # Another variable's cell, made just before, is a step too (two captures),
        # as is a location read, at the memory it reads at.
        return undef unless $mem->operation =~ /\A(?:Assign|EntryWrite|Call|MakeCell|PadAccess)\z/;
        $mem = $mem->mem_in;
    }
    return undef;
}

1;
