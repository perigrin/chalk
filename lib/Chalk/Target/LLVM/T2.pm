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
my %SCMP   = (StrEq => 'eq', StrNe => 'ne', StrLt => 'lt', StrGt => 'gt', StrLe => 'le', StrGe => 'ge');
my %CMP    = (NumLt => 'lt', NumGt => 'gt', NumLe => 'le', NumGe => 'ge', NumEq => 'eq', NumNe => 'ne');

sub _n { Chalk::Target::LLVM::T2::Node->new(@_) }

# lower_program($return_node) -> the module's text, or undef when the program
# is not slice 1's.
sub lower_program {
    my ($class, $ret, %opt) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {}, mop => $opt{mop} }, 'Chalk::Target::LLVM::T2::Builder';
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
    $b->emit(op => 'SaveArgs', type => 'void');   # argv, for @ARGV
    $b->make_mop if grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'method' } _all_nodes($b->{mop}, $ret);
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
        # A STATEMENT A READ TAKES AS ITS MEMORY must be a version T2 orders
        # reads by (_is_version): a new store kind missing there let reads after
        # it be made after the next store (three wrong answers, slices 14-15).
        out("a statement $op that versions memory T2 does not order reads by")
            if !_is_version($s) && grep { blessed($_) && refaddr( _memory_input($_) // 0 ) == refaddr($s) } ( $s->consumers // [] )->@*;
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
        # `my (...) = @_` PINNED (a call follows it): its reads are the
        # arguments already (args), nothing to store.
        elsif ($op eq 'Assign' && $b->{args} && $s->can('targets') && defined $s->targets
               && blessed($s->inputs->[-1]) && $s->inputs->[-1]->operation eq 'ArgsSource') {
            $b->{argsarr} ? $b->list_args_assign($s) : $b->args_assign($s);
            $ctl = $s;
        }
        elsif ($op eq 'Assign') { $b->assign($s); push @{ $b->{passed} }, $s; $ctl = $s }
        # A delete (or an exists) on the chain: made where it stands.
        elsif ($op =~ /\A(?:Delete|Exists)\z/ && ( $s->can('kind') ? $s->kind // '' : '' ) eq 'hash') {
            $b->hash_reads_settled('a delete') if $op eq 'Delete';
            $b->value($s);
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # `package X;` names the package code after it is in: nothing T2 reads.
        elsif ($op eq 'PackageMark') { $ctl = $s }
        # A PACKAGE SCALAR WRITTEN: what it held is read first, then stored.
        elsif ($op eq 'EntryWrite' && _pkg_scalar($s->inputs->[0])) {
            out('a local') if $s->can('local') && $s->local;
            my $val = $b->as($b->value($s->inputs->[1]), '%Slot');
            $b->hash_reads_settled('a package store');
            $b->emit(op => 'GStore', type => 'void', inputs => [$val], attr => { global => $b->global_of($s->inputs->[0]) });
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # `@X::ISA = (...)`: the run-time MOP's parents of X, replaced.
        elsif ($op eq 'EntryWrite' && $b->isa_write($s)) { $ctl = $s }
        # A `my @a` PINNED WHERE IT RUNS (B::SoN pins one in a loop body or an
        # arm): a fresh array there, each time control reaches it.
        elsif ($op eq 'ArrayLiteral' && ( $s->stamp // '' ) =~ /\A(?:Array|ArrayRef)\z/) { $b->value($s); $ctl = $s }   # static type
        # A `{...}` PINNED WHERE IT RUNS: a fresh hash there, each time.
        elsif ($op eq 'HashLiteral' && ( $s->stamp // '' ) eq 'HashRef') { $b->value($s); $ctl = $s }   # static type
        # A SHIFT OF @_ BOUND TO AN ARGUMENT is on the chain for its order; its
        # value is the argument. A direct call is made where it stands.
        elsif ($op eq 'Call' && ( $b->{args}{ refaddr($s) } || ( $s->dispatch_kind // '' ) =~ /\A(?:direct|method)\z/ )) {
            $b->value($s);
            push @{ $b->{passed} }, $s;   # B::SoN versions memory at a call
            $ctl = $s;
        }
        else { out("a statement $op" . ( $op eq 'Call' ? ' ' . ( $s->dispatch_kind // '' ) . ' ' . ( $s->name // '' ) : '' )) }
    }
    return $ctl;
}

# hash_reads_settled($what): before what may store through a reference (a
# store, a call), no read through one, of a version it replaces, may still be
# to make -- made after, it would see the new value. Refused if one is. Every
# other read waiting is made now (reads_before).
sub hash_reads_settled {
    my ($b, $what) = @_;
    for my $ver (@{ $b->{passed} }) {
        out("a read through a reference waiting across $what")
            if grep { $b->_through_ref($_) && !$b->{memo}{ refaddr($_) } } @{ $b->{readers}{ refaddr($ver) } // [] };
    }
    $b->reads_before($_) for @{ $b->{passed} };
}

# _through_ref($read) -> true for a read through a reference: a hash element,
# or an array's element, count or copy where the array is a scalar's.
sub _through_ref {
    my ($b, $n) = @_;
    my $op = $n->operation;
    if ($op =~ /\A(?:Subscript|Exists)\z/ && ( $n->can('kind') ? $n->kind // '' : '' ) eq 'hash') {
        return _named_hash($n->inputs->[0]) ? 0 : 1;   # a `my %h` is a hash: never a stop
    }
    return 0 unless $op =~ /\A(?:Subscript|Count|PostfixDeref)\z/;
    my $c = $n->inputs->[0];
    $c = $c->inputs->[0] while _aderef($c);
    return 0 unless blessed($c);
    # (a \@a, a [...], @_, a `my @a`, @ARGV: an array it has, never a stop)
    return 0 if $c->operation =~ /\A(?:Ref|ArrayLiteral|ArgsSource)\z/ || _array_var($c) || _argv($c);
    return 1;
}

# isa_write($EntryWrite) -> true when it is `our @ISA = (LIST)` (any
# package's), its parents now the list's values, in order.
sub isa_write {
    my ($b, $s) = @_;
    my ($to, $from) = $s->inputs->@*;
    return 0 unless blessed($to) && $to->operation eq 'EntryDef' && ( $to->sigil // '' ) eq '@' && ( $to->symbol // '' ) eq 'ISA';
    my $pkg = $to->can('package') ? $to->package : undef;
    out('an @ISA of no known package') unless defined $pkg && length $pkg;
    out('an @ISA written from what is not a list of names') unless blessed($from) && $from->operation eq 'ArrayLiteral';
    out('an @ISA of a list') if grep { _is_list($_) } $from->inputs->@*; # static type
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($_), '%Slot') ]) for $from->inputs->@*;
    $b->emit(op => 'MopIsaSet', type => 'void', inputs => [ $b->const_str($pkg), $arr ]);
    return 1;
}

sub _args_list_assign {
    my ($s) = @_;
    return $s->operation eq 'Assign' && $s->can('targets') && defined $s->targets
        && blessed($s->inputs->[-1]) && $s->inputs->[-1]->operation eq 'ArgsSource';
}

# args_elem($Assign, $read) -> @_'s element a `my (...) = @_` target is.
sub args_elem {
    my ($b, $s, $r) = @_;
    my @t = @{ $s->inputs }[ 0 .. $#{ $s->inputs } - 1 ];
    out('a `my (...) = @_` of what is not a scalar') if grep { !blessed($_) || $_->operation ne 'PadAccess' || ( $_->sigil // '' ) ne '$' } @t;
    my ($i) = grep { $t[$_]->symbol eq $r->symbol } 0 .. $#t;
    out('a read after `my (...) = @_` of no target') unless defined $i;
    my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $i });
    return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $b->{argsarr}, $ix ]);
}

# list_args_assign($Assign): `my (...) = @_` on the chain in the list
# convention: each target, and each read of one after it, is @_'s element
# now -- made here, before a shift after it.
sub list_args_assign {
    my ($b, $s) = @_;
    for my $r ( @{ $s->inputs }[ 0 .. $#{ $s->inputs } - 1 ], grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@* ) {
        $b->{memo}{ refaddr($r) } //= $b->args_elem($s, $r);
    }
}

# args_assign($Assign): `my ($x, $y) = @_` on the chain. Each target is an
# argument; a read of one made after it (its input this Assign) is too. A
# target or read not an argument is not T2's (it would read undef).
sub args_assign {
    my ($b, $s) = @_;
    my @t = @{ $s->inputs }[ 0 .. $#{ $s->inputs } - 1 ];
    out('a `my (...) = @_` of what is not a scalar') if grep { !blessed($_) || $_->operation ne 'PadAccess' || ( $_->sigil // '' ) ne '$' } @t;
    my %arg_of;
    for my $t (@t) {
        my $a = $b->{args}{ refaddr($t) } // out('a `my (...) = @_` target that is not an argument');
        $arg_of{ $t->symbol } = $a;
    }
    for my $r (grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@*) {
        next if $b->{args}{ refaddr($r) };
        out('a read after `my (...) = @_` of no target') unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*;
        $b->{args}{ refaddr($r) } = $arg_of{ $r->symbol } // out('a read after `my (...) = @_` of no target');
    }
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
    # A READ THROUGH A REFERENCE may stop (through what is no hash or array
    # reference), so it is made where it stands, under its guard (`return 0
    # unless $t; $t->{v}`); one still to make at a store or a call is refused
    # there (ref_reads_settled), not made after it.
    $b->value($_) for grep { !$b->_needs_unmade_phi($_, {}) && !$b->_through_ref($_) }
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
    return 1 if $op =~ /\A(?:MemStart|Assign|EntryWrite|Delete)\z/;   # a store's version
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
    return $in[2] if $op eq 'Subscript' || $op eq 'Exists';
    return $in[0] if _pkg_scalar($n);   # a package scalar's read, at its version
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
    # A PACKAGE SCALAR READ WITH NO VERSION: B::SoN reads a write's target
    # node (`$x += 1` reads the node it writes). One write: the read is at that
    # write's memory. Several (local's save, store, restore): no one version --
    # refused where it is read. None: the function's starting memory.
    my @starts = grep { $_->operation eq 'MemStart' } @nodes;
    for my $n (grep { _pkg_scalar($_) && !$_->inputs->@* } @nodes) {
        my @w = grep { $_->operation eq 'EntryWrite' && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) }
            ( $n->consumers // [] )->@*;
        my %seen; @w = grep { !$seen{ refaddr($_) }++ } @w;
        if (@w > 1) { $b->{unversioned}{ refaddr($n) } = 1; next }
        push @{ $r{ refaddr($_) } }, $n for @w ? grep { _is_version($_) } $w[0]->inputs->[2] : @starts;
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
    # A `my %h = (...)` of constants, or of @_, is made at entry too.
    for my $lit (grep { $_->operation eq 'HashLiteral' && ( $_->stamp // '' ) eq 'Hash' && !_pinned($_) } @nodes) { # static type
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
        out('a {...} not made where it runs') if $st eq 'HashRef' && !_pinned($v);
        # A `my %h` NOT MADE AT ENTRY, needed in an arm or a loop body, would be
        # made there -- again each pass, and gone after.
        out('a hash first made in an arm or a loop body') if $st eq 'Hash' && $b->{depth} && !_pinned($v);
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
    return $b->hash_var($v) if _hash_var($v);
    my $kind = $v->can('kind') ? $v->kind // '' : '';
    if ($op =~ /\A(?:Subscript|Exists|Delete)\z/ && $kind eq 'hash') {
        my $h = $b->hash_of($in[0]);
        my $k = $b->as($b->value($in[1]), '%Str');
        return $b->emit(op => 'HGet', type => '%Slot', inputs => [ $h, $k ]) if $op eq 'Subscript';
        return $b->emit(op => 'HExists', type => 'i1', inputs => [ $h, $k ]) if $op eq 'Exists';
        return $b->emit(op => 'HDelete', type => '%Slot', inputs => [ $h, $k ]);
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        my $h = $b->hash_of($in[0]);
        return $b->emit(op => 'HCount', type => 'i64', inputs => [$h]) if $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar';
        return $b->emit(op => $v->name eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
    }
    return undef;
}

# A `my %h` NAMED, NOT MADE HERE (`my %e;`): one hash per variable, made at
# its function's entry -- as a `my @a` is.
sub _hash_var {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PadAccess' && ( $n->sigil // '' ) eq '%' && !$n->inputs->@*;
}
sub _named_hash {
    my ($n) = @_;
    return _hash_var($n) || blessed($n) && $n->operation eq 'HashLiteral' && ( $n->stamp // '' ) eq 'Hash'; # static type
}
sub hash_var {
    my ($b, $pad) = @_;
    out('a hash a closure shares') if $pad->can('shared') && $pad->shared;
    my $key = '%' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        my $h = Chalk::Target::LLVM::T2::_n(op => 'HNew', type => '%Slot');
        unshift @{ $b->{blocks}[0]{nodes} }, $h;
        $h;
    };
}

# hash_of($n) -> the %Slot of the hash a hash element, exists, delete or keys
# is of: a `my %h`, or the reference a scalar holds (`$h->{k}`). A package
# hash (%ENV, %main::h) and one through an element (perl makes it) are not.
sub hash_of {
    my ($b, $n) = @_;
    return $b->value($n) if _named_hash($n);
    out('a hash element through an element') if $n->operation eq 'Subscript' && !$b->{args}{ refaddr($n) };   # $_[N] is an argument
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
        out('an array first made in an arm or a loop body') if $b->{depth} && !_pinned($v);
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
        out('a reference to what is not an array') unless blessed($t)
            && ( $t->operation eq 'ArrayLiteral' && ( $t->stamp // '' ) eq 'Array' || _aderef($t) || _array_var($t) || _argv($t) ) # static
            && ( $v->stamp // '' ) eq 'ArrayRef';   # \(@a) is a reference to each element type
        return $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->array_of($t) ]);
    }
    if (_aderef($v)) {
        # `my @p = @$r` IS A COPY (B::SoN's copy): its own array, of the
        # elements as they are here.
        return $b->array_of($in[0]) unless $v->can('copy') && $v->copy;
        my $a = $b->emit(op => 'NewArray', type => '%Array*');
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $a, $b->array_of($in[0]) ]);
        return $a;
    }
    return $b->array_var($v) if _array_var($v);
    return $b->emit(op => 'Argv', type => '%Array*') if _argv($v);
    return $b->{argsarr} // out('@_ outside a sub taking it as a list') if $op eq 'ArgsSource';
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
            my $arr = ( @list == 1 && ( $list[0]->operation =~ /\A(?:ArrayLiteral|ArgsSource)\z/ || _aderef($list[0]) || _array_var($list[0]) || _argv($list[0]) ) ) ? $b->array_of($list[0]) : do {
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
        } Chalk::Target::LLVM::Context::_program_nodes( $b->{ret} );
        $b->{strs}{' '} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => ' ', id => $b->{strs}{' '} });
    }
    return undef;
}

# _is_list($n): a value that is a list in perl's list context -- its stamp
# says so, or it is an array or hash variable (stamped Unknown).
sub _is_list {
    my ($n) = @_;
    return 1 if ( $n->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
    return 1 if $n->operation eq 'PadAccess' && ( $n->sigil // '' ) =~ /\A[@%]\z/;
    return 0;
}

# _aderef($n): `@$r`, `@{...}`, `$r->@*` -- an array deref (a `${...}` is a
# scalar's: not this).
sub _aderef {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PostfixDeref' && ( $n->sigil // '@' ) eq '@';
}

# A PACKAGE SCALAR (`our $g`, `$::s`, `$P::v`): one global %Slot every sub
# reads and writes. perl's own ($/, $", $0, $_, $a/$b of sort, ...) are not.
my %PERLS_OWN = map { ( $_ => 1 ) } qw(ARGV ENV INC STDIN STDOUT STDERR _ 0 a b AUTOLOAD);
sub _pkg_scalar {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) eq '$'
        && ( $n->symbol // '' ) =~ /\A[A-Za-z_]\w*\z/ && !$PERLS_OWN{ $n->symbol };
}
sub global_of {
    my ($b, $n) = @_;
    my $name = ( ( $n->can('package') ? $n->package : undef ) // 'main' ) . '::' . $n->symbol;
    ( my $id = $name ) =~ s/\W+/_/g;
    return $b->{globals}{$name} //= "\@g_$id";
}

# @ARGV: the program's arguments, one array (made from argv on first use).
sub _argv {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) eq '@' && ( $n->symbol // '' ) eq 'ARGV'
        && ( ( $n->can('package') ? $n->package : undef ) // 'main' ) eq 'main';
}

# A `my @a` NAMED, NOT MADE HERE: B::SoN's PadAccess of an array declared
# once in its sub (one declared in a loop body or an arm is an ArrayLiteral
# pinned there, made each time). One %Array per variable, made at its
# function's entry: fresh each call. A closure's (shared) is not T2's.
sub _array_var {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PadAccess' && ( $n->sigil // '' ) eq '@' && !$n->inputs->@*;
}

sub array_var {
    my ($b, $pad) = @_;
    out('an array a closure shares') if $pad->can('shared') && $pad->shared;
    my $key = '@' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        my $a = Chalk::Target::LLVM::T2::_n(op => 'NewArray', type => '%Array*');
        unshift @{ $b->{blocks}[0]{nodes} }, $a;
        $a;
    };
}

# array_of($n) -> the %Array* a T1 node names (an ArrayLiteral, a deref of one).
sub array_of {
    my ($b, $n) = @_;
    return $b->array_of($n->inputs->[0]) if blessed($n) && $n->operation eq 'Ref';
    if (blessed($n) && ( $n->operation =~ /\A(?:ArrayLiteral|ArgsSource)\z/ || _aderef($n) || _array_var($n) || _argv($n)
                         || $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'builtin' && ( $n->name // '' ) =~ /\A(?:keys|values)\z/ )) {
        my $a = $b->value($n);
        return $a if $a->type eq '%Array*';
        return $b->emit(op => 'ADeref', type => '%Array*', inputs => [$a]) if $a->type eq '%Slot';   # [...]
        out('not an array');
    }
    # A HASH IN A LIST is its pairs, key then value (`(0, %h)`, `%$r`).
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]) if _named_hash($n);
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n->inputs->[0]) ])
        if blessed($n) && $n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '%';
    # THROUGH AN ELEMENT (`$a[1][0]`, not `$_[N]`) perl makes the element an
    # array when it is undef -- a store inside a read: not T2's yet.
    out('an array through an element') if blessed($n) && $n->operation eq 'Subscript' && !$b->{args}{ refaddr($n) };
    # A SCALAR HOLDING AN ARRAY REFERENCE (a variable, an argument): its
    # array, or a run-time stop when it holds none.
    out('an array that is not a `my` array (' . ( blessed($n) ? $n->operation . ( $n->can('symbol') && defined $n->symbol ? ' ' . $n->symbol : '' ) : 'none' ) . ')')
        unless blessed($n) && $b->type_of($n) eq '%Slot';
    return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->value($n) ]);
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
            out('a push of a list') if _is_list($e); # static type
            $b->emit(op => 'APush', type => 'void', inputs => [ $a, $b->as($b->value($e), '%Slot') ]);
        }
        return;
    }
    $b->value($s);   # shift, pop: made here, its value memoized for its reader
}

# element_store($Subscript, $value): `$a[i] = v`, the array growing to i.
sub element_store {
    my ($b, $target, $v, $s) = @_;
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
        $b->reads_before($_) for @{ $b->{passed} };
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
            push @in, [ $b->as($b->value($p->inputs->[$k]), $ty), $arm ];
            # MAKING IT MAY MAKE BLOCKS (a ?: B::SoN folded an inner if into):
            # the arm ends where that left off (it ended before, a phi from
            # the old end, and that block's condbr overwritten by the br).
            $vals{$arm}{block} = $b->{cur};
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block('join');
    $_->{block}{term} = [ 'br', $join ] for values %vals;
    for my $m (@made) {
        my ($p, $ty, $in) = @$m;
        $b->{memo}{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty,
            inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $vals{ $_->[1] }{block} } @$in ] });
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
            push @in, [ $b->as($b->value($p->inputs->[$k]), $ty), $pr ];
            $pr->{block} = $b->{cur};   # making it may make blocks (see if_stmt)
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block('join');
    $_->{block}{term} = [ 'br', $join ] for @preds;
    for my $m (@made) {
        my ($p, $ty, $in) = @$m;
        $b->{memo}{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty,
            inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $_->[1]{block} } @$in ] });
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
    # `&f;` IS CALLED WITH THE CALLER'S OWN @_ (the same array: a shift there
    # is seen here): both must take @_ as an array.
    if ($c->can('shares_args') && $c->shares_args) {
        out('an & call sharing @_ of a sub not taking it as a list') unless $fn->{list} && $b->{argsarr};
        $b->hash_reads_settled('a call');
        return $b->emit(op => 'Call', type => '%Slot', inputs => [ $b->{argsarr} ], attr => { fn => $fn->{name} });
    }
    if ($fn->{list}) {
        # @_ BUILT HERE: each scalar pushed, an array's elements appended.
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $a (@args) {
            if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
        }
        $b->hash_reads_settled('a call');
        return $b->emit(op => 'Call', type => '%Slot', inputs => [$arr], attr => { fn => $fn->{name} });
    }
    out('a call passing a list') if grep { _is_list($_) } @args; # static type
    out('a call of a sub with a signature of another arity (perl dies)')
        if $fn->{signature} && @args != $fn->{nargs};
    my @pass = map { $b->as($b->value($_), '%Slot') } @args;
    $b->hash_reads_settled('a call');   # the sub may store into a hash
    push @pass, $b->emit(op => 'Undef', type => '%Slot') while @pass < $fn->{nargs};
    splice @pass, $fn->{nargs};
    return $b->emit(op => 'Call', type => '%Slot', inputs => \@pass, attr => { fn => $fn->{name} });
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
    # A `class` (fields, ADJUST, methods with $self) is not a package of subs.
    out('a class of the class feature') if grep { $_->methods || $_->fields || $_->adjust_blocks } @classes;
    my %called = map { ( $_->name => 1 ) }
        grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'method' } _all_nodes($mop, $b->{ret});
    # A NAME NO PACKAGE DEFINES is UNIVERSAL's (isa, can, DOES, VERSION): not T2's.
    my %defined = map { ( $_->name => 1 ) } map { $_->subs } @classes;
    out("a method no package defines ($_)") for grep { !$defined{$_} } sort keys %called;
    out('an AUTOLOAD') if $defined{AUTOLOAD};
    for my $cls (@classes) {
        my $cs = $b->const_str($cls->name);
        $b->emit(op => 'MopClass', type => 'void', inputs => [$cs]);
        $b->emit(op => 'MopIsa', type => 'void', inputs => [ $cs, $b->const_str($cls->parent_name) ])
            if defined $cls->parent_name && length $cls->parent_name;
        my %sub = map { ( $_->name => $_ ) } grep { $called{ $_->name } && $_->graph } $cls->subs;
        for my $sub (@sub{ sort keys %sub }) {
            my $fn = $b->func($sub, $cls->name . '::' . $sub->name);
            $b->emit(op => 'MopDef', type => 'void', inputs => [ $cs, $b->const_str($sub->name) ], attr => { fn => $fn->{name} });
        }
    }
}

sub const_str {
    my ($b, $c) = @_;
    $b->{strs}{$c} //= scalar keys %{ $b->{strs} };
    return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
}

# _all_nodes($mop, $ret) -> the program's nodes and every package sub's.
sub _all_nodes {
    my ($mop, $ret) = @_;
    my @n = Chalk::Target::LLVM::Context::_program_nodes($ret);
    for my $sub ( $mop ? map { $_->subs } $mop->classes : () ) {
        push @n, Chalk::Target::LLVM::Context::_graph_component($sub->graph) if $sub->graph;
    }
    return @n;
}

# method_call($Call) -> a method call: @_ built (the invocant first), the
# method looked up from the invocant's class at run time, its wrapper called.
sub method_call {
    my ($b, $c) = @_;
    my @args = $c->inputs->@*;
    pop @args if $c->can('memory_input') && $c->memory_input;
    out('a method call with no invocant') unless @args && blessed($args[0]);
    out('a method call passing a list') if grep { _is_list($_) } @args; # static type
    my @pass = map { $b->as($b->value($_), '%Slot') } @args;
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) for @pass;
    my $cls = $b->emit(op => 'ClassOf', type => '%Str', inputs => [ $pass[0] ]);
    $b->hash_reads_settled('a method call');
    my $fp = $b->emit(op => 'MFind', type => 'i8*', inputs => [ $cls, $b->const_str($c->name) ]);
    return $b->emit(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ]);
}

# func($sub, $name) -> the T2 function a sub is: `%Slot (%Slot args...)`, its
# body built in its own blocks, made before them so a call of itself finds it.
sub func {
    my ($b, $sub, $name) = @_;
    # ONE FUNCTION PER SUB: a method's name is not its package's (two
    # classes' `hi` are two subs).
    return $b->{funcs}{ refaddr($sub) } if $b->{funcs}{ refaddr($sub) };
    my $g = $sub->graph;
    my $ret = $g->returns->[0];
    out("sub $name has no Return") unless blessed($ret) && $ret->operation eq 'Return';
    out("sub $name returns more than one reading") if $ret->inputs->@* > 1;
    my $an = bless {}, 'Chalk::Target::LLVM::Context';
    my @reads = eval { $an->_collect_positional_arg_reads($g, $name) };
    # @_ READ AS A LIST (join(@_), "@_", scalar(@_), for (@_)): the sub takes
    # @_ as one %Array its caller builds -- the list convention. A write to
    # $_[N] (the caller's variable) or a signature is not T2's.
    my $list = !$@ && $an->{_args_read_as_a_list} && !$an->{_args_written} && !$an->{_args_slurpy} && !$an->{_args_signature};
    out("sub $name reads \@_ other than by shifts, \$_[N] or a signature")
        if !$list && ( $@ || grep { !blessed($_) } @reads
        or $an->{_args_written} || $an->{_args_read_as_a_list} || $an->{_args_slurpy} );
    @reads = () if $list;
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
    # Two subs one name (a method call's bare name): the second numbered.
    $id .= '_' . scalar keys %{ $b->{funcs} } if grep { $_->{name} eq "\@f_$id" } values %{ $b->{funcs} // {} };
    my $fn = $b->{funcs}{ refaddr($sub) } = { name => "\@f_$id", wrapper => "\@w_$id", nargs => $list ? 1 : scalar @reads,
        signature => $sig, list => $list, blocks => [] };
    my @argn = map { Chalk::Target::LLVM::T2::_n(op => 'Arg', type => '%Slot', attr => { index => $_ }) } 0 .. $#reads;
    $argn[$_]->set_name("%a$_") for 0 .. $#argn;
    my $argsarr = $list ? Chalk::Target::LLVM::T2::_n(op => 'Arg', type => '%Array*', attr => { index => 0 }) : undef;
    $argsarr->set_name('%a0') if $argsarr;
    local $b->{argsarr} = $argsarr;
    # A READ OF `my (...) = @_` made where it is used reads @_ then: one the
    # sub shifts first would be of the shifted array.
    local $b->{args_mutated} = $list && scalar grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin'
        && ( $_->name // '' ) =~ /\A(?:shift|pop|push|unshift|splice)\z/ && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'ArgsSource' }
        Chalk::Target::LLVM::Context::_graph_component($g);
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
    # AN ARRAY REFERENCE is a %Slot (tag 6) over an %Array: a scalar.
    return '%Slot' if $op eq 'ArrayLiteral' && ( $v->stamp // '' ) eq 'ArrayRef'; # static type
    return '%Slot' if $op eq 'Ref';
    return '%Array*' if $op eq 'ArrayLiteral' || _aderef($v) || _array_var($v) || $op eq 'ArgsSource';
    return 'i64' if $op eq 'Count';
    return '%Slot' if $op eq 'Subscript';
    # A HASH REFERENCE is a %Slot (tag 5) over a %Hash: it is a scalar.
    return '%Slot' if $op eq 'HashLiteral' && ( $v->stamp // '' ) =~ /\A(?:HashRef|Hash)\z/; # static type
    return '%Slot' if _hash_var($v);
    # length of a scalar: undef for undef, so a %Slot; of a string, an i64.
    return ( ( $v->inputs->[0]->stamp // '' ) !~ /\A(?:Array|ArrayRef)\z/ && $b->type_of($v->inputs->[0]) eq '%Slot' ) ? '%Slot' : 'i64' if $op eq 'Length'; # static type
    my $hk = $v->can('kind') ? $v->kind // '' : '';
    return 'i1' if $op eq 'Exists' && $hk eq 'hash';
    return '%Slot' if $op eq 'Delete' && $hk eq 'hash';
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        return $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar' ? 'i64' : '%Array*';
    }
    return '%Slot' if $op eq 'Call' && ( $v->name // '' ) =~ /\A(?:shift|pop)\z/;
    return '%Str' if $op eq 'Call' && ( $v->name // '' ) eq 'join';
    return '%Array*' if _argv($v);
    return '%Slot' if _pkg_scalar($v);   # what it holds is what was stored last, anywhere
    return '%Str' if $op eq 'EntryDef';
    return '%Slot' if $op eq 'PadAccess' && $v->is_location;
    return '%Slot' if $op eq 'Increment' || $op eq 'Decrement';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) =~ /\A(?:direct|method)\z/;
    # AN OBJECT is its blessed reference; ref() of one its class, or HASH.
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless';
    return '%Str' if $op eq 'RefType';
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
    # (a read after the Assign takes it as input; a target read is its input)
    if ($b->{argsarr} && $v->operation eq 'PadAccess'
        && ( my ($as) = ( grep( { blessed($_) && _args_list_assign($_) } $v->inputs->@* ),
                          grep( { blessed($_) && _args_list_assign($_) && grep { blessed($_) && refaddr($_) == refaddr($v) } @{ $_->inputs }[ 0 .. $#{ $_->inputs } - 1 ] } ( $v->consumers // [] )->@* ) ) )) {
        out('a read of `my (...) = @_` in a sub that shifts @_') if $b->{args_mutated};
        return $b->args_elem($as, $v);
    }
    my $op = $v->operation;
    my $ty = $b->type_of($v);
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'direct') { return $b->call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'method') { return $b->method_call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless') {
        my @in = $v->inputs->@*;
        pop @in if $v->can('memory_input') && $v->memory_input;
        # ONE ARGUMENT blesses into the package the bless is in: not known here.
        out('a bless of one argument') unless @in == 2;
        out('a bless of what is not a hash') if $in[0]->operation eq 'ArrayLiteral' || ( $in[0]->stamp // '' ) =~ /\A(?:ArrayRef|ScalarRef|CodeRef)\z/; # static type
        return $b->emit(op => 'Bless', type => '%Slot',
            inputs => [ $b->as($b->value($in[0]), '%Slot'), $b->as($b->value($in[1]), '%Str') ]);
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
    if (_pkg_scalar($v)) {
        out('a package scalar read of no one version') if $b->{unversioned}{ refaddr($v) };
        return $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->global_of($v) });
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
        $b->{strs}{$k} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'Env', type => '%Slot', attr => { key => $k, id => $b->{strs}{$k} });
    }
    if ($op eq 'DefinedOr' || $op eq 'TernaryExpr' || $op eq 'And' || $op eq 'Or') {
        # A MERGE: its condition, an arm built in each block, a phi at the join.
        my ($cond, $then, $else);
        if ($op eq 'And' || $op eq 'Or') {
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
        { local $b->{memo} = { %{ $b->{memo} } };
          $tv = $b->as( blessed($then) && $then->isa('Chalk::Target::LLVM::T2::Node') ? $then : $b->value($then), $ty ); }
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        { local $b->{memo} = { %{ $b->{memo} } };
          $ev = $b->as( blessed($else) && $else->isa('Chalk::Target::LLVM::T2::Node') ? $else : $b->value($else), $ty ); }
        my $eend = $b->{cur};
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $cond, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => $ty, inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
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
    push @L, "$_ = internal global %Slot zeroinitializer" for sort values %{ $bld->{globals} // {} };
    push @L, 'define i32 @main(i32 %argc, i8** %argv) {', _blocks($bld->{blocks}), '}', '';
    # EACH SUB A FUNCTION: `%Slot (%Slot %a0, ...)`, its blocks printed alike.
    for my $fn (sort { $a->{name} cmp $b->{name} } values %{ $bld->{funcs} // {} }) {
        my $i = 0;
        $_->set_name('%v' . $i++) for map { @{ $_->{nodes} } } @{ $fn->{blocks} };
        push @L, "define internal %Slot $fn->{name}(" . ( $fn->{list} ? '%Array* %a0' : join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) ) . ') {',
            _blocks($fn->{blocks}), '}', '';
        if ($fn->{list}) {   # its wrapper is itself: @_ already an %Array
            push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {", "  %r = call %Slot $fn->{name}(%Array* %args)", '  ret %Slot %r', '}', '';
            next;
        }
        # ITS WRAPPER, a method's entry: @_ as an %Array, each argument its
        # element (undef past the end). A signature's arity perl checks.
        push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {";
        if ($fn->{signature}) {
            push @L, '  %n = call i64 @t2_alen(%Array* %args)', "  %ok = icmp eq i64 %n, $fn->{nargs}",
                '  br i1 %ok, label %call, label %bad', 'bad:',
                '  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)',
                '  unreachable', 'call:';
        }
        push @L, "  %a$_ = call %Slot \@t2_aget(%Array* %args, i64 $_)" for 0 .. $fn->{nargs} - 1;
        push @L, "  %r = call %Slot $fn->{name}(" . join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) . ')',
            '  ret %Slot %r', '}', '';
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
    return "$nm = call i64 \@t2_strcmp(" . $arg->(@in) . ')' if $op eq 'StrCmp';
    return "$nm = extractvalue %Str " . $in[0]->name . ', 1' if $op eq 'StrLen';
    return "$nm = call %Slot \@t2_slot_length(" . $arg->(@in) . ')' if $op eq 'SlotLength';
    return "$nm = call %Array* \@t2_new_array()" if $op eq 'NewArray';
    return "$nm = call %Slot \@t2_hnew()" if $op eq 'HNew';
    return "call void \@t2_save_args(i32 %argc, i8** %argv)" if $op eq 'SaveArgs';
    return "$nm = load %Slot, %Slot* $a{global}" if $op eq 'GLoad';
    return "store %Slot " . $in[0]->name . ", %Slot* $a{global}" if $op eq 'GStore';
    return "$nm = call %Array* \@t2_argv()" if $op eq 'Argv';
    return "$nm = call %Slot \@t2_bless(" . $arg->(@in) . ')' if $op eq 'Bless';
    return "$nm = call %Str \@t2_reftype(" . $arg->(@in) . ')' if $op eq 'RefType';
    return "call void \@t2_mop_class(" . $arg->(@in) . ')' if $op eq 'MopClass';
    return "call void \@t2_mop_isa(" . $arg->(@in) . ')' if $op eq 'MopIsa';
    return "call void \@t2_mop_isa_set(" . $arg->(@in) . ')' if $op eq 'MopIsaSet';
    return "call void \@t2_mop_def(" . $arg->(@in) . ", i8* bitcast (%Slot (%Array*)* $a{fn}_w to i8*))" if $op eq 'MopDef';
    return "$nm = call %Str \@t2_classof(" . $arg->(@in) . ')' if $op eq 'ClassOf';
    return "$nm = call i8* \@t2_mfind(" . $arg->(@in) . ')' if $op eq 'MFind';
    if ($op eq 'MCall') {
        return "$nm.f = bitcast i8* " . $in[0]->name . " to %Slot (%Array*)*\n  $nm = call %Slot $nm.f(%Array* " . $in[1]->name . ')';
    }
    return "call void \@t2_hset(" . $arg->(@in) . ')' if $op eq 'HSet';
    return "$nm = call %Slot \@t2_hget(" . $arg->(@in) . ')' if $op eq 'HGet';
    return "$nm = call i1 \@t2_hexists(" . $arg->(@in) . ')' if $op eq 'HExists';
    return "$nm = call %Slot \@t2_hdelete(" . $arg->(@in) . ')' if $op eq 'HDelete';
    return "call void \@t2_hfroma(" . $arg->(@in) . ')' if $op eq 'HFromArray';
    return "$nm = call i64 \@t2_hcount(" . $arg->(@in) . ')' if $op eq 'HCount';
    return "$nm = call %Array* \@t2_hkeys(" . $arg->(@in) . ')' if $op eq 'HKeys';
    return "$nm = call %Array* \@t2_hpairs(" . $arg->(@in) . ')' if $op eq 'HPairs';
    return "$nm = call %Array* \@t2_hvalues(" . $arg->(@in) . ')' if $op eq 'HValues';
    return "call void \@t2_apush(" . $arg->(@in) . ')' if $op eq 'APush';
    return "call void \@t2_aappend(" . $arg->(@in) . ')' if $op eq 'AAppend';
    return "$nm = call %Slot \@t2_aref(" . $arg->(@in) . ')' if $op eq 'ARef';
    return "$nm = call %Array* \@t2_aderef(" . $arg->(@in) . ')' if $op eq 'ADeref';
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
                               i8 5, label %ref
                               i8 6, label %ref ]
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
  ; A REFERENCE AS A NUMBER is its address (perl's refaddr): == compares them.
  %ra = extractvalue %Slot %s, 1
  %rs = call %Slot @t2_box_i64(i64 %ra)
  ret %Slot %rs
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
                               i8 5, label %ref
                               i8 6, label %ref ]
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
  %da = sitofp i64 %v to double
  ret double %da
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
                               i8 5, label %ref
                               i8 6, label %ref ]
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
  %rs = call %Str @t2_ref_str(%Slot %s)
  ret %Str %rs
}
@fmt_ref = private unnamed_addr constant [12 x i8] c"%.*s(0x%lx)\00"
@lit_eqhash = private unnamed_addr constant [6 x i8] c"=HASH\00"
; t2_ref_str(r) -> perl's string of a reference: HASH(0x...), ARRAY(0x...),
; or Class=HASH(0x...) for an object.
define internal %Str @t2_ref_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %addr = extractvalue %Slot %s, 1
  %kind = call %Str @t2_reftype(%Slot %s)
  %ishash = icmp eq i8 %t, 5
  br i1 %ishash, label %h, label %fmt
h:
  %a = call %Array* @t2_harr(%Slot %s)
  %c = call %Slot @t2_aget(%Array* %a, i64 0)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %fmt
obj:
  %eh = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_eqhash, i64 0, i64 0), i64 5)
  %ck = call %Str @t2_concat(%Str %kind, %Str %eh)
  br label %fmt
fmt:
  %pre = phi %Str [ %kind, %entry ], [ %kind, %h ], [ %ck, %obj ]
  %pp = extractvalue %Str %pre, 0
  %pl = extractvalue %Str %pre, 1
  %pl32 = trunc i64 %pl to i32
  %cap = add i64 %pl, 32
  %buf = call i8* @malloc(i64 %cap)
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 %cap, i8* getelementptr ([12 x i8], [12 x i8]* @fmt_ref, i64 0, i64 0), i32 %pl32, i8* %pp, i64 %addr)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
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
                               i8 5, label %ref
                               i8 6, label %ref ]
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
@lit_hash = private unnamed_addr constant [5 x i8] c"HASH\00"
@lit_array = private unnamed_addr constant [6 x i8] c"ARRAY\00"
@msg_notanarray = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: an array element read through no ARRAY reference\0A\00"
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
; A HASH'S %Array: element 0 is the class a bless gave it (undef until),
; then key, value pairs.
define internal %Slot @t2_hnew() {
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot zeroinitializer)
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
  %i = phi i64 [ 1, %entry ], [ %i2, %next ]
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
define internal %Slot @t2_bless(%Slot %h, %Str %c) {
  %a = call %Array* @t2_harr(%Slot %h)
  %cs = call %Slot @t2_box_str(%Str %c)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  store %Slot %cs, %Slot* %els
  ret %Slot %h
}
; t2_reftype(s) -> perl's ref(): an object's class, HASH, or "" for no reference.
define internal %Str @t2_reftype(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %isarr = icmp eq i8 %t, 6
  br i1 %isarr, label %arr, label %nota
arr:
  %as = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_array, i64 0, i64 0), i64 5)
  ret %Str %as
nota:
  %isref = icmp eq i8 %t, 5
  br i1 %isref, label %ref, label %none
ref:
  %a = call %Array* @t2_harr(%Slot %s)
  %c = call %Slot @t2_aget(%Array* %a, i64 0)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %hash
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  ret %Str %cn
hash:
  %h = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 4)
  ret %Str %h
none:
  %e = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 0)
  ret %Str %e
}
@t2_stashes = internal global %Slot zeroinitializer
@lit_isa = private unnamed_addr constant [5 x i8] c"@ISA\00"
@msg_nomethod = private unnamed_addr constant [79 x i8] c"chalk: refused at run time: a method call no class of the invocant can answer\0A\00"
@msg_noclass = private unnamed_addr constant [77 x i8] c"chalk: refused at run time: a method call on what is not an object or class\0A\00"
@msg_arity = private unnamed_addr constant [68 x i8] c"chalk: refused at run time: a call of a signature of another arity\0A\00"
define internal %Slot @t2_stash_table() {
entry:
  %t = load %Slot, %Slot* @t2_stashes
  %tag = extractvalue %Slot %t, 0
  %made = icmp eq i8 %tag, 5
  br i1 %made, label %have, label %make
make:
  %n = call %Slot @t2_hnew()
  store %Slot %n, %Slot* @t2_stashes
  ret %Slot %n
have:
  ret %Slot %t
}
@t2_argc = internal global i32 0
@t2_argvp = internal global i8** null
@t2_ARGV = internal global %Array* null
define internal void @t2_save_args(i32 %c, i8** %v) {
  store i32 %c, i32* @t2_argc
  store i8** %v, i8*** @t2_argvp
  ret void
}
; t2_argv() -> @ARGV: argv[1..] as strings, made once.
define internal %Array* @t2_argv() {
entry:
  %have = load %Array*, %Array** @t2_ARGV
  %made = icmp ne %Array* %have, null
  br i1 %made, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %c32 = load i32, i32* @t2_argc
  %c = sext i32 %c32 to i64
  %v = load i8**, i8*** @t2_argvp
  br label %loop
loop:
  %i = phi i64 [ 1, %make ], [ %i2, %body ]
  %more = icmp slt i64 %i, %c
  br i1 %more, label %body, label %store
body:
  %pp = getelementptr i8*, i8** %v, i64 %i
  %p = load i8*, i8** %pp
  %n = call i64 @strlen(i8* %p)
  %s = call %Str @t2_str(i8* %p, i64 %n)
  %sl = call %Slot @t2_box_str(%Str %s)
  call void @t2_apush(%Array* %a, %Slot %sl)
  %i2 = add i64 %i, 1
  br label %loop
store:
  store %Array* %a, %Array** @t2_ARGV
  ret %Array* %a
done:
  ret %Array* %have
}
define internal %Slot @t2_aref(%Array* %a) {
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  ret %Slot %s
}
define internal %Array* @t2_aderef(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 6
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_notanarray, i64 0, i64 0), i64 77)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
define internal void @t2_aappend(%Array* %d, %Array* %s) {
entry:
  %n = call i64 @t2_alen(%Array* %s)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %s, i64 %i)
  call void @t2_apush(%Array* %d, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
; t2_slot_length(s) -> perl's length of a scalar: undef for undef.
define internal %Slot @t2_slot_length(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %len
undef:
  ret %Slot zeroinitializer
len:
  %str = call %Str @t2_slot_str(%Slot %s)
  %n = extractvalue %Str %str, 1
  %r = call %Slot @t2_box_i64(i64 %n)
  ret %Slot %r
}
; t2_strcmp(x, y) -> perl's cmp: -1, 0 or 1, bytewise, a prefix first.
define internal i64 @t2_strcmp(%Str %x, %Str %y) {
entry:
  %xp = extractvalue %Str %x, 0
  %xl = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yl = extractvalue %Str %y, 1
  %short = icmp slt i64 %xl, %yl
  %m = select i1 %short, i64 %xl, i64 %yl
  %r = call i32 @memcmp(i8* %xp, i8* %yp, i64 %m)
  %neg = icmp slt i32 %r, 0
  %pos = icmp sgt i32 %r, 0
  br i1 %neg, label %lt, label %notlt
notlt:
  br i1 %pos, label %gt, label %bylen
bylen:
  br i1 %short, label %lt, label %notshort
notshort:
  %longer = icmp sgt i64 %xl, %yl
  br i1 %longer, label %gt, label %eq
lt:
  ret i64 -1
gt:
  ret i64 1
eq:
  ret i64 0
}
; t2_stash(c) -> c's stash, made empty if c has none yet.
define internal %Slot @t2_stash(%Str %c) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %has = icmp eq i8 %st, 5
  br i1 %has, label %ok, label %make
make:
  %n = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %n)
  ret %Slot %n
ok:
  ret %Slot %s
}
define internal void @t2_mop_isa_set(%Str %c, %Array* %a) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %ai = ptrtoint %Array* %a to i64
  %as = call %Slot @t2_slot(i8 6, i64 %ai)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %as)
  ret void
}
define internal void @t2_mop_class(%Str %c) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %s)
  ret void
}
define internal %Str @t2_isa_key() {
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_isa, i64 0, i64 0), i64 4)
  ret %Str %k
}
; t2_mop_isa(class, parent): push parent onto class's @ISA.
define internal void @t2_mop_isa(%Str %c, %Str %p) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %tag = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %tag, 6
  br i1 %has, label %push, label %make
make:
  %na = call %Array* @t2_new_array()
  %ni = ptrtoint %Array* %na to i64
  %ns = call %Slot @t2_slot(i8 6, i64 %ni)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %ns)
  br label %push
push:
  %cur = phi %Slot [ %isa, %entry ], [ %ns, %make ]
  %cv = extractvalue %Slot %cur, 1
  %arr = inttoptr i64 %cv to %Array*
  %ps = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush(%Array* %arr, %Slot %ps)
  ret void
}
define internal void @t2_mop_def(%Str %c, %Str %m, i8* %f) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %fi = ptrtoint i8* %f to i64
  %fs = call %Slot @t2_slot(i8 7, i64 %fi)
  call void @t2_hset(%Slot %s, %Str %m, %Slot %fs)
  ret void
}
; t2_classof(inv) -> the class a method call looks from: an object's, or a
; class name's own.
define internal %Str @t2_classof(%Slot %inv) {
entry:
  %t = extractvalue %Slot %inv, 0
  %isref = icmp eq i8 %t, 5
  br i1 %isref, label %ref, label %name
ref:
  %a = call %Array* @t2_harr(%Slot %inv)
  %cl = call %Slot @t2_aget(%Array* %a, i64 0)
  %ct = extractvalue %Slot %cl, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %bad
obj:
  %cn = call %Str @t2_slot_str(%Slot %cl)
  ret %Str %cn
name:
  %isstr = icmp eq i8 %t, 3
  br i1 %isstr, label %named, label %bad
named:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  ret %Str %nn
bad:
  call void @t2_stop(i8* getelementptr ([77 x i8], [77 x i8]* @msg_noclass, i64 0, i64 0), i64 76)
  unreachable
}
; t2_mfind1(class, m) -> m's code in class or, depth first, its @ISA; null.
define internal i8* @t2_mfind1(%Str %c, %Str %m) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %look, label %none
look:
  %f = call %Slot @t2_hget(%Slot %s, %Str %m)
  %ft = extractvalue %Slot %f, 0
  %code = icmp eq i8 %ft, 7
  br i1 %code, label %found, label %parents
found:
  %fv = extractvalue %Slot %f, 1
  %fp = inttoptr i64 %fv to i8*
  ret i8* %fp
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %none
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i8* @t2_mfind1(%Str %pn, %Str %m)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ret, label %next
ret:
  ret i8* %r
next:
  %i2 = add i64 %i, 1
  br label %loop
none:
  ret i8* null
}
define internal i8* @t2_mfind(%Str %c, %Str %m) {
entry:
  %r = call i8* @t2_mfind1(%Str %c, %Str %m)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %bad
ok:
  ret i8* %r
bad:
  call void @t2_stop(i8* getelementptr ([79 x i8], [79 x i8]* @msg_nomethod, i64 0, i64 0), i64 78)
  unreachable
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
define internal i1 @t2_hexists(%Slot %h, %Str %k) {
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %e = icmp sge i64 %i, 0
  ret i1 %e
}
; t2_hdelete(h, k) -> k's value (undef if none), its pair taken out.
define internal %Slot @t2_hdelete(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %none, label %take
none:
  ret %Slot zeroinitializer
take:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %d = phi i64 [ %i, %take ], [ %d2, %move ]
  %src = add i64 %d, 2
  %more = icmp slt i64 %src, %n
  br i1 %more, label %move, label %done
move:
  %sp = getelementptr %Slot, %Slot* %els, i64 %src
  %sv = load %Slot, %Slot* %sp
  %dp = getelementptr %Slot, %Slot* %els, i64 %d
  store %Slot %sv, %Slot* %dp
  %d2 = add i64 %d, 1
  br label %loop
done:
  %n2 = sub i64 %n, 2
  store i64 %n2, i64* %lp
  ret %Slot %v
}
define internal void @t2_hfroma(%Slot %h, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ks = call %Slot @t2_aget(%Array* %l, i64 %i)
  %k = call %Str @t2_slot_str(%Slot %ks)
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %j)
  call void @t2_hset(%Slot %h, %Str %k, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret void
}
define internal i64 @t2_hcount(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %p = sub i64 %n, 1
  %c = sdiv i64 %p, 2
  ret i64 %c
}
; t2_hpick(h, from) -> every other element of the hash's pairs from index
; from: 1 its keys, 2 its values.
define internal %Array* @t2_hpick(%Slot %h, i64 %from) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ %from, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hpairs(%Slot %h) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hkeys(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 1)
  ret %Array* %r
}
define internal %Array* @t2_hvalues(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 2)
  ret %Array* %r
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
