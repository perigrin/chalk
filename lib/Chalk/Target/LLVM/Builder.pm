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
# A node no slice takes refuses the whole program by name (out(); lower_program
# returns undef and Chalk::Target::LLVM::lower dies with the reason).

package Chalk::Target::LLVM::Builder;

use Chalk::Regex::Graph;   # a constant regex as its own graph
use Chalk::MOP::Sub;
require Chalk::IR::Serialize::JSON;
use Chalk::IR::Graph;   # program_nodes, own_nodes, component: whose nodes are whose
require Chalk::IR::Analysis;   # integer_intervals, int_is_iv: T1's integer intervals


require Chalk::Target::LLVM::Node;
require Chalk::Target::LLVM::Printer;   # its %CONVERT: which conversions there are

sub out { die "T2: out of its slices ($_[0])\n" }

# eval_regions_at(@nodes) -> { entry node address => the eval's Region }. A TRY MAKES NO NODE
# WHERE IT BEGINS, so a try or eval beginning its body names the same entry,
# and a map keyed by it kept one of the two: the outer catch was lost (re-audit
# 2026-11-23, section 3 H: `try { try { die } catch ($e) { die "o" } } catch
# ($e) { ... }` died "o"). Refused by name.
sub eval_regions_at (@nodes) {
    my %at;
    for my $r ( grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } @nodes ) {
        my $k = refaddr( $r->eval_entry );
        out('two evals entered at one node (a try whose body begins with a try or an eval)')
            if $at{$k} && $at{$k} != $r;
        $at{$k} = $r;
    }
    return \%at;
}

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
               : $start->operation =~ /\A(?:Region|Proj|Exc)\z/ ? $start->inputs->[0]
               : out('no way back to Start from ' . $start->operation);
    }
    $b->{ret} = $ret;
    # T1'S INTEGER INTERVALS, which an integer + - * asks before it is an i64
    # op (Chalk::IR::Analysis::integer_intervals: run in T1; here where it has
    # not, a graph made without it).
    Chalk::IR::Analysis::integer_intervals($ret);
    # (THE PROGRAM'S Return, for what asks of the whole program: in a sub,
    # {ret} is the sub's -- a question asked there first saw only the sub)
    $b->{root_ret} = $ret;
    $b->{own_nodes} = [ Chalk::IR::Graph::own_nodes($ret) ];
    $b->{eval_at} = eval_regions_at( $b->{own_nodes}->@* );
    $b->{evals} = [];
    $b->{passed} = [ grep { $_->operation eq 'MemStart' } Chalk::IR::Graph::own_nodes($ret) ];
    $b->index_readers(Chalk::IR::Graph::own_nodes($ret));
    $b->new_block('entry');
    $b->emit(op => 'SaveArgs', type => 'void');   # argv, for @ARGV
    # $^T: the time the program started, kept here for every read of it.
    $b->emit(op => 'GStore', type => 'void', inputs => [ $b->as( $b->emit(op => 'Time', type => 'i64'), '%Slot' ) ], attr => { global => $b->global_named("perl's start time") })
        if grep { $_->operation eq 'EntryDef' && ( $_->special_scalar // '' ) eq 'start_time' } _all_nodes($b->{mop}, $ret);
    # (a tie calls its class's methods too)
    # (and `isa`, and a method named at run time, look through it)
    $b->make_mop if $b->special_containers->%* || grep { $_->operation eq 'IsaOp' || $_->operation eq 'Call' && ( ( $_->dispatch_kind // '' ) =~ /\A(?:method|dynamic_method)\z/ || ( $_->builtin_kind // '' ) eq 'binds' ) } _all_nodes($b->{mop}, $ret);
    $b->special_startup;
    $b->glob_stashes;
    # $_ ALIASED (topic_alias): outside any alias it is $main::_ itself.
    $b->emit(op => 'GStore', type => 'void', attr => { global => $b->global_named('my::0topic') },
        inputs => [ $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->emit(op => 'GAddr', type => '%Slot*', attr => { global => $b->global_named('main::_') }) ]) ])
        if $b->topic_alias;
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
            if $kind eq 'BEGIN' && grep { $_->operation eq 'PadAccess' && ( $_->shared || !defined $_->inputs->[0] && !blessed( $_->mem_in ) ) }
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

# emit_entry_end(%n): a node made at the function's entry, after what is there
# (here, when the walk is still in it).
sub emit_entry_end {
    my ($b, %a) = @_;
    return $b->emit(%a) if refaddr( $b->{cur} // 0 ) == refaddr( $b->{blocks}[0] );
    my $n = Chalk::Target::LLVM::Node::_n(%a);
    push $b->{blocks}[0]{nodes}->@*, $n;
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
    return 1 if $n->operation eq 'Call' && $n->gives_a_list;
    # A MATCH IN LIST CONTEXT (B::SoN stamps it Boolean): by what takes it.
    return _match_in_list($n) if $n->operation =~ /\A(?:RegexMatch|Match)\z/;
    return 1 if $n->operation eq 'PadAccess' && ( $n->sigil // '' ) =~ /\A[@%]\z/;
    # (a merge of an array's or a hash's versions, B::SoN's stamp Unknown or
    # Hash: `@p` after a loop that whole-assigns it -- one it refuses is
    # refused where it is typed)
    return 1 if $n->operation eq 'Phi' && !$n->memory && eval { Chalk::Target::LLVM::Builder::agg_versions(undef, $n) };
    return 1 if $Chalk::Target::LLVM::Builder::LIST_FIELD{ refaddr($n) };
    return 1 if _refs_each_item($n);
    return 0;
}

# _refs_each_item($Ref) -> `\(c ? ($x, $y) : ())`: perl's reference of a list
# written out is a list of a reference to each item (B::SoN stamps the Ref
# ArrayRef) -- a choice, an arm a list of items or one, each a scalar T2
# makes a reference to (scalar_ref). (`\(c ? @a : @b)` is a reference to the
# array taken: not this.)
sub _refs_each_item {
    my ($n) = @_;
    return 0 unless blessed($n) && $n->operation eq 'Ref' && !$n->each;
    my $t = $n->inputs->[0];
    return 0 unless blessed($t) && $t->operation eq 'TernaryExpr';
    my $lit = sub ($x) { blessed($x) && $x->operation eq 'ArrayLiteral' && !defined $x->symbol && ( $x->stamp // '' ) eq 'Array' };   # static type
    my @arms = $t->inputs->@[1, 2];
    return 0 unless grep { $lit->($_) } @arms;
    for my $a (@arms) {
        my @items = $lit->($a) ? $a->inputs->@* : ($a);
        return 0 if grep { !Chalk::Target::LLVM::Builder::_scalar_ref_of($_) } @items;
    }
    return 1;
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
        # (a value it takes: a statement after a pinned match that takes the
        # match as its memory version names it by mem_in, not an input)
        my @args = $c->inputs->@*;
        next unless grep { blessed($_) && refaddr($_) == refaddr($n) } @args;
        my $is_in = sub ($x) { grep { blessed($_) && refaddr($_) == refaddr($x) } @args };
        # (returned: the sub gives its list or its truth by its caller's context -- func)
        next if $op eq 'Return' && $c->inputs->@* == 1;
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
    # (CALLED IN SCALAR CONTEXT by perl's own op -- B::SoN's want=scalar,
    # `my $l = $n->name; ... push @f, $l` folded to the call -- is a scalar
    # wherever its value goes: perl called it once, for one value)
    return 0 if ( $c->can('want') ? $c->want // '' : '' ) eq 'scalar';
    my ($list, $scalar) = _use_counts($c, {});
    out('a call used both as a list and as a scalar') if $list && $scalar;
    return $list ? 1 : 0;
}

# _use_counts($n, $seen) -> (list uses, scalar uses) of $n's value; a merge
# it is a way into is used as the merge is.
sub _use_counts {
    my ($c, $seen_phi) = @_;
    my ($list, $scalar) = (0, 0);
    $list++ if $PRINTED{ refaddr($c) };
    my %seen;
    for my $u (grep { blessed($_) && !$seen{ refaddr($_) }++ } ( $c->consumers // [] )->@*) {
        my $op = $u->operation;
        # (the call as a memory version -- a read after it, a store's memory
        # -- is its mem_in, no input: not a use of its value)
        my @pos = grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($c) } 0 .. $u->inputs->$#*;
        # (a scalar Assign's last input, its value, is not counted -- a LIST
        # assign's is its list: `my ($x, $y) = f()`)
        @pos = grep { $_ != $u->inputs->$#* } @pos if $u->operation eq 'Assign'
            && !( $u->can('targets') && defined $u->targets );
        # (a control node's first input is its control: a call on the chain
        # before a loop is the Loop's way in, not a use of its value)
        # (nor is an Exc's: its way out if it dies)
        @pos = () if $op =~ /\A(?:Loop|Region|Proj|Exc)\z/;
        @pos = grep { $_ != 0 } @pos if $op eq 'If';
        next unless @pos;
        my $at0 = grep { $_ == 0 } @pos;   # (a bare grep in an || chain takes the rest as its list)
        my $at1 = grep { $_ == 1 } @pos;
        # (a hash literal's items are a list too: `(a => f(), b => 1)` calls f
        # for a list, as many items as it returns -- fifth final audit, Q16.
        # Only where nothing else reads the call: `%h = f()` counted too, in
        # a loop's test, counted the hash's list wrong -- refused there, as
        # a call read both ways is.)
        my $only_hash = $op eq 'HashLiteral' && !grep {
            my $o = $_;
            blessed($o) && refaddr($o) != refaddr($u) && $o->operation !~ /\A(?:Loop|Region|Proj|Exc)\z/ && !( $o->operation eq 'Phi' && $o->memory )
                && grep { blessed($_) && refaddr($_) == refaddr($c) } $o->inputs->@*
        } ( $c->consumers // [] )->@*;
        if ($op eq 'ArrayLiteral' || $only_hash || $op eq 'Print'
            || $op eq 'Call' && ( $u->dispatch_kind // '' ) eq 'direct'
            || $op eq 'Call' && ( $u->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/ && !$at0   # not the invocant, nor the code
            || $op eq 'Call' && $u->takes_a_list && !$at0   # (push's list, join's: not its array, its separator)
            || $op eq 'ListAppend' && $at1
            || $op eq 'Return' && $u->inputs->@* == 2 && $at0
            || $op eq 'Assign' && $u->can('targets') && defined $u->targets) { $list++ }   # `my ($x, $y) = f()`
        elsif ($op eq 'Coerce' && $PRINTED{ refaddr($c) }) { }   # print's (counted above)
        elsif ($op eq 'Phi' && $u->memory) { }   # (the call as a memory version: no value)
        elsif ($op eq 'Phi' && !$u->memory && blessed( $u->region ) && $u->region->operation eq 'Region'
               && ( $u->stamp // '' ) =~ /\A(?:List|Array)\z/) {   # static type
            # a merge of lists: its own use decides (`my @c = $p ? two() : ()`)
            # (a merge of scalars is one value: T2 takes the call's scalar)
            next if $seen_phi->{ refaddr($u) }++;
            my ($l, $s) = _use_counts($u, $seen_phi);
            $list += $l; $scalar += $s;
        }
        elsif ($op =~ /\A(?:Phi|Return)\z/) { }   # a loop's merge or a tail call: its own use decides
        else { $scalar++ }
    }
    return ($list, $scalar);
}

# list_only($n, $what): a list value (a slice, a range) is a list only where
# what takes it takes a list -- print's, a list's element, a builtin's list,
# a list assign, map's and grep's walk (its count and elements). Taken as a
# scalar (a slice's last element, a range's flip-flop) it is refused.
sub list_only {
    my ($b, $n, $what, %o) = @_;
    for my $u (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        # (A READ PINNED where it stands is a memory version and a control: a
        # later read's memory -- its mem_in --, a loop's or a merge's way in,
        # takes no value)
        my @pos = grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($n) } 0 .. $u->inputs->$#*;
        next unless @pos;
        my $op = $u->operation;
        # (an Exc's input is what may die, its way out: no value taken)
        next if $op =~ /\A(?:Loop|Region|If|Proj|Exc)\z/;
        next if $op eq 'Phi' && $u->memory;   # (a merge of memory versions)
        my $at0 = grep { $_ == 0 } @pos;
        next if $op eq 'Coerce' && !grep { blessed($_) && $_->operation ne 'Print' } ( $u->consumers // [] )->@*;
        next if $op =~ /\A(?:ArrayLiteral|HashLiteral|Print)\z/;
        next if $op eq 'Count' && $at0;
        # (a hash's: its elements, keys and values are the hash's own)
        next if $o{hash_ok} && $at0 && ( $op =~ /\A(?:Subscript|Exists|Delete)\z/
                                         || $op eq 'Call' && $u->takes_a_hash );
        next if $op eq 'Subscript' && $at0 && @pos == 1 && ( $u->can('kind') ? $u->kind // 'array' : 'array' ) eq 'array';
        next if $op eq 'Slice' && !grep { $_ == $u->inputs->$#* } @pos;   # its indices
        next if $op eq 'ListAppend' && !$at0;
        next if $op eq 'TernaryExpr' && !$at0;   # an arm: the choice's own use decides
        # (a way into a merge of arrays: the merge is an array, its own use decides)
        next if $op eq 'Phi' && ( ( eval { $b->phi_type($u) } // '' ) eq '%Array*' );
        next if $op eq 'Assign' && $u->can('targets') && defined $u->targets;
        next if $op eq 'Call' && ( $u->is_sub_call && !( $at0 && ( $u->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/ )
                                   || $u->takes_a_list && !$at0 );
        out("$what taken as a scalar ($op)");
    }
}

# _value_read($n) -> some node takes $n's value as an input -- not only as its
# memory version (a later read of the array: its mem_in) or its control.
sub _value_read {
    my ($b, $n) = @_;
    # (an Exc is its way out if it dies, not a read of its value)
    for my $c (grep { blessed($_) && $_->operation ne 'Exc' } ( $n->consumers // [] )->@*) {
        return 1 if grep { blessed($_) && refaddr($_) == refaddr($n) } $c->inputs->@*;
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
