# ABOUTME: The LLVM builder's variables kept in memory: their slots, stores into them,
# ABOUTME: and the reads a store must not overtake (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

use Scalar::Util qw(blessed refaddr);

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

sub hash_reads_settled {
    my ($b, $what) = @_;
    # (ONCE AT A TIME: a read made here may itself settle -- a sort with a
    # comparator, made as a read at a version -- and in again it was the same
    # unmade read, without end: "Deep recursion", then out of memory)
    return if $b->{settling};
    local $b->{settling} = 1;
    for my $ver ($b->{passed}->@*) {
        my @waiting = grep { $b->_through_ref($_) && !$b->{memo}{ refaddr($_) } } +($b->{readers}{ refaddr($ver) } // [])->@*;
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
    $b->reads_before($_) for $b->{passed}->@*;
}

# _through_ref($read) -> true for a read through a reference: a hash element,
# or an array's element, count or copy where the array is a scalar's.
sub _through_ref {
    my ($b, $n) = @_;
    my $op = $n->operation;
    # (a foreach alias read is its element's read)
    if ( $op eq 'PostfixDeref' && ( my $el = $n->alias_element ) ) { return $b->_through_ref($el) }
    if ($op =~ /\A(?:Subscript|Exists)\z/ && ( $n->can('kind') ? $n->kind // '' : '' ) eq 'hash') {
        return $n->inputs->[0]->is_named_hash || $n->inputs->[0]->operation eq 'FieldAccess' ? 0 : 1;   # a `my %h`, a hash field: never a stop
    }
    return 0 unless $op =~ /\A(?:Subscript|Count|PostfixDeref)\z/;
    my $c = $n->inputs->[0];
    $c = $c->inputs->[0] while $c isa Chalk::IR::Node && $c->is_array_deref;
    return 0 unless blessed($c);
    # (a \@a, a [...], @_, a `my @a`, @ARGV: an array it has, never a stop)
    return 0 if $c->operation =~ /\A(?:Ref|ArrayLiteral|ArgsSource)\z/ || $c->is_my_array || $c->is_argv;
    return 1;
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

# reads_before($version): a store replaces a memory version, so every read
# made AT that version is made now, before it -- built at its first use, a
# read after the store saw the store (`my $x = $i; $i = 5; print $x`).
sub reads_before {
    my ($b, $version) = @_;
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
    $b->value($_) for grep { !$_->is_pinned && !$b->_needs_unmade_phi($_, {}) && !$b->_through_ref($_) }
        +($b->{readers}{ refaddr($version) } // [])->@*;
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
        push $r{ refaddr($m) }->@*, $n if $m isa Chalk::IR::Node && $m->is_memory_version;
    }
    # A PACKAGE SCALAR READ WITH NO VERSION: B::SoN reads a write's target
    # node (`$x += 1` reads the node it writes). One write: the read is at that
    # write's memory. Several (local's save, store, restore): no one version --
    # refused where it is read. None: the function's starting memory.
    my @starts = grep { $_->operation eq 'MemStart' } @nodes;
    for my $n (grep { ( $_->is_package_scalar || $_->operation eq 'FieldAccess' ) && !$_->inputs->@* } @nodes) {
        my @w = grep { $_->operation =~ /\A(?:EntryWrite|Assign)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) }
            ( $n->consumers // [] )->@*;
        my %seen; @w = grep { !$seen{ refaddr($_) }++ } @w;
        if (@w > 1) { $b->{unversioned}{ refaddr($n) } = 1; next }
        push $r{ refaddr($_) }->@*, $n for @w ? grep { $_ isa Chalk::IR::Node && $_->is_memory_version } $w[0]->inputs->[2] : @starts;
    }
    $b->{readers} = \%r;
}

# assign($Assign): a store of one value into a variable kept in memory.
sub assign {
    my ($b, $s) = @_;
    return $b->list_assign($s) if $s->can('targets') && defined $s->targets;
    out('a local') if $s->can('local') && $s->local;
    my ($target, $v) = $s->inputs->@[0, 1];
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
    if (blessed($target) && $target->operation eq 'Call' && ( $target->dispatch_kind // '' ) eq 'builtin' && ( $target->name // '' ) eq 'pos') {
        my ( $pc, $zc ) = $b->pos_cells( $target->inputs->[0] );
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->as($b->value($v), '%Slot'), $pc ]);
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->emit(op => 'Undef', type => '%Slot'), $zc ]);
        return;
    }
    my $ptr = $b->location($target);
    $b->reads_before($target->inputs->[0]);
    my $val = $b->as($b->value($v), '%Slot');
    $b->emit(op => 'Store', type => 'void', inputs => [ $val, $ptr ]);
    $b->pos_reset($target);
}

# list_assign($Assign): `my ($x, undef, $y) = LIST`. Its inputs are its
# targets (`targets` of them) and then the list's items: the list is made, and
# each target is its element by place (undef past the end, as perl's). A
# target is the node later reads are, so its value is that element; one kept in
# memory is stored too. An array or hash target (which takes the rest) is not T2's.
sub list_assign {
    my ($b, $s) = @_;
    out('a local') if $s->can('local') && $s->local;
    my @in = $s->inputs->@*;
    pop @in if $s->can('memory_input') && $s->memory_input;
    my @t = splice @in, 0, $s->targets;
    out('a list assignment to an array or hash') if grep {
        !( blessed($_) && ( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$'
                            || $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'undef' ) )
    } @t;
    my $list = $b->emit(op => 'NewArray', type => '%Array*');
    for my $e (grep { blessed($_) } @in) {
        if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
    }
    my %val;
    for my $i (0 .. $#t) {
        my $t = $t[$i];
        next unless $t->operation eq 'PadAccess';
        my $v = $b->emit(op => 'AGet', type => '%Slot', inputs => [ $list, $b->emit(op => 'Const', type => 'i64', attr => { value => $i }) ]);
        $val{ $t->symbol } = $v;
        $b->{lvals}{ $t->symbol } = $v;
        $b->{memo}{ refaddr($t) } = $v;
        $b->emit(op => 'Store', type => 'void', inputs => [ $v, $b->location($t) ]) if $t->is_location;
    }
    # A READ MADE AFTER IT (its input this Assign): the target's element; a
    # variable it does not assign, what the last list assign before it gave
    # (`my ($t) = @_; my ($f) = caller; ... $t`: $t's version is this Assign).
    for my $r (grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@*) {
        next if $b->{memo}{ refaddr($r) } || $b->{args}{ refaddr($r) };
        next if $r->is_assign_target;
        next unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*;
        if ( exists $val{ $r->symbol } ) { $b->{memo}{ refaddr($r) } = $val{ $r->symbol }; next }
        my $last = $b->{lvals}{ $r->symbol } // out('a read after a list assignment of no target (' . $r->symbol . ')');
        # (an argument is read where it is: as `my (...) = @_` reads keep it)
        if ( $b->{args_vals}{ refaddr($last) } ) { $b->{args}{ refaddr($r) } = $last } else { $b->{memo}{ refaddr($r) } = $last }
    }
    push $b->{passed}->@*, $s;
}

1;
