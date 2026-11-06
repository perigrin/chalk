# ABOUTME: T2 for LLVM -- a program built as a new graph typed in LLVM's types (the repr
# ABOUTME: chosen once, here), then printed. Slice 1: straight-line. Out of scope: undef.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# T1 is the Perl graph: its stamps are Perl types. T2 is the target's graph:
# each node carries the LLVM type its value is (perigrin, 2026-11-03). It is
# built fresh -- T1 is never mutated -- and may change shape: a conversion
# between representations is a node of its own (Convert), and so is a call of
# the runtime. Printing T2 decides nothing.
#
# THE REPRESENTATION IS CHOSEN HERE, ONCE. A merge whose arms are of one type
# is that type; arms of different types (a Num and a Str: T1 says Str) are a
# %Slot, each arm boxed into it, read back by its tag. That is the case T1's
# stamp-as-repr got wrong: `$c ? 0.1 + 0.2 : "x"` held as a %Str was its
# printed digits, and compared equal to 0.3.
#
# SLICE 1 is a program with no subs, loops or aggregates: constants,
# arithmetic, numeric comparisons, ?: and //, Concat, an %ENV read, print.
# Any other node makes the whole program fall back to Context.pm (lower
# returns undef), so the slice can only ever add programs, never break one.

class Chalk::Target::LLVM::T2::Node {
    field $op     :param :reader;
    field $type   :param :reader;           # i64 | double | i1 | %Str | %Slot | void
    field $inputs :param :reader = [];
    field $attr   :param :reader = {};
    field $name   :reader;                  # its SSA name, given by the printer
    method set_name ($n) { $name = $n }
}

package Chalk::Target::LLVM::T2;

use Scalar::Util qw(blessed refaddr);

# Undef and a Scalar nothing narrowed are each a %Slot: its tag says which.
my %SCALAR = (Int => 'i64', Num => 'double', Str => '%Str', Boolean => 'i1', Undef => '%Slot', Scalar => '%Slot');
my %ARITH  = (Add => 'add', Subtract => 'sub', Multiply => 'mul');
my %CMP    = (NumLt => 'lt', NumGt => 'gt', NumLe => 'le', NumGe => 'ge', NumEq => 'eq', NumNe => 'ne');

sub _n { Chalk::Target::LLVM::T2::Node->new(@_) }

# lower_program($return_node) -> the module's text, or undef when the program
# is not slice 1's.
sub lower_program {
    my ($class, $ret) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {} }, 'Chalk::Target::LLVM::T2::Builder';
    my $ok = eval { $b->build($ret); 1 };
    return undef unless $ok;
    return Chalk::Target::LLVM::T2::Printer::print_module($b);
}

package Chalk::Target::LLVM::T2::Builder;

use Scalar::Util qw(blessed refaddr);

sub out { die "T2: out of its slices ($_[0])\n" }

sub new_block {
    my ($b, $label) = @_;
    my $blk = { label => $label . scalar(@{ $b->{blocks} }), nodes => [], term => undef };
    push @{ $b->{blocks} }, $blk;
    return $b->{cur} = $blk;
}

sub emit {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::T2::_n(%a);
    push @{ $b->{cur}{nodes} }, $n;
    return $n;
}

# The program: its control chain walked forward from Start to its Return.
sub build {
    my ($b, $ret) = @_;
    out('no Return') unless blessed($ret) && $ret->operation eq 'Return';
    # Back to Start: through a merge's Region and a loop's exit Proj.
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj)\z/ ? $start->inputs->[0]
               : out('no way back to Start from ' . $start->operation);
    }
    $b->{ret} = $ret;
    $b->{passed} = [ _memstarts($ret, 1) ];
    $b->index_readers(_own_nodes($ret));
    $b->new_block('entry');
    $b->make_constant_arrays(_own_nodes($ret));
    $b->{jumps} = {};
    $b->walk($start);
    out('an early exit to a merge never reached') if %{ $b->{jumps} };
    $b->{cur}{term} = [ 'ret' ];
}

# successors($ctl) -> the nodes whose control is $ctl, each once.
sub successors {
    my ($ctl) = @_;
    my %seen;
    return grep { blessed($_) && $_->can('control_in') && blessed($_->control_in)
                  && refaddr($_->control_in) == refaddr($ctl) && !$seen{ refaddr($_) }++ }
           ( $ctl->consumers // [] )->@*;
}

# walk($ctl): the statements after $ctl, in order, to a Return or the end of
# a body. A statement of a kind T2 does not have makes the program fall back:
# skipped, its effect would be lost.
sub walk {
    my ($b, $ctl) = @_;
    while (1) {
        my @s = successors($ctl);
        # ONLY THE PROGRAM'S Return ends it: another hung on the same control is
        # not this program's (a graph built over an earlier one).
        @s = grep { $_->operation ne 'Return' || refaddr($_) == refaddr($b->{ret}) } @s;
        unless (@s) {
            # A MERGE AN EARLIER ARM JUMPED TO, this control its other way in.
            if (my $r = $b->join_jumps($ctl)) { $ctl = $r; next }
            return $ctl;
        }
        out('a control node with ' . scalar(@s) . ' successors') if @s > 1;
        my $s = $s[0];
        my $op = $s->operation;
        return $ctl if $op eq 'Return';
        if ($op eq 'Print') {
            # One print of each argument, in order (perl prints the list).
            $b->emit(op => 'Print', type => 'void', inputs => [ $b->as($b->value($_), '%Str') ]) for $s->inputs->@*;
            $ctl = $s;
        }
        elsif ($op eq 'Loop') { $ctl = $b->loop($s) }
        elsif ($op eq 'If')   { $ctl = $b->if_stmt($s) }
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:push|shift|pop)\z/) {
            $b->array_stmt($s);
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        elsif ($op eq 'Assign') { $b->assign($s); push @{ $b->{passed} }, $s; $ctl = $s }
        # A `my @a` PINNED WHERE IT RUNS (B::SoN pins one in a loop body or an
        # arm): a fresh array there, each time control reaches it.
        elsif ($op eq 'ArrayLiteral' && ( $s->stamp // '' ) eq 'Array') { $b->value($s); $ctl = $s }   # static type
        # A `{...}` PINNED WHERE IT RUNS: a fresh hash there, each time.
        elsif ($op eq 'HashLiteral' && ( $s->stamp // '' ) eq 'HashRef') { $b->value($s); $ctl = $s }   # static type
        # A SHIFT OF @_ BOUND TO AN ARGUMENT is on the chain for its order; its
        # value is the argument. A direct call is made where it stands.
        elsif ($op eq 'Call' && ( $b->{args}{ refaddr($s) } || ( $s->dispatch_kind // '' ) eq 'direct' )) {
            $b->value($s);
            push @{ $b->{passed} }, $s;   # B::SoN versions memory at a call
            $ctl = $s;
        }
        else { out("a statement $op") }
    }
    return $ctl;
}

# A `my` VARIABLE KEPT IN MEMORY (B::SoN's location: passed to a sub, written
# in a loop around a call) is an alloca'd %Slot in its function's entry,
# undef until stored. Only a plain scalar `my` of this function.
sub location {
    my ($b, $pad) = @_;
    out('a variable that is not a `my` scalar kept here')
        unless blessed($pad) && $pad->operation eq 'PadAccess' && $pad->is_location && !$pad->shared
        && ( $pad->sigil // '$' ) eq '$';
    my $key = $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        my $p = Chalk::Target::LLVM::T2::_n(op => 'Alloca', type => '%Slot*', attr => { name => $pad->name });
        unshift @{ $b->{blocks}[0]{nodes} }, $p;
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
    # A HASH ELEMENT READ may stop (through what is no hash reference), so it
    # is made where it stands, under its guard -- and nothing in this slice
    # stores into a hash, so it cannot go stale (`return 0 unless $t; $t->{v}`).
    $b->value($_) for grep { !$b->_needs_unmade_phi($_, {})
                             && !( $_->operation eq 'Subscript' && ( $_->can('kind') ? $_->kind // '' : '' ) eq 'hash' ) }
        @{ $b->{readers}{ refaddr($version) } // [] };
}

sub _needs_unmade_phi {
    my ($b, $n, $seen) = @_;
    return 0 unless blessed($n) && $n->can('operation') && !$seen->{ refaddr($n) }++;
    return 0 if $b->{memo}{ refaddr($n) } || _is_version($n);
    return 1 if $n->operation eq 'Phi';
    return scalar grep { $b->_needs_unmade_phi($_, $seen) } $n->inputs->@*;
}

# _is_version($n) -> true for a memory version: MemStart, a store, a call made
# as a statement, a memory phi.
sub _is_version {
    my ($n) = @_;
    return 0 unless blessed($n) && $n->can('operation');
    my $op = $n->operation;
    return 1 if $op eq 'MemStart' || $op eq 'Assign';
    return 1 if $op eq 'Call' && $n->can('control_in') && blessed($n->control_in);
    return $op eq 'Phi' && Chalk::Target::LLVM::Context::_is_memory_phi($n) ? 1 : 0;
}

# _memory_input($n) -> the memory version a read reads at: its MEMORY input,
# not any input -- a statement call is a version and a value, and reading its
# value is not reading memory (taken so, fact's recursive call was made before
# its if: unbounded). Each op says where its memory input is.
sub _memory_input {
    my ($n) = @_;
    my $op = $n->operation;
    my @in = $n->inputs->@*;
    return $in[0] if $op eq 'PadAccess' && $n->is_location;
    return $in[2] if $op eq 'Subscript';
    return $in[1] if $op eq 'Count' || $op eq 'PostfixDeref';
    return $in[-1] if $op eq 'Call' && $n->can('memory_input') && $n->memory_input;
    return undef;
}

# index_readers(@nodes): each memory version's reads -- the nodes, not on the
# control chain, that take it as an input -- found from the inputs.
sub index_readers {
    my ($b, @nodes) = @_;
    my %r;
    for my $n (@nodes) {
        next if $n->can('control_in') && blessed($n->control_in);
        next if $n->operation =~ /\A(?:Phi|Region|Proj|Start|Return|MemStart)\z/;
        my $m = _memory_input($n);
        push @{ $r{ refaddr($m) } }, $n if _is_version($m);
    }
    $b->{readers} = \%r;
}

# assign($Assign): a store of one value into a variable kept in memory.
sub assign {
    my ($b, $s) = @_;
    out('a list assignment') if $s->can('targets') && defined $s->targets;
    out('a local') if $s->can('local') && $s->local;
    my ($target, $v) = $s->inputs->@[0, 1];
    return $b->element_store($target, $v, $s) if blessed($target) && $target->operation eq 'Subscript';
    my $ptr = $b->location($target);
    $b->reads_before($target->inputs->[0]);
    my $val = $b->as($b->value($v), '%Slot');
    $b->emit(op => 'Store', type => 'void', inputs => [ $val, $ptr ]);
}

# make_constant_arrays(@nodes): an array whose literal holds only constants
# (`my @a = (1, 2)`, `my @a`) is made in the entry block -- first made where it
# was first used, in a loop body it was made again each pass.
# _pinned($n) -> true for a node on the control chain.
sub _pinned { my ($n) = @_; return $n->can('control_in') && blessed($n->control_in) ? 1 : 0 }

sub make_constant_arrays {
    my ($b, @nodes) = @_;
    for my $lit (grep { $_->operation eq 'ArrayLiteral' } @nodes) {
        next if _pinned($lit);   # a `my @a` pinned where it runs: made there
        next if grep { !( blessed($_) && $_->operation eq 'Constant' ) } $lit->inputs->@*;
        $b->value($lit);
    }
}

# hash_value($v, $op) -> the T2 node of a hash reference, or of an element
# read through one; undef for what is not.
sub hash_value {
    my ($b, $v, $op) = @_;
    my @in = $v->inputs->@*;
    if ($op eq 'HashLiteral') {
        out('a hash that is not a {...}') unless ( $v->stamp // '' ) eq 'HashRef'; # static type
        out('a {...} not made where it runs') unless _pinned($v);
        out('a {...} of an odd list') if @in % 2;
        my $h = $b->emit(op => 'HNew', type => '%Slot');
        for (my $i = 0; $i < @in; $i += 2) {
            out('a list in a {...}') if grep { ( $_->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/ } @in[ $i, $i + 1 ]; # static type
            $b->emit(op => 'HSet', type => 'void',
                inputs => [ $h, $b->as($b->value($in[$i]), '%Str'), $b->as($b->value($in[ $i + 1 ]), '%Slot') ]);
        }
        return $h;
    }
    if ($op eq 'Subscript' && ( $v->can('kind') ? $v->kind // '' : '' ) eq 'hash') {
        # THROUGH A REFERENCE a scalar holds: perl's $h->{k}. A named %h is
        # not this slice's.
        out('a hash element of a named hash') if ( $in[0]->can('sigil') ? $in[0]->sigil // '' : '' ) eq '%'
            || $in[0]->operation =~ /\A(?:HashLiteral|EntryDef)\z/ && ( $in[0]->stamp // '' ) eq 'Hash' # static type
            || $in[0]->operation eq 'Constant';   # a package hash by name: $ENV{K}
        return $b->emit(op => 'HGet', type => '%Slot',
            inputs => [ $b->as($b->value($in[0]), '%Slot'), $b->as($b->value($in[1]), '%Str') ]);
    }
    return undef;
}

# array_value($v, $op) -> the T2 node of an array, or of a read of one; undef
# for what is not.
sub array_value {
    my ($b, $v, $op) = @_;
    my @in = $v->inputs->@*;
    if ($op eq 'ArrayLiteral') {
        # ONE NOT MADE AT ENTRY, needed in an arm or a loop body, would be made
        # there -- again each pass, and gone after.
        out('an array first made in an arm or a loop body') if $b->{depth} && !_pinned($v);
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        for my $e (@in) {
            out('a list in an array literal') if ( $e->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($e), '%Slot') ]);
        }
        return $a;
    }
    return $b->array_of($in[0]) if $op eq 'PostfixDeref';
    return $b->emit(op => 'ALen', type => 'i64', inputs => [ $b->array_of($in[0]) ]) if $op eq 'Count';
    if ($op eq 'Subscript') {
        out('a hash element') unless ( $v->can('kind') ? $v->kind // 'array' : 'array' ) eq 'array';
        return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $b->array_of($in[0]), $b->as($b->value($in[1]), 'i64') ]);
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin') {
        my $name = $v->name // '';
        if ($name eq 'shift' || $name eq 'pop') {
            return $b->emit(op => $name eq 'shift' ? 'AShift' : 'APop', type => '%Slot', inputs => [ $b->array_of($in[0]) ]);
        }
        if ($name eq 'join') {
            my @args = @in;
            pop @args if $v->can('memory_input') && $v->memory_input;
            my ($sep, @list) = @args;
            # ONE ARRAY is joined as it is; scalars (an array literal folded to
            # its elements, `"@a"`) go into a fresh array first.
            my $arr = ( @list == 1 && $list[0]->operation =~ /\A(?:ArrayLiteral|PostfixDeref)\z/ ) ? $b->array_of($list[0]) : do {
                my $t = $b->emit(op => 'NewArray', type => '%Array*');
                for my $e (@list) {
                    out('a join of a list') if ( $e->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
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
        } Chalk::Target::LLVM::Context::_program_nodes( $b->{ret} );
        $b->{strs}{' '} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => ' ', id => $b->{strs}{' '} });
    }
    return undef;
}

# array_of($n) -> the %Array* a T1 node names (an ArrayLiteral, a deref of one).
sub array_of {
    my ($b, $n) = @_;
    out('an array that is not a `my` array') unless blessed($n) && $n->operation =~ /\A(?:ArrayLiteral|PostfixDeref)\z/;
    my $a = $b->value($n);
    out('not an array') unless $a->type eq '%Array*';
    return $a;
}

# array_stmt($Call): push, or a shift or pop whose value is not used, in its
# place -- after every read the array's version had.
sub array_stmt {
    my ($b, $s) = @_;
    $b->reads_before($_) for @{ $b->{passed} };
    my @in = $s->inputs->@*;
    pop @in if $s->can('memory_input') && $s->memory_input;
    if ($s->name eq 'push') {
        my ($arr, @vals) = @in;
        my $a = $b->array_of($arr);
        for my $e (@vals) {
            out('a push of a list') if ( $e->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($e), '%Slot') ]);
        }
        return;
    }
    $b->value($s);   # shift, pop: made here, its value memoized for its reader
}

# element_store($Subscript, $value): `$a[i] = v`, the array growing to i.
sub element_store {
    my ($b, $target, $v, $s) = @_;
    out('a hash element store') unless ( $target->can('kind') ? $target->kind // 'array' : 'array' ) eq 'array';
    $b->reads_before($_) for @{ $b->{passed} };
    my ($arr, $idx) = $target->inputs->@[0, 1];
    $b->emit(op => 'ASet', type => 'void',
        inputs => [ $b->array_of($arr), $b->as($b->value($idx), 'i64'), $b->as($b->value($v), '%Slot') ],
        attr => do {
            # PERL DIES on a store before the start, naming the subscript and where.
            my ($at) = grep { $_->can('line') && defined $_->line } $s, $target;
            my $msg = $at ? " at " . ( $at->file // '-' ) . " line " . $at->line . ".\n" : ".\n";   # no site from B::SoN yet
            $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
            +{ msg => $msg, id => $b->{strs}{$msg} };
        });
}

# if_stmt($If) -> the Region the program continues from: the condition, each
# arm walked in its own block from its Proj (0 true, 1 false), and at the join
# a phi of each value the Region merges, from the end of each arm.
sub if_stmt {
    my ($b, $if) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } successors_by_input($if);
    out('an if without two arms') unless $proj{0} && $proj{1};
    # EVERY READ MADE SO FAR IS MADE HERE, before the arms: one built in an arm
    # (before a store there) is the arm's, and a use after the join would load
    # it again, after the store (`my $x = $i; if ($c) { $i = 5 } print $x`).
    $b->reads_before($_) for @{ $b->{passed} };
    my $cond = $b->truth($b->value($if->inputs->[1]));
    my $from = $b->{cur};
    my (%end, %blk, %vals);
    for my $i (0, 1) {
        my $blk = $b->new_block($i ? 'else' : 'then');
        $blk{$i} = $blk;
        local $b->{memo} = { %{ $b->{memo} } };   # an arm's values are the arm's
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        $end{$i} = $b->walk($proj{$i});
        # The arm's memo is kept: its phi inputs are read from it (a call made
        # in the arm is that value, not made again).
        $vals{$i} = { block => $b->{cur}, ctl => $end{$i}, memo => $b->{memo} };
    }
    $from->{term} = [ 'condbr', $cond, $blk{0}, $blk{1} ];
    my ($region) = grep { $_->operation eq 'Region' } ( $end{0}->consumers // [] )->@*;
    # ARMS THAT DO NOT MEET: one leaves early (`// return` in an arm) for a
    # merge further out. That arm waits there (jump); the if goes on from the
    # other, which is where its statements continue (pvm 093).
    unless ($region && grep { refaddr($_) == refaddr($end{1}) } grep { blessed($_) } $region->inputs->@*) {
        my %far = map { my $i = $_; ( $i => [ grep { $_->operation eq 'Region' } ( $end{$i}->consumers // [] )->@* ] ) } 0, 1;
        my ($jump) = grep { my $i = $_; @{ $far{$i} } == 1 && _merges_further($far{$i}[0], $end{ 1 - $i }) } 0, 1;
        out('an if whose arms do not meet') unless defined $jump;
        my $r = $far{$jump}[0];
        push @{ $b->{jumps}{ refaddr($r) } }, { %{ $vals{$jump} }, end => $end{$jump} };
        my $go = 1 - $jump;
        $b->{cur}  = $vals{$go}{block};
        $b->{memo} = $vals{$go}{memo};
        return $end{$go};
    }
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($region)
                      && !Chalk::Target::LLVM::Context::_is_memory_phi($_) } ( $region->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    # Each Region input is an arm's end; the phi's input of the same place is
    # that arm's value -- made in the arm, where it is live.
    my @arm_of = map { my $in = $_; ( grep { refaddr($end{$_}) == refaddr($in) } 0, 1 )[0] } $region->inputs->@*;
    out('an if Region whose ways in are not its arms') if grep { !defined } @arm_of;
    my @made;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        my @in;
        for my $k (0 .. $#arm_of) {
            my $arm = $arm_of[$k];
            local $b->{cur} = $vals{$arm}{block};
            local $b->{memo} = $vals{$arm}{memo};
            push @in, [ $b->as($b->value($p->inputs->[$k]), $ty), $vals{$arm}{block} ];
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block('join');
    $_->{block}{term} = [ 'br', $join ] for values %vals;
    for my $m (@made) {
        my ($p, $ty, $in) = @$m;
        $b->{memo}{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty,
            inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $_->[1] } @$in ] });
    }
    push @{ $b->{passed} }, _memory_phis($region);
    return $region;
}

# _merges_further($region, $ctl) -> true when $ctl reaches $region by the
# control it goes on to -- through the Regions it feeds, and what they head.
sub _merges_further {
    my ($r, $ctl) = @_;
    my (%seen, @q);
    @q = ($ctl);
    while (defined(my $n = shift @q)) {
        next if $seen{ refaddr($n) }++;
        return 1 if refaddr($n) == refaddr($r);
        push @q, grep { blessed($_) && ( $_->operation eq 'Region'
                        || ( $_->can('control_in') && blessed($_->control_in) && refaddr($_->control_in) == refaddr($n) ) ) }
            ( $n->consumers // [] )->@*;
    }
    return 0;
}

# join_jumps($ctl) -> the merge the walk goes on from, or undef: where control
# runs out at $ctl and $ctl feeds a merge an earlier arm jumped to, that merge
# is made -- each jump and this way in a predecessor, each phi's input made in
# its own predecessor's block.
sub join_jumps {
    my ($b, $ctl) = @_;
    my ($r) = grep { $_->operation eq 'Region' && $b->{jumps}{ refaddr($_) } } ( $ctl->consumers // [] )->@*;
    return undef unless $r;
    my @preds = ( @{ delete $b->{jumps}{ refaddr($r) } }, { block => $b->{cur}, ctl => $ctl, end => $ctl, memo => $b->{memo} } );
    my @ways = $r->inputs->@*;
    my @pred_of = map { my $in = $_; ( grep { blessed($in) && refaddr($preds[$_]{end}) == refaddr($in) } 0 .. $#preds )[0] } @ways;
    out('a merge with a way in no arm reached') if grep { !defined } @pred_of;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($r)
                      && !Chalk::Target::LLVM::Context::_is_memory_phi($_) } ( $r->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @made;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        my @in;
        for my $k (0 .. $#pred_of) {
            my $pr = $preds[ $pred_of[$k] ];
            local $b->{cur}  = $pr->{block};
            local $b->{memo} = $pr->{memo};
            push @in, [ $b->as($b->value($p->inputs->[$k]), $ty), $pr->{block} ];
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block('join');
    $_->{block}{term} = [ 'br', $join ] for @preds;
    for my $m (@made) {
        my ($p, $ty, $in) = @$m;
        $b->{memo}{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty,
            inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $_->[1] } @$in ] });
    }
    push @{ $b->{passed} }, _memory_phis($r);
    return $r;
}

# call($Call) -> the %Slot a direct call of a sub returns: its function, made
# once, called with each argument boxed (one not passed is undef).
sub call {
    my ($b, $c) = @_;
    my $sub = $c->target;
    out('a direct call with no sub') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func($sub, $c->name);
    my @args = $c->inputs->@*;
    pop @args if $c->can('memory_input') && $c->memory_input;
    out('a call passing a list') if grep { ( $_->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/ } @args; # static type
    out('a call of a sub with a signature of another arity (perl dies)')
        if $fn->{signature} && @args != $fn->{nargs};
    my @pass = map { $b->as($b->value($_), '%Slot') } @args;
    push @pass, $b->emit(op => 'Undef', type => '%Slot') while @pass < $fn->{nargs};
    splice @pass, $fn->{nargs};
    return $b->emit(op => 'Call', type => '%Slot', inputs => \@pass, attr => { fn => $fn->{name} });
}

# func($sub, $name) -> the T2 function a sub is: `%Slot (%Slot args...)`, its
# body built in its own blocks, made before them so a call of itself finds it.
sub func {
    my ($b, $sub, $name) = @_;
    return $b->{funcs}{$name} if $b->{funcs}{$name};
    my $g = $sub->graph;
    my $ret = $g->returns->[0];
    out("sub $name has no Return") unless blessed($ret) && $ret->operation eq 'Return';
    out("sub $name returns more than one reading") if $ret->inputs->@* > 1;
    my $an = bless {}, 'Chalk::Target::LLVM::Context';
    my @reads = eval { $an->_collect_positional_arg_reads($g, $name) };
    out("sub $name reads \@_ other than by shifts, \$_[N] or a signature")
        if $@ || grep { !blessed($_) } @reads
        or $an->{_args_written} || $an->{_args_read_as_a_list} || $an->{_args_slurpy};
    # A SIGNATURE'S OPTIONAL PARAMETER has a default the body computes: not
    # T2's yet (dropped, `($a, $b = 3)` gave $b undef). Its arity is checked
    # at each call (perl dies on another).
    my $sig = $an->{_args_signature};
    if ($sig) {
        my $decl = $sub->can('signature') ? $sub->signature // {} : {};
        out("sub $name has an optional signature parameter")
            if $decl->{optional} || ( $decl->{mandatory} // scalar @reads ) != @reads;
    }
    ( my $id = $name ) =~ s/\W+/_/g;
    my $fn = $b->{funcs}{$name} = { name => "\@f_$id", nargs => scalar @reads, signature => $sig, blocks => [] };
    my @argn = map { Chalk::Target::LLVM::T2::_n(op => 'Arg', type => '%Slot', attr => { index => $_ }) } 0 .. $#reads;
    $argn[$_]->set_name("%a$_") for 0 .. $#argn;
    local $b->{blocks} = $fn->{blocks};
    local $b->{cur};
    local $b->{locs} = {};
    local $b->{memo} = {};
    local $b->{args} = { map { ( refaddr( $reads[$_] ) => $argn[$_] ) } 0 .. $#reads };
    local $b->{ret} = $ret;
    local $b->{passed} = [ grep { $_->operation eq 'MemStart' } Chalk::Target::LLVM::Context::_graph_component($g) ];
    local $b->{readers};
    $b->index_readers(Chalk::Target::LLVM::Context::_graph_component($g));
    local $b->{depth} = 0;
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj)\z/ ? $start->inputs->[0]
               : out("no way back to Start in $name");
    }
    $b->new_block('entry');
    $b->make_constant_arrays(Chalk::Target::LLVM::Context::_graph_component($g));
    local $b->{jumps} = {};   # this function's early exits
    $b->walk($start);
    out('an early exit to a merge never reached') if %{ $b->{jumps} };
    my $v = $ret->inputs->[0];
    my $r = blessed($v) ? $b->as($b->value($v), '%Slot') : $b->emit(op => 'Undef', type => '%Slot');
    $b->{cur}{term} = [ 'retval', $r ];
    return $fn;
}

# phi_type($Phi) -> a merge's T2 type: its stamp's, except a Str (a Num may
# reach it) or a stamp T1 could not give (a recursive sub's result) -- boxed.
sub phi_type {
    my ($b, $phi) = @_;
    my $st = $phi->stamp // ''; # static type
    return '%Slot' if $st =~ /\A(?:Str|Unknown|None|Scalar)\z/;
    return $SCALAR{$st} // out("a phi stamped $st");
}

# loop($Loop) -> the control node the program continues from: a header of
# phis (each its initial value, then the body's) and the condition, a body
# walked forward back to the header, and an exit.
sub loop {
    my ($b, $L) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } successors_by_input($L);
    my ($bodyp, $exitp) = @proj{0, 1};
    out('a loop without a body and an exit') unless $bodyp && $exitp;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($L)
                      && !Chalk::Target::LLVM::Context::_is_memory_phi($_) } ( $L->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @cond = grep { $_->operation !~ /\A(?:Phi|Proj)\z/ } successors($L);
    out('a loop condition that is not one value') unless @cond == 1;
    out('a loop phi with other than two ways in') if grep { scalar( @{ $_->inputs } ) != 2 } @phis;

    $b->reads_before($_) for @{ $b->{passed} };   # see if_stmt
    my $pre = $b->{cur};
    my @init = map { $b->as($b->value($_->inputs->[0]), $b->loop_type($_)) } @phis;
    my $pre_end = $b->{cur};
    my $head = $b->new_block('loop');
    $pre_end->{term} = [ 'br', $head ];
    # THE PHI IS MADE NOW, ITS BACK EDGE WHEN THE BODY IS: the body reads it.
    my @t2 = map {
        my $p = $b->emit(op => 'Phi', type => $b->loop_type($phis[$_]), inputs => [ $init[$_] ], attr => { from => [$pre_end] });
        $b->{memo}{ refaddr( $phis[$_] ) } = $p;
    } 0 .. $#phis;
    # Reads at the loop's memory, each pass: made in the header, before the body
    # can store, and seen after the loop (the header runs as it exits).
    my @mphis = _memory_phis($L);
    $b->reads_before($_) for @mphis;
    push @{ $b->{passed} }, @mphis;
    my $cond = $b->truth($b->value($cond[0]));
    my $head_end = $b->{cur};
    my $body = $b->new_block('body');
    my @back;
    {
        # A value made in the body is the body's: not seen after the loop.
        local $b->{memo} = { %{ $b->{memo} } };
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        $b->walk($bodyp);
        @back = map { $b->as($b->value($phis[$_]->inputs->[1]), $t2[$_]->type) } 0 .. $#phis;
    }
    my $body_end = $b->{cur};
    $body_end->{term} = [ 'br', $head ];
    for my $i (0 .. $#t2) {
        push @{ $t2[$i]->inputs }, $back[$i];
        push @{ $t2[$i]->attr->{from} }, $body_end;
    }
    my $exit = $b->new_block('exit');
    $head_end->{term} = [ 'condbr', $cond, $body, $exit ];
    my ($region) = grep { $_->operation eq 'Region' } ( $exitp->consumers // [] )->@*;
    # THE EXIT'S MEMORY is a version too: a read at it, before a store after.
    push @{ $b->{passed} }, _memory_phis($region) if $region;
    return $region // $exitp;
}

# _memory_phis($merge) -> the memory phis a Region or Loop merges.
sub _memory_phis {
    my ($m) = @_;
    my %seen;
    return grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($m)
                  && Chalk::Target::LLVM::Context::_is_memory_phi($_) && !$seen{ refaddr($_) }++ }
           grep { blessed($_) } ( $m->consumers // [] )->@*;
}

# _own_nodes($ret) -> the program's own nodes: those of the subs it calls are
# theirs.
sub _own_nodes {
    my ($ret) = @_;
    my @all = Chalk::Target::LLVM::Context::_program_nodes($ret);
    my %callee;
    for my $c (grep { $_->operation eq 'Call' && blessed($_->can('target') ? $_->target : undef) } @all) {
        my $t = $c->target;
        next unless $t->can('graph') && $t->graph;
        $callee{ refaddr($_) } = 1 for Chalk::Target::LLVM::Context::_graph_component($t->graph);
    }
    return grep { !$callee{ refaddr($_) } } @all;
}
sub _memstarts { return grep { $_->operation eq 'MemStart' } _own_nodes($_[0]) }

# successors_by_input($n) -> the nodes that take $n as an input (a Loop's Projs).
sub successors_by_input {
    my ($n) = @_;
    my %seen;
    return grep { blessed($_) && grep({ blessed($_) && refaddr($_) == refaddr($n) } $_->inputs->@*) && !$seen{ refaddr($_) }++ }
           ( $n->consumers // [] )->@*;
}

# A LOOP PHI'S TYPE: its stamp, except a Str one, which a Num may reach on a
# later pass -- boxed, as a merge of differing arms is.
sub loop_type { my ($b, $phi) = @_; return $b->phi_type($phi) }

# The T2 type a T1 value is, decided once.
sub type_of {
    my ($b, $v) = @_;
    my $op = $v->operation;
    return '%Slot' if $op eq 'EnvRead' || $op eq 'DefinedOr';   # may be undef
    # A SUB'S ARGUMENT AND RESULT are whatever its callers pass and it returns:
    # T1 types them per call site (add(2,3) Int, though add(0.5,1) is 1.5),
    # so in T2 each is a %Slot, read by its tag.
    return '%Slot' if $b->{args}{ refaddr($v) };
    # AN ARRAY is an %Array of %Slot, by pointer; a count of it an i64, an
    # element a %Slot (it holds what was stored, by its tag).
    return '%Array*' if $op eq 'ArrayLiteral' || $op eq 'PostfixDeref';
    return 'i64' if $op eq 'Count';
    return '%Slot' if $op eq 'Subscript';
    # A HASH REFERENCE is a %Slot (tag 5) over a %Hash: it is a scalar.
    return '%Slot' if $op eq 'HashLiteral' && ( $v->stamp // '' ) eq 'HashRef'; # static type
    return '%Slot' if $op eq 'Call' && ( $v->name // '' ) =~ /\A(?:shift|pop)\z/;
    return '%Str' if $op eq 'Call' && ( $v->name // '' ) eq 'join';
    return '%Str' if $op eq 'EntryDef';
    return '%Slot' if $op eq 'PadAccess' && $v->is_location;
    return '%Slot' if $op eq 'Increment' || $op eq 'Decrement';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'direct';
    # ARITHMETIC ON A %Slot is perl's: Ints stay Ints until they overflow. Done
    # as doubles (T1 may say Num), fact(20) lost its digits.
    return '%Slot' if $ARITH{$op} && grep { $b->type_of($_) eq '%Slot' } $v->inputs->@[0, 1];
    # NUMIFYING A SCALAR OR A STRING is perl's: an Int stays one, an integer
    # string is parsed whole -- through a double, 9007199254740993 lost its 3.
    return '%Slot' if $op eq 'Coerce' && ( $v->stamp // '' ) eq 'Num' # static type
        && $b->type_of($v->inputs->[0]) =~ /\A%(?:Slot|Str)\z/;
    return $b->phi_type($v) if $op eq 'Phi';
    return '%Slot' if ( $v->stamp // '' ) =~ /\A(?:Unknown|None)\z/; # static type
    if ($op eq 'TernaryExpr') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[1, 2];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    my $st = $v->stamp // ''; # static type
    return $SCALAR{$st} // out("a value stamped $st ($op)");
}

# value($t1) -> the T2 node for a T1 value, built once.
sub value {
    my ($b, $v) = @_;
    return $b->{memo}{ refaddr($v) } //= $b->_value($v);
}

sub _value {
    my ($b, $v) = @_;
    # AN ARGUMENT READ (a shift, $_[N], a signature parameter) is the argument.
    if (my $arg = $b->{args}{ refaddr($v) }) { return $arg }
    my $op = $v->operation;
    my $ty = $b->type_of($v);
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'direct') { return $b->call($v) }
    # A READ OF A VARIABLE KEPT IN MEMORY: a load, where it is first used (or
    # earlier, before a store that replaces its version: reads_before).
    if ($op eq 'PadAccess' && $v->is_location) {
        return $b->as($b->emit(op => 'Load', type => '%Slot', inputs => [ $b->location($v) ]), $ty);
    }
    if (my $h = $b->hash_value($v, $op)) { return $h }
    if (my $arr = $b->array_value($v, $op)) { return $arr }
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
        $b->{strs}{$c} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
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
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
        my $q = $b->emit(op => 'Div', type => 'double',
            inputs => [ map { $b->as($b->value($_), 'double') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        return $b->as($q, $ty);
    }
    if ($op eq 'Modulo') {
        # PERL'S % IS OF INTEGERS, its sign the right side's, and dies on zero.
        out('a % not typed Int') unless $ty eq 'i64';
        my $msg = "Illegal modulus zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'Mod', type => 'i64',
            inputs => [ map { $b->as($b->value($_), 'i64') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
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
    if ($op eq 'Concat') {
        return $b->emit(op => 'Concat', type => '%Str', inputs => [ map { $b->as($b->value($_), '%Str') } $v->inputs->@[0, 1] ]);
    }
    if ($op eq 'EnvRead') {
        my $k = $v->key // out('an EnvRead with no key');
        $b->{strs}{$k} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'Env', type => '%Slot', attr => { key => $k, id => $b->{strs}{$k} });
    }
    if ($op eq 'DefinedOr' || $op eq 'TernaryExpr') {
        # A MERGE: its condition, an arm built in each block, a phi at the join.
        my ($cond, $then, $else);
        if ($op eq 'TernaryExpr') {
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
        { local $b->{memo} = { %{ $b->{memo} } };
          $tv = $b->as( blessed($then) && $then->isa('Chalk::Target::LLVM::T2::Node') ? $then : $b->value($then), $ty ); }
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        { local $b->{memo} = { %{ $b->{memo} } };
          $ev = $b->as($b->value($else), $ty); }
        my $eend = $b->{cur};
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $cond, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => $ty, inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
    out($op);
}

# truth($node) -> an i1: perl's truth of a value of any slice type.
sub truth {
    my ($b, $n) = @_;
    return $n if $n->type eq 'i1';
    return $b->emit(op => 'Truth', type => 'i1', inputs => [$n]);
}

# as($node, $type) -> the node converted to that type (itself if it is one).
sub as {
    my ($b, $n, $ty) = @_;
    return $n if $n->type eq $ty;
    return $b->emit(op => 'Convert', type => $ty, inputs => [$n], attr => { from => $n->type });
}

package Chalk::Target::LLVM::T2::Printer;

use Scalar::Util qw(refaddr);

# THE CONVERSIONS T2 HAS, from>to: the builder asks here before it makes one
# (a program needing another falls back), the printer prints from it.
our %CONVERT = (
    'i64>double' => 'sitofp', 'i64>%Str' => 't2_i64_str', 'double>%Str' => 't2_num_str',
    '%Str>double' => 't2_str_num', 'i1>%Str' => 't2_bool_str', 'i64>%Slot' => 't2_box_i64',
    'double>%Slot' => 't2_box_num', '%Str>%Slot' => 't2_box_str', '%Slot>double' => 't2_slot_num',
    '%Slot>%Str' => 't2_slot_str', 'i1>i64' => 'zext', 'i1>double' => 't2_bool_num',
    '%Slot>i64' => 't2_slot_i64', '%Str>i64' => 't2_str_i64', 'double>i64' => 'fptosi',
    'i64>i1' => 't2_truth_i64', 'double>i1' => 't2_truth_num', '%Str>i1' => 't2_truth_str',
    '%Slot>i1' => 't2_truth_slot', 'i1>%Slot' => 't2_box_bool',
);

# The printer names each node, then writes one line (or a runtime call) per
# node. It chooses nothing: every type is already on the node.
sub print_module {
    my ($bld) = @_;   # not $b: sort below uses $a and $b
    my $i = 0;
    $_->set_name('%v' . $i++) for map { @{ $_->{nodes} } } @{ $bld->{blocks} };
    my @L = ('; chalk T2: a graph typed in LLVM types, printed', _prelude());
    my $strs = $bld->{strs};
    for my $s (sort { $strs->{$a} <=> $strs->{$b} } keys %$strs) {
        my $len = do { use bytes; length $s };
        push @L, sprintf('@s%d = private unnamed_addr constant [%d x i8] c"%s\00"', $strs->{$s}, $len + 1, _c($s));
    }
    push @L, 'define i32 @main() {', _blocks($bld->{blocks}), '}', '';
    # EACH SUB A FUNCTION: `%Slot (%Slot %a0, ...)`, its blocks printed alike.
    for my $fn (sort { $a->{name} cmp $b->{name} } values %{ $bld->{funcs} // {} }) {
        my $i = 0;
        $_->set_name('%v' . $i++) for map { @{ $_->{nodes} } } @{ $fn->{blocks} };
        push @L, "define internal %Slot $fn->{name}(" . join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) . ') {',
            _blocks($fn->{blocks}), '}', '';
    }
    return join("\n", @L);
}

sub _blocks {
    my ($blocks) = @_;
    my @L;
    for my $blk (@$blocks) {
        push @L, "$blk->{label}:";
        push @L, map { '  ' . _line($_) } @{ $blk->{nodes} };
        my ($k, @t) = @{ $blk->{term} // ['ret'] };
        push @L, $k eq 'ret'    ? '  ret i32 0'
               : $k eq 'retval' ? '  ret %Slot ' . $t[0]->name
               : $k eq 'br'     ? "  br label %$t[0]{label}"
               :                    "  br i1 " . $t[0]->name . ", label %$t[1]{label}, label %$t[2]{label}";
    }
    return @L;
}

sub _c { my $s = shift; $s =~ s/([^\x20-\x21\x23-\x5b\x5d-\x7e])/sprintf('\\%02X', ord $1)/ge; $s }

sub _line {
    my ($n) = @_;
    my ($op, $ty, $nm, @in) = ($n->op, $n->type, $n->name, @{ $n->inputs });
    my %a = %{ $n->attr };
    my $arg = sub { join ', ', map { $_->type . ' ' . $_->name } @_ };
    if ($op eq 'Const') {
        return "$nm = add i64 0, " . ( 0 + $a{value} ) if $ty eq 'i64';
        return "$nm = fadd double 0.0, " . _double($a{value}) if $ty eq 'double';
        return "$nm = add i1 0, " . ( $a{value} ? 1 : 0 ) if $ty eq 'i1';
        die "T2: a constant of $ty";
    }
    if ($op eq 'ConstStr') {
        my $len = do { use bytes; length $a{value} };
        return "$nm = call %Str \@t2_str(i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    if ($op eq 'Env') {
        my $len = do { use bytes; length $a{key} };
        return "$nm = call %Slot \@t2_env(i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0))";
    }
    if ($op eq 'Arith') {
        my %fop = (add => 'fadd', sub => 'fsub', mul => 'fmul', div => 'fdiv');
        my $o = $ty eq 'double' ? $fop{ $a{op} } : $a{op};
        return "$nm = $o $ty " . $in[0]->name . ', ' . $in[1]->name;
    }
    if ($op eq 'Cmp') {
        my $t = $in[0]->type;
        my $o = $t eq 'double' ? "fcmp o$a{op}" : 'icmp ' . ( { eq => 'eq', ne => 'ne' }->{ $a{op} } // "s$a{op}" );
        $o = 'fcmp une' if $t eq 'double' && $a{op} eq 'ne';
        return "$nm = $o $t " . $in[0]->name . ', ' . $in[1]->name;
    }
    return "$nm = call %Slot \@t2_slot(i8 0, i64 0)" if $op eq 'Undef';
    return "$nm = call %Slot $a{fn}(" . $arg->(@in) . ')' if $op eq 'Call';
    return "$nm = alloca %Slot  ; my $a{name}\n  store %Slot zeroinitializer, %Slot* $nm" if $op eq 'Alloca';
    return "$nm = load %Slot, %Slot* " . $in[0]->name if $op eq 'Load';
    return "$nm = call %Slot \@t2_slot_numify(" . $arg->(@in) . ')' if $op eq 'Numify';
    return "store %Slot " . $in[0]->name . ", %Slot* " . $in[1]->name if $op eq 'Store';
    return "$nm = call %Slot \@t2_slot_$a{op}(" . $arg->(@in) . ')' if $op eq 'SlotStep';
    return "$nm = call %Slot \@t2_slot_$a{op}(" . $arg->(@in) . ')' if $op eq 'SlotArith';
    if ($op eq 'Mod') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call i64 \@t2_mod(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    if ($op eq 'Div') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call double \@t2_div(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    return "$nm = call %Str \@t2_concat(" . $arg->(@in) . ')' if $op eq 'Concat';
    return "$nm = call %Array* \@t2_new_array()" if $op eq 'NewArray';
    return "$nm = call %Slot \@t2_hnew()" if $op eq 'HNew';
    return "call void \@t2_hset(" . $arg->(@in) . ')' if $op eq 'HSet';
    return "$nm = call %Slot \@t2_hget(" . $arg->(@in) . ')' if $op eq 'HGet';
    return "call void \@t2_apush(" . $arg->(@in) . ')' if $op eq 'APush';
    if ($op eq 'ASet') {
        my $len = do { use bytes; length $a{msg} };
        return "call void \@t2_aset(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    my %aop = (ALen => 'i64 @t2_alen', AGet => '%Slot @t2_aget', AShift => '%Slot @t2_ashift', APop => '%Slot @t2_apop', Join => '%Str @t2_join');
    return "$nm = call $aop{$op}(" . $arg->(@in) . ')' if $aop{$op};
    return "call void \@t2_print(" . $arg->(@in) . ')' if $op eq 'Print';
    return "$nm = call i1 \@t2_defined(" . $arg->(@in) . ')' if $op eq 'Defined';
    if ($op eq 'Truth') {
        my %f = ('i64' => 't2_truth_i64', double => 't2_truth_num', '%Str' => 't2_truth_str', '%Slot' => 't2_truth_slot');
        return "$nm = call i1 \@$f{ $in[0]->type }(" . $arg->(@in) . ')';
    }
    if ($op eq 'Convert') {
        my $f = $CONVERT{"$a{from}>$ty"} // die "T2: no conversion $a{from} -> $ty";
        return "$nm = $f $a{from} " . $in[0]->name . " to $ty" if $f =~ /\A(?:sitofp|zext|fptosi)\z/;
        return "$nm = call $ty \@$f(" . $arg->(@in) . ')';
    }
    if ($op eq 'Phi') {
        return "$nm = phi $ty " . join(', ', map { '[ ' . $in[$_]->name . ", %$a{from}[$_]{label} ]" } 0 .. $#in);
    }
    die "T2: cannot print $op";
}

# A double's bits: a hex pattern as given (0x7FF0000000000000 is +Inf), else
# the value's -- which numifies "Inf" and "NaN" as perl does.
sub _double {
    my $v = shift;
    return uc($v) =~ s/^0X/0x/r if $v =~ /\A0x[0-9a-f]{16}\z/i;
    return '0x' . uc unpack('H16', pack('d>', 0 + $v));
}

# The runtime a slice-1 module calls: %Str is { i8*, i64 }; %Slot is a tag
# (0 undef, 1 Int, 2 Num, 3 Str) and an i64 payload (a Num's bits, a Str's
# heap pointer). Numbers print as perl prints them: %.15g, Inf, -Inf, NaN.
sub _prelude { return <<'LL' }
%Str = type { i8*, i64 }
%Slot = type { i8, i64 }
declare i32 @snprintf(i8*, i64, i8*, ...)
declare i8* @malloc(i64)
declare i8* @memcpy(i8*, i8*, i64)
declare i8* @getenv(i8*)
declare i64 @strlen(i8*)
declare double @strtod(i8*, i8**)
declare i64 @write(i32, i8*, i64)
@fmt_g = private unnamed_addr constant [6 x i8] c"%.15g\00"
@fmt_d = private unnamed_addr constant [4 x i8] c"%ld\00"
@lit_inf = private unnamed_addr constant [4 x i8] c"Inf\00"
@lit_ninf = private unnamed_addr constant [5 x i8] c"-Inf\00"
@lit_nan = private unnamed_addr constant [4 x i8] c"NaN\00"
@lit_one = private unnamed_addr constant [2 x i8] c"1\00"
@lit_zero = private unnamed_addr constant [2 x i8] c"0\00"
define internal %Str @t2_str(i8* %p, i64 %n) {
  %a = insertvalue %Str undef, i8* %p, 0
  %b = insertvalue %Str %a, i64 %n, 1
  ret %Str %b
}
define internal void @t2_print(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 1, i8* %p, i64 %n)
  ret void
}
define internal %Str @t2_concat(%Str %x, %Str %y) {
  %xp = extractvalue %Str %x, 0
  %xn = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yn = extractvalue %Str %y, 1
  %n = add i64 %xn, %yn
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %xp, i64 %xn)
  %mid = getelementptr i8, i8* %buf, i64 %xn
  call i8* @memcpy(i8* %mid, i8* %yp, i64 %yn)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_i64_str(i64 %v) {
  %buf = call i8* @malloc(i64 24)
  %f = getelementptr [4 x i8], [4 x i8]* @fmt_d, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 24, i8* %f, i64 %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_num_str(double %v) {
entry:
  %nan = fcmp uno double %v, %v
  br i1 %nan, label %isnan, label %notnan
isnan:
  %pn = getelementptr [4 x i8], [4 x i8]* @lit_nan, i64 0, i64 0
  %rn = call %Str @t2_str(i8* %pn, i64 3)
  ret %Str %rn
notnan:
  %pinf = fcmp oeq double %v, 0x7FF0000000000000
  br i1 %pinf, label %ispinf, label %notpinf
ispinf:
  %pi = getelementptr [4 x i8], [4 x i8]* @lit_inf, i64 0, i64 0
  %ri = call %Str @t2_str(i8* %pi, i64 3)
  ret %Str %ri
notpinf:
  %ninf = fcmp oeq double %v, 0xFFF0000000000000
  br i1 %ninf, label %isninf, label %finite
isninf:
  %pm = getelementptr [5 x i8], [5 x i8]* @lit_ninf, i64 0, i64 0
  %rm = call %Str @t2_str(i8* %pm, i64 4)
  ret %Str %rm
finite:
  %zero = fcmp oeq double %v, 0.0
  br i1 %zero, label %iszero, label %nonzero
iszero:
  %pz = getelementptr [2 x i8], [2 x i8]* @lit_zero, i64 0, i64 0
  %rz = call %Str @t2_str(i8* %pz, i64 1)
  ret %Str %rz
nonzero:
  %buf = call i8* @malloc(i64 32)
  %f = getelementptr [6 x i8], [6 x i8]* @fmt_g, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 32, i8* %f, double %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal double @t2_str_num(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %d = call double @strtod(i8* %buf, i8** null)
  ret double %d
}
define internal i64 @t2_str_i64(%Str %s) {
  %n = call %Slot @t2_str_numslot(%Str %s)
  %i = call i64 @t2_slot_i64(%Slot %n)
  ret i64 %i
}
declare i64 @strtoll(i8*, i8**, i32)
; A STRING'S NUMBER, perl's way: its leading integer kept whole (strtoll)
; unless a fraction or exponent follows, else its double.
define internal %Slot @t2_str_numslot(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %ep = alloca i8*
  %i = call i64 @strtoll(i8* %buf, i8** %ep, i32 10)
  %e = load i8*, i8** %ep
  %none = icmp eq i8* %e, %buf
  br i1 %none, label %num, label %after
after:
  %c = load i8, i8* %e
  %dot = icmp eq i8 %c, 46
  %ee = icmp eq i8 %c, 101
  %eE = icmp eq i8 %c, 69
  %f1 = or i1 %dot, %ee
  %frac = or i1 %f1, %eE
  %max = icmp eq i64 %i, 9223372036854775807
  %min = icmp eq i64 %i, -9223372036854775808
  %edge = or i1 %max, %min
  %tonum = or i1 %frac, %edge
  br i1 %tonum, label %num, label %int
int:
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
num:
  %d = call double @strtod(i8* %buf, i8** null)
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_numify(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %undef [ i8 1, label %same
                               i8 2, label %same
                               i8 3, label %str
                               i8 5, label %ref ]
same:
  ret %Slot %s
str:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %r = call %Slot @t2_str_numslot(%Str %sv)
  ret %Slot %r
undef:
  %z = call %Slot @t2_box_i64(i64 0)
  ret %Slot %z
ref:
  call void @t2_refscalar()
  unreachable
}
define internal %Str @t2_bool_str(i1 %b) {
  %p = getelementptr [2 x i8], [2 x i8]* @lit_one, i64 0, i64 0
  %n = zext i1 %b to i64
  %r = call %Str @t2_str(i8* %p, i64 %n)
  ret %Str %r
}
define internal double @t2_bool_num(i1 %b) {
  %d = uitofp i1 %b to double
  ret double %d
}
define internal %Slot @t2_slot(i8 %t, i64 %v) {
  %a = insertvalue %Slot undef, i8 %t, 0
  %b = insertvalue %Slot %a, i64 %v, 1
  ret %Slot %b
}
define internal %Slot @t2_box_i64(i64 %v) {
  %s = call %Slot @t2_slot(i8 1, i64 %v)
  ret %Slot %s
}
define internal %Slot @t2_box_num(double %v) {
  %i = bitcast double %v to i64
  %s = call %Slot @t2_slot(i8 2, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_box_str(%Str %v) {
  %m = call i8* @malloc(i64 16)
  %p = bitcast i8* %m to %Str*
  store %Str %v, %Str* %p
  %i = ptrtoint %Str* %p to i64
  %s = call %Slot @t2_slot(i8 3, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_env(i8* %k) {
entry:
  %v = call i8* @getenv(i8* %k)
  %none = icmp eq i8* %v, null
  br i1 %none, label %undef, label %set
undef:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
set:
  %n = call i64 @strlen(i8* %v)
  %s = call %Str @t2_str(i8* %v, i64 %n)
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
define internal %Slot @t2_box_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
declare void @exit(i32)
define internal double @t2_div(double %x, double %y, i8* %msg, i64 %n) {
entry:
  %z = fcmp oeq double %y, 0.0
  br i1 %z, label %die, label %ok
die:
  call i64 @write(i32 2, i8* %msg, i64 %n)
  call void @exit(i32 255)
  unreachable
ok:
  %q = fdiv double %x, %y
  ret double %q
}
define internal i64 @t2_mod(i64 %x, i64 %y, i8* %msg, i64 %n) {
entry:
  %z = icmp eq i64 %y, 0
  br i1 %z, label %die, label %ok
die:
  call i64 @write(i32 2, i8* %msg, i64 %n)
  call void @exit(i32 255)
  unreachable
ok:
  %r = srem i64 %x, %y
  %rnz = icmp ne i64 %r, 0
  %rneg = icmp slt i64 %r, 0
  %yneg = icmp slt i64 %y, 0
  %diff = xor i1 %rneg, %yneg
  %fix = and i1 %rnz, %diff
  %r2 = add i64 %r, %y
  %res = select i1 %fix, i64 %r2, i64 %r
  ret i64 %res
}
; PERL'S ++ AND --. A string of letters then digits, starting with a letter,
; increments by magic ("az" -> "ba", "Zz" -> "AAa", "a9" -> "b0"); any other
; string, and -- always, go by its number -- an Int when it is a whole one.
define internal i1 @t2_is_magic(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %first
first:
  %c0 = load i8, i8* %p
  %l0 = call i1 @t2_is_letter(i8 %c0)
  br i1 %l0, label %loop, label %no
loop:
  %i = phi i64 [ 1, %first ], [ %i1, %next ]
  %digits = phi i1 [ 0, %first ], [ %d1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %yes
body:
  %cp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %cp
  %isl = call i1 @t2_is_letter(i8 %c)
  %ge0 = icmp uge i8 %c, 48
  %le9 = icmp ule i8 %c, 57
  %isd = and i1 %ge0, %le9
  ; a letter after a digit ends the pattern
  %lad = and i1 %isl, %digits
  %neither = xor i1 %isl, true
  %notd = xor i1 %isd, true
  %bad0 = and i1 %neither, %notd
  %bad = or i1 %bad0, %lad
  br i1 %bad, label %no, label %next
next:
  %i1 = add i64 %i, 1
  %d1 = or i1 %digits, %isd
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_is_letter(i8 %c) {
  %lo1 = icmp uge i8 %c, 97
  %lo2 = icmp ule i8 %c, 122
  %lo = and i1 %lo1, %lo2
  %up1 = icmp uge i8 %c, 65
  %up2 = icmp ule i8 %c, 90
  %up = and i1 %up1, %up2
  %r = or i1 %lo, %up
  ret i1 %r
}
define internal %Str @t2_str_magic_inc(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 2
  %buf = call i8* @malloc(i64 %n1)
  %dst = getelementptr i8, i8* %buf, i64 1
  call i8* @memcpy(i8* %dst, i8* %p, i64 %n)
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ %last, %entry ], [ %im1, %carry ]
  %cp = getelementptr i8, i8* %dst, i64 %i
  %c = load i8, i8* %cp
  %isz = icmp eq i8 %c, 122
  %isZ = icmp eq i8 %c, 90
  %is9 = icmp eq i8 %c, 57
  %wrap = or i1 %isz, %isZ
  %wrap2 = or i1 %wrap, %is9
  br i1 %wrap2, label %carry, label %bump
bump:
  %c1 = add i8 %c, 1
  store i8 %c1, i8* %cp
  %r = call %Str @t2_str(i8* %dst, i64 %n)
  ret %Str %r
carry:
  %low = select i1 %isz, i8 97, i8 48
  %w = select i1 %isZ, i8 65, i8 %low
  store i8 %w, i8* %cp
  %im1 = sub i64 %i, 1
  %done = icmp slt i64 %im1, 0
  br i1 %done, label %grow, label %loop
grow:
  ; carried off the front: a new first character of the first's kind
  %f = load i8, i8* %dst
  %fA = icmp eq i8 %f, 65
  %lead = select i1 %fA, i8 65, i8 97
  store i8 %lead, i8* %buf
  %n2 = add i64 %n, 1
  %g = call %Str @t2_str(i8* %buf, i64 %n2)
  ret %Str %g
}
define internal %Slot @t2_num_slot(double %d) {
entry:
  %i = fptosi double %d to i64
  %back = sitofp i64 %i to double
  %whole = fcmp oeq double %back, %d
  %small = fcmp olt double %d, 0x43E0000000000000
  %big = fcmp ogt double %d, 0xC3E0000000000000
  %fits0 = and i1 %small, %big
  %fits = and i1 %whole, %fits0
  br i1 %fits, label %int, label %num
int:
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
num:
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_step(%Slot %s, i64 %by, i1 %magic) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str ]
int:
  %v = extractvalue %Slot %s, 1
  %r = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v, i64 %by)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %num, label %intok
intok:
  %rv = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %rv)
  ret %Slot %si
num:
  %d = call double @t2_slot_num(%Slot %s)
  %dby = sitofp i64 %by to double
  %dr = fadd double %d, %dby
  %sn = call %Slot @t2_box_num(double %dr)
  ret %Slot %sn
str:
  %pv = extractvalue %Slot %s, 1
  %pp = inttoptr i64 %pv to %Str*
  %sv = load %Str, %Str* %pp
  %ism = call i1 @t2_is_magic(%Str %sv)
  %domagic = and i1 %ism, %magic
  br i1 %domagic, label %magicinc, label %strnum
magicinc:
  %ms = call %Str @t2_str_magic_inc(%Str %sv)
  %mslot = call %Slot @t2_box_str(%Str %ms)
  ret %Slot %mslot
strnum:
  %sd = call double @t2_str_num(%Str %sv)
  %sby = sitofp i64 %by to double
  %sr = fadd double %sd, %sby
  %ss = call %Slot @t2_num_slot(double %sr)
  ret %Slot %ss
undef:
  %su = call %Slot @t2_box_i64(i64 %by)
  ret %Slot %su
}
define internal %Slot @t2_slot_inc(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 1, i1 1)
  ret %Slot %r
}
define internal %Slot @t2_slot_dec(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 -1, i1 0)
  ret %Slot %r
}
define internal i1 @t2_defined(%Slot %s) {
  %t = extractvalue %Slot %s, 0
  %d = icmp ne i8 %t, 0
  ret i1 %d
}
define internal double @t2_slot_num(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref ]
int:
  %di = sitofp i64 %v to double
  ret double %di
num:
  %dn = bitcast i64 %v to double
  ret double %dn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %ds = call double @t2_str_num(%Str %sv)
  ret double %ds
undef:
  ret double 0.0
ref:
  call void @t2_refscalar()
  unreachable
}
define internal i64 @t2_slot_i64(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %isint = icmp eq i8 %t, 1
  br i1 %isint, label %int, label %other
int:
  %v = extractvalue %Slot %s, 1
  ret i64 %v
other:
  %d = call double @t2_slot_num(%Slot %s)
  %i = fptosi double %d to i64
  ret i64 %i
}
; PERL'S ARITHMETIC ON TWO SCALARS: two Ints give an Int unless it overflows,
; anything else a Num.
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
define internal %Slot @t2_slot_add(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fadd double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_sub(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fsub double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_mul(%Slot %x, %Slot %y) {
entry:
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %r = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %vx, i64 %vy)
  %ov = extractvalue { i64, i1 } %r, 1
  br i1 %ov, label %nums, label %int
int:
  %v = extractvalue { i64, i1 } %r, 0
  %si = call %Slot @t2_box_i64(i64 %v)
  ret %Slot %si
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fmul double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}

define internal %Str @t2_slot_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref ]
int:
  %si = call %Str @t2_i64_str(i64 %v)
  ret %Str %si
num:
  %dn = bitcast i64 %v to double
  %sn = call %Str @t2_num_str(double %dn)
  ret %Str %sn
str:
  %p = inttoptr i64 %v to %Str*
  %ss = load %Str, %Str* %p
  ret %Str %ss
undef:
  %e = call %Str @t2_str(i8* null, i64 0)
  ret %Str %e
ref:
  call void @t2_refscalar()
  unreachable
}

; %Array: { len, cap, elements } -- a `my @a`, its elements %Slot.
%Array = type { i64, i64, %Slot* }
declare i8* @realloc(i8*, i64)
declare i8* @memmove(i8*, i8*, i64)
define internal %Array* @t2_new_array() {
  %m = call i8* @malloc(i64 24)
  %a = bitcast i8* %m to %Array*
  store %Array zeroinitializer, %Array* %a
  ret %Array* %a
}
define internal i64 @t2_alen(%Array* %a) {
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  ret i64 %n
}
; t2_agrow(a, n): room for n elements, the new ones undef.
define internal void @t2_agrow(%Array* %a, i64 %n) {
entry:
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 1
  %cap = load i64, i64* %cp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %fits = icmp sle i64 %n, %cap
  br i1 %fits, label %fill, label %grow
grow:
  %c2 = mul i64 %cap, 2
  %big = icmp sgt i64 %c2, %n
  %c3 = select i1 %big, i64 %c2, i64 %n
  %c4 = add i64 %c3, 4
  %bytes = mul i64 %c4, 16
  %old = load %Slot*, %Slot** %ep
  %o8 = bitcast %Slot* %old to i8*
  %new8 = call i8* @realloc(i8* %o8, i64 %bytes)
  %new = bitcast i8* %new8 to %Slot*
  store %Slot* %new, %Slot** %ep
  store i64 %c4, i64* %cp
  br label %fill
fill:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %len = load i64, i64* %lp
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %len, %fill ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot zeroinitializer, %Slot* %p
  %i1 = add i64 %i, 1
  br label %loop
done:
  %longer = icmp sgt i64 %n, %len
  %nl = select i1 %longer, i64 %n, i64 %len
  store i64 %nl, i64* %lp
  ret void
}
define internal void @t2_apush(%Array* %a, %Slot %v) {
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %n
  store %Slot %v, %Slot* %p
  ret void
}
define internal %Slot @t2_aget(%Array* %a, i64 %i) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %undef, label %get
get:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %v = load %Slot, %Slot* %p
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
@lit_aset = private unnamed_addr constant [64 x i8] c"Modification of non-creatable array value attempted, subscript \00"
define internal void @t2_aset(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  br i1 %lo, label %die, label %set
set:
  %j1 = add i64 %j, 1
  call void @t2_agrow(%Array* %a, i64 %j1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  store %Slot %v, %Slot* %p
  ret void
die:
  %m = getelementptr [64 x i8], [64 x i8]* @lit_aset, i64 0, i64 0
  call i64 @write(i32 2, i8* %m, i64 63)
  %is = call %Str @t2_i64_str(i64 %i)
  %ip = extractvalue %Str %is, 0
  %in = extractvalue %Str %is, 1
  call i64 @write(i32 2, i8* %ip, i64 %in)
  call i64 @write(i32 2, i8* %at, i64 %atn)
  call void @exit(i32 255)
  unreachable
}
define internal %Slot @t2_apop(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %pop
pop:
  %n1 = sub i64 %n, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %n1)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_ashift(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %shift
shift:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %d = bitcast %Slot* %els to i8*
  %s1 = getelementptr %Slot, %Slot* %els, i64 1
  %s = bitcast %Slot* %s1 to i8*
  %n1 = sub i64 %n, 1
  %bytes = mul i64 %n1, 16
  call i8* @memmove(i8* %d, i8* %s, i64 %bytes)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Str @t2_join(%Str %sep, %Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %e = call %Str @t2_str(i8* null, i64 0)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %acc = phi %Str [ %e, %entry ], [ %acc2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %first = icmp eq i64 %i, 0
  %pre = call %Str @t2_concat(%Str %acc, %Str %sep)
  %acc1 = select i1 %first, %Str %acc, %Str %pre
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  %vs = call %Str @t2_slot_str(%Slot %v)
  %acc2 = call %Str @t2_concat(%Str %acc1, %Str %vs)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret %Str %acc
}
define internal i1 @t2_truth_i64(i64 %v) {
  %b = icmp ne i64 %v, 0
  ret i1 %b
}
define internal i1 @t2_truth_num(double %v) {
  %b = fcmp une double %v, 0.0
  ret i1 %b
}
define internal i1 @t2_truth_str(%Str %s) {
entry:
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %one
one:
  %is1 = icmp eq i64 %n, 1
  br i1 %is1, label %check, label %yes
check:
  %p = extractvalue %Str %s, 0
  %c = load i8, i8* %p
  %zero = icmp eq i8 %c, 48
  br i1 %zero, label %no, label %yes
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_truth_slot(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref ]
int:
  %bi = icmp ne i64 %v, 0
  ret i1 %bi
num:
  %d = bitcast i64 %v to double
  %bn = fcmp une double %d, 0.0
  ret i1 %bn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %bs = call i1 @t2_truth_str(%Str %sv)
  ret i1 %bs
undef:
  ret i1 0
ref:
  ret i1 1
}
; A HASH REFERENCE is a %Slot of tag 5 whose payload is an %Array of its
; pairs, key (a boxed Str) then value, in insertion order (perl's own order
; is not promised; keys/each are not this slice's).
declare i32 @memcmp(i8*, i8*, i64)
@msg_notahash = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a hash element read through no HASH reference\0A\00"
@msg_refstr = private unnamed_addr constant [62 x i8] c"chalk: refused at run time: a reference read as a str or num\0A\00"
define internal void @t2_stop(i8* %m, i64 %n) {
  %w = call i64 @write(i32 2, i8* %m, i64 %n)
  call void @exit(i32 255)
  unreachable
}
define internal void @t2_refscalar() {
  call void @t2_stop(i8* getelementptr ([62 x i8], [62 x i8]* @msg_refstr, i64 0, i64 0), i64 61)
  unreachable
}
define internal %Slot @t2_hnew() {
  %a = call %Array* @t2_new_array()
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 5, i64 %i)
  ret %Slot %s
}
define internal %Array* @t2_harr(%Slot %h) {
entry:
  %t = extractvalue %Slot %h, 0
  %ok = icmp eq i8 %t, 5
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_notahash, i64 0, i64 0), i64 74)
  unreachable
yes:
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
; t2_hfind(a, k) -> the index of k's key slot, or -1.
define internal i64 @t2_hfind(%Array* %a, %Str %k) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %kp = extractvalue %Str %k, 0
  %kl = extractvalue %Str %k, 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ks = call %Slot @t2_aget(%Array* %a, i64 %i)
  %kstr = call %Str @t2_slot_str(%Slot %ks)
  %ol = extractvalue %Str %kstr, 1
  %samelen = icmp eq i64 %ol, %kl
  br i1 %samelen, label %cmp, label %next
cmp:
  %op = extractvalue %Str %kstr, 0
  %c = call i32 @memcmp(i8* %op, i8* %kp, i64 %kl)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i2 = add i64 %i, 2
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
define internal %Slot @t2_hget(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %undef, label %get
get:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal void @t2_hset(%Slot %h, %Str %k, %Slot %v) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %add, label %put
add:
  %ks = call %Slot @t2_box_str(%Str %k)
  call void @t2_apush(%Array* %a, %Slot %ks)
  call void @t2_apush(%Array* %a, %Slot %v)
  ret void
put:
  %j = add i64 %i, 1
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  store %Slot %v, %Slot* %p
  ret void
}
LL

1;
