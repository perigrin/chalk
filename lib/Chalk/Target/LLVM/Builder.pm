# ABOUTME: The LLVM T2 builder: the lowering functor from a chalk IR graph to a graph of
# ABOUTME: Chalk::Target::LLVM::Node, typed in LLVM's types. Its methods are split by concern.
use 5.42.0;
use utf8;

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

package Chalk::Target::LLVM::Builder;

use Chalk::Regex::Graph;   # a constant regex as its own graph
use Chalk::MOP::Sub;
require Chalk::IR::Serialize::JSON;
use Chalk::IR::Graph;   # program_nodes, own_nodes, component: whose nodes are whose

use Scalar::Util qw(blessed refaddr);

require Chalk::Target::LLVM::Node;
require Chalk::Target::LLVM::Printer;   # its %CONVERT: which conversions there are

sub out { die "T2: out of its slices ($_[0])\n" }

sub new_block {
    my ($b, $label) = @_;
    my $blk = { label => $label . scalar($b->{blocks}->@*), nodes => [], term => undef };
    push $b->{blocks}->@*, $blk;
    return $b->{cur} = $blk;
}

sub emit {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::Node::_n(%a);
    push $b->{cur}{nodes}->@*, $n;
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
    $b->{own_nodes} = [ Chalk::IR::Graph::own_nodes($ret) ];
    $b->{eval_at} = { map { ( refaddr( $_->eval_entry ) => $_ ) } grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } $b->{own_nodes}->@* };
    $b->{evals} = [];
    $b->{passed} = [ grep { $_->operation eq 'MemStart' } Chalk::IR::Graph::own_nodes($ret) ];
    $b->index_readers(Chalk::IR::Graph::own_nodes($ret));
    $b->new_block('entry');
    $b->emit(op => 'SaveArgs', type => 'void');   # argv, for @ARGV
    # (a tie calls its class's methods too)
    $b->make_mop if grep { $_->operation eq 'Call' && ( ( $_->dispatch_kind // '' ) eq 'method' || ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'tie' ) } _all_nodes($b->{mop}, $ret);
    $b->make_constant_arrays(Chalk::IR::Graph::own_nodes($ret));
    # PHASE BLOCKS, each a function as a sub is (its file lexicals shared as a
    # sub's are): a BEGIN runs first, in order, at the program's start; an END
    # is registered with atexit(3), which runs them last defined first at every
    # way out -- the main line's end, an exit, a die. Another phase is not T2's.
    for my $ph ( grep { blessed( $_->[1] ) } @Chalk::IR::Serialize::JSON::PHASE_GRAPHS ) {
        my ( $kind, $g ) = @$ph;
        out("a $kind block") unless $kind =~ /\A(?:BEGIN|END)\z/;
        # A BEGIN TOUCHING A MAIN-LINE LEXICAL ran at compile time, before the
        # main line's `my`, which then leaves it (`my $x; BEGIN { $x = 5 }` is 5):
        # run first here, the `my` reset it. Refused.
        out('a BEGIN block reading or writing a lexical of the main program')
            if $kind eq 'BEGIN' && grep { $_->operation eq 'PadAccess' && ( $_->shared || !defined $_->inputs->[0] ) }
                Chalk::IR::Graph::program_nodes( $g->returns->[0] );
        my $sub = Chalk::MOP::Sub->new( name => "main::$kind", class => undef, graph => $g, params => ['@_'], uses_args => 1 );
        my $fn = $b->func( $sub, lc($kind) . '_' . ++$b->{nphase} );
        out("a $kind block read as taking arguments") if $fn->{nargs} || $fn->{list} || $fn->{closure};
        if ( $kind eq 'BEGIN' ) { $b->emit_call(op => 'Call', type => '%Slot', inputs => [], attr => { fn => $fn->{name} }) }
        else {
            out('more than 64 END blocks') if +($b->{atexit} // [])->@* >= 64;
            push $b->{atexit}->@*, $fn->{name};
            $b->emit(op => 'AtExit', type => 'void', attr => { fn => '@x_' . scalar $b->{atexit}->@* });
        }
    }
    $b->{jumps} = {};
    $b->walk($start);
    out('an early exit to a merge never reached') if $b->{jumps}->%*;
    $b->emit(op => 'RunEnds', type => 'void') if $b->{atexit} && !$b->{cur}{dead};   # (the main line's end)
    $b->{cur}{term} = [ 'ret' ];
}

# emit_entry(%n): a node made at the function's entry (first block's start),
# where each `my` aggregate of the function is made.
sub emit_entry {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::Node::_n(%a);
    unshift $b->{blocks}[0]{nodes}->@*, $n;
    return $n;
}

# _is_list($n): a value that is a list in perl's list context -- its stamp
# says so, or it is an array or hash variable (stamped Unknown).
sub _is_list {
    my ($n) = @_;
    # A CALL IN LIST CONTEXT: its result is a list (of one value, maybe). Its
    # use decides, not its stamp (a call stamped List is a scalar's in `my $n =`).
    return _list_use($n) if $n->operation eq 'Call' && $n->is_sub_call;
    return 1 if ( $n->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
    # A MATCH IN LIST CONTEXT (B::SoN stamps it Boolean): by what takes it.
    return _match_in_list($n) if $n->operation =~ /\A(?:RegexMatch|Match)\z/;
    return 1 if $n->operation eq 'PadAccess' && ( $n->sigil // '' ) =~ /\A[@%]\z/;
    return 1 if $Chalk::Target::LLVM::Builder::LIST_FIELD{ refaddr($n) };
    return 0;
}

# _match_in_list($match) -> 1 if what takes the match takes a list: print (a
# Coerce B::SoN put there is no scalar context), a list's element, a sub
# call's argument, a builtin's list (Call::takes_a_list), a list assignment.
# Returned, its context is the caller's: refused.
sub _match_in_list {
    my ($n) = @_;
    my $list = 0;
    for my $c ( grep { blessed($_) } ( $n->consumers // [] )->@* ) {
        my $op = $c->operation;
        # (a value it takes: not its memory input -- a statement after a
        # pinned match takes the match as its memory version)
        my @args = $c->inputs->@*;
        pop @args if $c->can('memory_input') && $c->memory_input;
        next unless grep { blessed($_) && refaddr($_) == refaddr($n) } @args;
        my $is_in = sub ($x) { grep { blessed($_) && refaddr($_) == refaddr($x) } @args };
        Chalk::Target::LLVM::Builder::out('a match returned (its context is its caller\'s)') if $op eq 'Return';
        if ( $op eq 'Coerce' && grep { blessed($_) && $_->operation eq 'Print' } ( $c->consumers // [] )->@* ) { $list = 1; next }
        $list = 1 if $op =~ /\A(?:Print|ArrayLiteral|ListAppend)\z/ && $is_in->($n);
        $list = 1 if $op eq 'Call' && $c->is_sub_call;
        $list = 1 if $op eq 'Call' && $c->takes_a_list;
        $list = 1 if $op eq 'Assign' && blessed( $c->inputs->[-1] ) && refaddr( $c->inputs->[-1] ) == refaddr($n)
            && ( ( $c->can('targets') && defined $c->targets ) || grep { blessed($_) && $_->can('sigil') && ( $_->sigil // '' ) =~ /\A[\@%]\z/ } $c->inputs->@[ 0 .. $c->inputs->$#* - 1 ] );
    }
    return $list;
}

sub global_of {
    my ($b, $n) = @_;
    return '@t2_err' if $n->symbol eq '@';
    return $b->global_named( $n->qualified_name );
}

sub global_named {
    my ($b, $name) = @_;
    ( my $id = $name ) =~ s/\W+/_/g;
    return $b->{globals}{$name} //= "\@g_$id";
}

# A FIELD of the class feature: its key in the object's hash ("Stash::$x",
# a parent's field and a child's of one name kept apart) and its sigil.
sub field_of {
    my ($b, $n) = @_;
    my $stash = $n->can('field_stash') ? $n->field_stash : undef;
    my $cls = defined $stash && $b->{mop} ? $b->{mop}->for_class($stash) : undef;
    out('a field of no known class') unless $cls;
    # perl numbers a class's fields after its parents' (the MOP from 0 in each)
    my $off = 0;
    for (my $p = $cls; defined $p->parent_name && length $p->parent_name; ) {
        $p = $b->{mop}->for_class( $p->parent_name ) // last;
        $off += scalar $p->fields;
    }
    my ($f) = grep { $_->fieldix + $off == ( $n->field_index // -1 ) } $cls->fields;
    out('a field of no known index') unless $f;
    return ( "$stash\::" . $f->name, $f->sigil );
}

# _list_use($call) -> true when what uses the call's value uses it as a list:
# an element of a list (an array literal, print's and a call's arguments,
# push's and join's), map's value, a return's list. Not B::SoN's `want`:
# `$o->m || "x"` is want=list, but perl calls it in scalar context there. A
# value used both ways is refused (one call, one context).
our %PRINTED;
our %LIST_FIELD;
sub _list_use {
    my ($c) = @_;
    my ($list, $scalar) = (0, 0);
    $list++ if $PRINTED{ refaddr($c) };
    my %seen;
    for my $u (grep { blessed($_) && !$seen{ refaddr($_) }++ } ( $c->consumers // [] )->@*) {
        my $op = $u->operation;
        my @pos = grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($c) } 0 .. $u->inputs->$#*;
        # (the call as a memory version -- a read after it, a store's memory --
        # is not a use of its value)
        # (only its memory position: `push @a, f()` has f() as its value AND its memory)
        my $m = $u->memory_operand;
        if (blessed($m) && refaddr($m) == refaddr($c)) {
            my ($mi) = reverse grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($m) } 0 .. $u->inputs->$#*;
            @pos = grep { $_ != $mi } @pos;
        }
        # (a LIST assign's last input is its list, not its memory: `my ($x, $y) = f()`)
        @pos = grep { $_ != $u->inputs->$#* } @pos if $u->operation =~ /\A(?:Assign|EntryWrite|Delete|Exists)\z/
            && !( $u->operation eq 'Assign' && $u->can('targets') && defined $u->targets );
        @pos = () if $u->operation eq 'EntryDef';   # its input is its memory ($" read after the call)
        next unless @pos;
        my $at0 = grep { $_ == 0 } @pos;   # (a bare grep in an || chain takes the rest as its list)
        my $at1 = grep { $_ == 1 } @pos;
        if ($op eq 'ArrayLiteral' || $op eq 'Print'
            || $op eq 'Call' && ( $u->dispatch_kind // '' ) eq 'direct'
            || $op eq 'Call' && ( $u->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/ && !$at0   # not the invocant, nor the code
            || $op eq 'Call' && ( $u->name // '' ) =~ /\A(?:push|unshift|join)\z/ && !$at0
            || $op eq 'ListAppend' && $at1
            || $op eq 'Return' && $u->inputs->@* == 2 && $at0
            || $op eq 'Assign' && $u->can('targets') && defined $u->targets) { $list++ }   # `my ($x, $y) = f()`
        elsif ($op eq 'Coerce' && $PRINTED{ refaddr($c) }) { }   # print's (counted above)
        elsif ($op =~ /\A(?:Phi|Return)\z/) { }   # a merge or a tail call: its own use decides
        else { $scalar++ }
    }
    out('a call used both as a list and as a scalar') if $list && $scalar;
    return $list ? 1 : 0;
}

# _value_read($n) -> some node takes $n's value as an input -- not only as its
# memory version (a later read of the array) or its control.
sub _value_read {
    my ($b, $n) = @_;
    for my $c (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        my @in = $c->inputs->@*;
        my $mem = $c->memory_operand // ( $c->operation =~ /\A(?:EntryDef|PadAccess)\z/ ? $in[0] : undef );
        my $skip = blessed($mem) && refaddr($mem) == refaddr($n) ? 1 : 0;
        my $uses = grep { blessed($_) && refaddr($_) == refaddr($n) } @in;
        return 1 if $uses > $skip;
    }
    return 0;
}

sub const_str {
    my ($b, $c) = @_;
    $b->{strs}{$c} //= scalar keys $b->{strs}->%*;
    return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
}

# _all_nodes($mop, $ret) -> the program's nodes and every package sub's.
sub _all_nodes {
    my ($mop, $ret) = @_;
    my @n = Chalk::IR::Graph::program_nodes($ret);
    for my $sub ( $mop ? map { $_->subs } $mop->classes : () ) {
        push @n, $sub->graph->component if $sub->graph;
    }
    # (AN ADJUST BLOCK'S too: `new` runs it, so a method only it calls --
    # `ADJUST { $self->mark("d") }` -- must be in its stash, or the lookup
    # dies where perl finds it.)
    for my $adj ( $mop ? map { $_->adjust_blocks } $mop->classes : () ) {
        push @n, $adj->graph->component if $adj->can('graph') && $adj->graph;
    }
    # (A PHASE BLOCK'S too: its method calls, its derefs, are the program's.)
    push @n, Chalk::IR::Graph::program_nodes( $_->[1]->returns->[0] )
        for grep { blessed( $_->[1] ) } @Chalk::IR::Serialize::JSON::PHASE_GRAPHS;
    return @n;
}

# The builder's methods by concern, each file `package Chalk::Target::LLVM::Builder`.
require Chalk::Target::LLVM::Builder::Control;
require Chalk::Target::LLVM::Builder::Values;
require Chalk::Target::LLVM::Builder::Variables;
require Chalk::Target::LLVM::Builder::Containers;
require Chalk::Target::LLVM::Builder::Calls;
require Chalk::Target::LLVM::Builder::Regex;

1;
