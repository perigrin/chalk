# ABOUTME: The LLVM builder's arrays and hashes: `my` and package aggregates, references to
# ABOUTME: them, their elements, reads and stores (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

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
        out('a {...} not made where it runs') if $st eq 'HashRef' && !$v->is_pinned;
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
    my $kind = $v->can('kind') ? $v->kind // '' : '';
    if ($op =~ /\A(?:Subscript|Exists|Delete)\z/ && $kind eq 'hash') {
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
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        # %$r READ WHOLE: the hash the reference holds; an undefined one is an
        # empty hash here, as in perl (a store through it would autovivify: not this).
        my $h = blessed($in[0]) && $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%'
            ? $b->emit(op => 'HDerefR', type => '%Slot', inputs => [ $b->as($b->value( $in[0]->inputs->[0] ), '%Slot') ])
            : $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]) if $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar';
        return $b->emit(op => $v->name eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
    }
    # sort (by string or by number, either way) and reverse, of a list: a new
    # list. A sort with its own comparator is not T2's yet.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:sort|reverse)\z/
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
        grep { $_->operation eq 'EntryWrite' && $_->binds && ( $_->inputs->[0] isa Chalk::IR::Node && $_->inputs->[0]->is_package_aggregate ) } _all_nodes( $b->{mop}, $b->{ret} ) };
}

sub hash_var {
    my ($b, $pad) = @_;
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) { return $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i }) }
    # A FILE'S HASH (shared with a sub, a sort block): one, in a global, made
    # at its first use from any function.
    return $b->{locs}{ '%file#' . $pad->symbol } //= $b->emit_entry(op => 'GHash', type => '%Slot', attr => { global => $b->global_named( 'my::%' . $pad->symbol ) })
        if $pad->can('file') && $pad->file;
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
    if ($n->operation eq 'FieldAccess') {   # a hash field: its hash
        my (undef, $sg) = $b->field_of($n);
        return $b->value($n) if $sg eq '%';
    }
    # THROUGH AN ELEMENT (`$h{x}{y}`): the reference the element holds. A deref
    # for a write B::SoN spells as the element made a hash first (`//= {}`).
    out('a hash element of a named hash') if ( $n->can('sigil') ? $n->sigil // '' : '' ) eq '%'
        || $n->operation eq 'EntryDef' || $n->operation eq 'Constant';   # a package hash by name: $ENV{K}
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
        # \$x: a reference to the variable itself, kept on the heap (tag 9).
        # (NOT IN A LOOP BODY OR AN ARM: a `my` there is a new variable each time,
        # and the one cell made at entry would be all of them -- `2,2` for perl's `1,2`)
        out('a reference to a scalar in a loop body or an arm') if $b->{depth}
            && blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$';
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($t) ])
            if blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$' && $t->is_location;
        # \%h: a named hash IS its reference here (a %Slot of tag 5), one hash, two names.
        return $b->value($t) if blessed($t) && ( $t->is_named_hash || $t->is_package_aggregate && $t->sigil eq '%' ) && ( $v->stamp // '' ) eq 'HashRef';   # static type
        out('a reference to what is not an array') unless blessed($t)
            && ( $t->operation eq 'ArrayLiteral' && ( $t->stamp // '' ) eq 'Array' || $t->is_array_deref || $t->is_my_array || $t->is_argv
                 || $t->is_package_aggregate && $t->sigil eq '@' ) # static
            && ( $v->stamp // '' ) eq 'ArrayRef';   # \(@a) is a reference to each element type
        return $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->array_of($t) ]);
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
        elsif ($c eq 'map' && !blessed($cond)) {
            if (_is_list($x)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($x) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($x), '%Slot') ]) }
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
        if ($name eq 'shift' || $name eq 'pop') {
            return $b->emit(op => $name eq 'shift' ? 'AShift' : 'APop', type => '%Slot', inputs => [ $b->array_of($in[0]) ]);
        }
        if ($name eq 'join') {
            my @args = @in;
            pop @args if $v->can('memory_input') && $v->memory_input;
            my ($sep, @list) = @args;
            # ONE ARRAY is joined as it is; scalars (an array literal folded to
            # its elements, `"@a"`) go into a fresh array first.
            my $arr = ( @list == 1 && _is_list($list[0]) ) ? $b->array_of($list[0]) : do {
                my $t = $b->emit(op => 'NewArray', type => '%Array*');
                for my $e (@list) {
                    out('a join of a list') if _is_list($e); # static type
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

# array_var($pad): a `my @a` named, not made here (is_my_array): one %Array
# per variable, made at its function's entry -- fresh each call. A closure's
# (shared) is not T2's.
sub array_var {
    my ($b, $pad) = @_;
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) { return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i }) ]) }
    # A FILE'S ARRAY: likewise, the global holding its reference.
    return $b->{locs}{ '@file#' . $pad->symbol } //= $b->emit_entry(op => 'GArray', type => '%Array*', attr => { global => $b->global_named( 'my::@' . $pad->symbol ) })
        if $pad->can('file') && $pad->file;
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
    if (blessed($n) && ( $n->operation =~ /\A(?:ArrayLiteral|ArgsSource)\z/ || $n->is_array_deref || $n->is_my_array || $n->is_argv
                         || $n->is_package_aggregate && $n->sigil eq '@'
                         || $n->operation eq 'FieldAccess' && $b->type_of($n) eq '%Array*'
                         || $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'builtin' && ( $n->name // '' ) =~ /\A(?:keys|values|sort|reverse|caller)\z/ )) {
        my $a = $b->value($n);
        return $a if $a->type eq '%Array*';
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [$a]) if $a->type eq '%Slot';   # [...]
        out('not an array');
    }
    # A CALL IN LIST CONTEXT: a sub returning a list gives a reference to it; a
    # sub returning one value is a list of it. A method's sub is not known here.
    if (blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'direct' && ( $n->name // '' ) !~ /__ANON__/) {
        my $r = $b->value($n);
        my $t = $n->target;
        my $fn = blessed($t) && $t->can('graph') && $t->graph ? $b->{funcs}{ refaddr($t) } : undef;
        out('a list from a call of no sub T2 made') unless $fn;
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [$r]) if $fn->{listret};
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'APush', type => 'void', inputs => [ $a, $r ]);
        return $a;
    }
    # A CALL OF A CODE VALUE IN LIST CONTEXT: its wrapper hands back a list's
    # reference, as a method's does.
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ])
        if blessed($n) && $n->operation eq 'Call' && ( ( $n->dispatch_kind // '' ) eq 'indirect' || ( $n->name // '' ) =~ /__ANON__/ );   # (a closure called directly too)
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
    # A LIST A LOOP BUILDS (a phi of one, map's ListAppend) is its array.
    return $b->value($n) if blessed($n) && $n->operation =~ /\A(?:Phi|ListAppend)\z/ && $b->type_of($n) eq '%Array*';
    # A HASH IN A LIST is its pairs, key then value (`(0, %h)`, `%$r`).
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]) if ( $n isa Chalk::IR::Node && $n->is_named_hash )
        || blessed($n) && $n->operation eq 'FieldAccess' && ( $b->field_of($n) )[1] eq '%';
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n->inputs->[0]) ])
        if blessed($n) && $n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%';
    # THROUGH AN ELEMENT (`$a[1][0]`, `@{$h{l}}`): the array the element holds. A
    # deref for a write B::SoN spells as the element made an array first (`//= []`).
    # (WRITTEN -- push, unshift, ... -- one undef there stops: B::SoN makes it an
    # array first where it can, and a write into a stand-in would be lost)
    # (an ELEMENT read through an undef one is undef, as perl's; read WHOLE --
    # a count, a list -- perl dies under strict and reads undef without: refused)
    if (blessed($n) && $n->operation eq 'Subscript' && !$b->{args}{ refaddr($n) }) {
        out('an array through an element read whole') unless $b->{writing} || $b->{elem_read};
        my $w = $b->{writing};
        local $b->{elem_read} = 0;
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
    # A FLATTENED LIST (`for (@a, @b) { $_ *= 10 }`) is a copy here; perl's
    # elements are the arrays' own.
    out('a store into a flattened list') if blessed($arr) && $arr->operation eq 'ArrayLiteral' && grep { _is_list($_) } $arr->inputs->@*;
    my $val = $b->as($b->value($v), '%Slot');
    my $ix  = $b->as($b->value($idx), 'i64');
    my $a   = $b->array_of($arr);
    $b->hash_reads_settled('an element store');   # it may be an array read through another name
    $b->emit(op => 'ASet', type => 'void',
        inputs => [ $a, $ix, $val ],
        attr => do {
            # PERL DIES on a store before the start, naming the subscript and where.
            my ($at) = grep { $_->can('line') && defined $_->line } $s, $target;
            my $msg = $at ? " at " . ( $at->file // '-' ) . " line " . $at->line . ".\n" : ".\n";   # no site from B::SoN yet
            $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
            +{ msg => $msg, id => $b->{strs}{$msg} };
        });
}

1;
