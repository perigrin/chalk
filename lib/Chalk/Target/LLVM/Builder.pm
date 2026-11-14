# ABOUTME: The LLVM T2 builder: the lowering functor from a chalk IR graph to a graph of
# ABOUTME: Chalk::Target::LLVM::Node, typed in LLVM's types.
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

# Undef and a Scalar nothing narrowed are each a %Slot: its tag says which.
my %SCALAR = (Int => 'i64', Num => 'double', Str => '%Str', Boolean => 'i1', Undef => '%Slot', Scalar => '%Slot');
my %ARITH  = (Add => 'add', Subtract => 'sub', Multiply => 'mul');
my %SCMP   = (StrEq => 'eq', StrNe => 'ne', StrLt => 'lt', StrGt => 'gt', StrLe => 'le', StrGe => 'ge');
my %CMP    = (NumLt => 'lt', NumGt => 'gt', NumLe => 'le', NumGe => 'ge', NumEq => 'eq', NumNe => 'ne');

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

# walk($ctl): the statements after $ctl, in order, to a Return or the end of
# a body. A statement of a kind T2 does not have makes the program fall back:
# skipped, its effect would be lost.
sub walk {
    my ($b, $ctl) = @_;
    $b->open_eval($ctl);
    while (1) {
        # A STATEMENT AN EVAL'S BODY FOLLOWS opens it; the body's end closes it
        # at its Region, where the body's end and its catch meet.
        $b->open_eval($ctl);
        if (my $r = $b->eval_region_after($ctl)) { $ctl = $b->close_eval($r); next }
        my @s = $ctl->successors;
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
        # (WHERE EACH STATEMENT STANDS: its turn and its block -- hash_reads_settled
        # makes a waiting read at the store right after the read's own version)
        $b->{at}{ refaddr($s) } = [ ++$b->{seq}, refaddr( $b->{cur} // 0 ) ];
        # A STATEMENT A READ TAKES AS ITS MEMORY must be a version T2 orders
        # reads by (is_memory_version): a new store kind missing there let reads after
        # it be made after the next store (three wrong answers, slices 14-15).
        out("a statement $op that versions memory T2 does not order reads by")
            if !$s->is_memory_version && grep { my $m = blessed($_) ? $_->memory_operand : undef; blessed($m) && refaddr($m) == refaddr($s) } ( $s->consumers // [] )->@*;
        return $ctl if $op eq 'Return';
        if ($op eq 'Print') {
            # TO STDOUT OR STDERR BY NAME (B::SoN: has_filehandle, the glob
            # first): file descriptor 1 or 2. Another filehandle is refused.
            my @args = $s->inputs->@*;
            my $fd = 1;
            if ( $s->can('has_filehandle') && $s->has_filehandle ) {
                my $fh = shift @args;
                my $name = blessed($fh) && $fh->operation eq 'Constant' && ( $fh->stamp // '' ) eq 'Glob' ? $fh->value // '' : '';
                $fd = { STDOUT => 1, STDERR => 2 }->{ $name =~ s/\A(?:main)?:://r }
                    // out('a print to a filehandle other than STDOUT or STDERR');
            }
            # One print of each argument, in order (perl prints the list); a
            # list's elements one after another ($, is "" until written).
            for my $in (@args) {
                # (a list B::SoN coerced to a string for print is printed as a list;
                # a copy: the loop variable aliases the Print's own inputs, and
                # assigning it rewrote the graph the fallback then lowered)
                my $x = $in;
                $x = $x->inputs->[0] if $x->operation eq 'Coerce' && blessed( $x->inputs->[0] ) && _is_list( $x->inputs->[0] );
                if (_is_list($x)) {
                    out('$, written') if $b->{writes_out_sep} //= scalar grep {
                        $_->operation =~ /\A(?:EntryWrite|LocalAlias)\z/ && grep { blessed($_) && $_->can('symbol') && ( $_->symbol // '' ) eq ',' } ( $_, $_->inputs->@* )
                    } _all_nodes($b->{mop}, $b->{ret});
                    my $none = $b->const_str('');
                    $b->emit(op => 'Print', type => 'void', inputs => [ $b->emit(op => 'Join', type => '%Str', inputs => [ $none, $b->array_of($x) ]) ], attr => { fd => $fd });
                    next;
                }
                $b->emit(op => 'Print', type => 'void', inputs => [ $b->as($b->value($x), '%Str') ], attr => { fd => $fd });
            }
            # ITS VALUE is 1 (perl's print returns true): a block's last
            # statement, a try's catch.
            $b->{memo}{ refaddr($s) } = $b->emit(op => 'Const', type => 'i64', attr => { value => 1 });
            $ctl = $s;
        }
        elsif ($op eq 'Loop') { $ctl = $b->loop($s) }
        elsif ($op eq 'If')   { $ctl = $b->if_stmt($s) // return undef }   # (undef: both arms left the loop)
        # A READ OF A TIED AGGREGATE PINNED where it runs (B::SoN): a FETCH,
        # FETCHSIZE or EXISTS call, made here, in order.
        elsif ($op eq 'RegexSubst' || $op eq 'Transliterate') { $b->regex_subst_stmt($s); push $b->{passed}->@*, $s; $ctl = $s }
        elsif ($op =~ /\A(?:Subscript|Count|Exists|PostfixDeref|RegexMatch|Match)\z/
               || $op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:keys|values|join|sort|caller|pos)\z/) {
            $b->value($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # A tie OR untie in place: every later access of the container is the new metaobject's.
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:tie|untie|bless)\z/) {
            $b->value($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:push|unshift|shift|pop)\z/) {
            $b->array_stmt($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # `my (...) = @_` PINNED (a call follows it): its reads are the
        # arguments already (args), nothing to store.
        elsif ($b->{args} && $s->is_args_list_assign) {
            $b->{argsarr} ? $b->list_args_assign($s) : $b->args_assign($s);
            $ctl = $s;
        }
        elsif ($op eq 'Assign') { $b->assign($s); push $b->{passed}->@*, $s; $ctl = $s }
        # AN UNCAUGHT DIE: its message (a list joined) to STDERR, " at FILE
        # line N.\n" added where it does not end in a newline, and exit 255.
        # The block ends there: nothing after it in its arm runs.
        elsif ($op eq 'Unwind') {
            my @m = grep { blessed($_) } $s->inputs->@*;
            pop @m if $s->can('memory_input') && $s->memory_input;
            out('a die of a list') if grep { _is_list($_) } @m;
            my $msg = @m ? $b->as($b->value( shift @m ), '%Str') : $b->const_str('Died');
            $msg = $b->emit(op => 'Concat', type => '%Str', inputs => [ $msg, $b->as($b->value($_), '%Str') ]) for @m;
            my $at = ' at ' . ( $s->can('file') ? $s->file // '-' : '-' ) . ' line ' . ( $s->can('line') ? $s->line // 0 : 0 ) . ".\n";
            my $full = $b->emit(op => 'DieMsg', type => '%Str', inputs => [ $msg, $b->const_str($at) ]);
            if (my $f = ( $b->{evals} // [] )->[-1]) {
                # IN AN EVAL HERE: $@ is the message, and on to its catch.
                out('a die of another eval than the one open here') if defined $s->eval_id && $s->eval_id ne ( $f->{region}->eval_id // '' );
                $b->emit(op => 'SetErr', type => 'void', inputs => [$full]);
                $b->{cur}{term} = [ 'br', $b->eval_catch($f) ];
            }
            elsif ($b->{has_eval} && $b->{in_func}) {
                # AN EVAL MAY BE OPEN UP THE CALLS: caught there (the dying flag
                # unwinds every caller), else perl's exit.
                $b->emit(op => 'DieUnwind', type => 'void', inputs => [$full]);
                $b->{cur}{term} = [ 'retval', $b->emit(op => 'Undef', type => '%Slot') ];
            }
            else {
                $b->emit(op => 'Die', type => 'void', inputs => [$full]);
                $b->{cur}{term} = ['unreachable'];
            }
            $b->{cur}{dead} = 1;
            # WHAT FOLLOWS A DIE never runs: it goes in a block of its own, no
            # way into it (in the die's block it ran before the branch: `eval {
            # die "b"; print "c" }` printed c).
            my $dead = $b->new_block('dead');
            $dead->{term} = ['unreachable'];
            $dead->{dead} = 1;
            $ctl = $s;
        }
        # exit: the process ends with the status (0 when none is given). Like
        # a die, nothing after it in its block runs.
        # shortcut: END blocks are not run (T2 refuses a program with one).
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) eq 'exit') {
            my ($x) = grep { blessed($_) } $s->inputs->@*;
            my $v = $x && !( $s->can('memory_input') && $s->memory_input && refaddr($x) == refaddr( $s->memory_input ) )
                ? $b->as( $b->value($x), 'i64' )
                : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
            $b->emit(op => 'Exit', type => 'void', inputs => [$v]);
            $b->{cur}{term} = ['unreachable'];
            $b->{cur}{dead} = 1;
            my $dead = $b->new_block('dead');
            $dead->{term} = ['unreachable'];
            $dead->{dead} = 1;
            $ctl = $s;
        }
        # A STORE THROUGH A CELL (a captured variable written): what it is
        # given, then the store into the variable's storage.
        elsif ($op eq 'CellWrite') {
            my ($cell, $val) = $s->inputs->@[0, 1];
            my $v = $b->as($b->value($val), '%Slot');
            my $ptr = $b->value($cell);
            $b->hash_reads_settled('a store to a captured variable');
            $b->emit(op => 'Store', type => 'void', inputs => [ $v, $ptr ]);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # A delete (or an exists) on the chain: made where it stands.
        elsif ($op =~ /\A(?:Delete|Exists)\z/ && ( $s->can('kind') ? $s->kind // '' : '' ) eq 'hash') {
            $b->hash_reads_settled('a delete') if $op eq 'Delete';
            $b->value($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # map's `$_` FOR A CALLEE: its body reads the element itself; only code
        # reading the global $_ needs it -- none in the program, a no-op.
        elsif ($op eq 'LocalAlias' && ( $s->can('name') ? $s->name // '' : '' ) eq '_') {
            out('a $_ aliased where the program reads $_')
                if grep { $_->is_package_scalar && $_->symbol eq '_' && grep { blessed($_) && $_->operation ne 'EntryWrite' } ( $_->consumers // [] )->@* }
                   _all_nodes($b->{mop}, $b->{ret});
            $ctl = $s;
        }
        # `package X;` names the package code after it is in: nothing T2 reads.
        elsif ($op eq 'PackageMark') { $ctl = $s }
        # A CHOICE PINNED WHERE IT RUNS (B::SoN pins one that reads memory, `$n
        # > 1 ? ... : ...` of a package scalar): its value made here, in order.
        # (A FOREACH ALIAS'S GUARDED REFERENCE is never made: its deref is the element.)
        elsif ($op eq 'TernaryExpr') { $b->value($s) unless $s->is_alias_guard; push $b->{passed}->@*, $s; $ctl = $s }
        # A READ OF $@ ON THE CHAIN is made where it stands: a caught die sets
        # $@ with no store in the graph, so only its place orders it.
        # (B::SoN gives two reads of $@ around a caught die one version, and
        # the pipeline makes them one node: what is made from the first stands
        # for both -- the outer eval's message printed the inner's, "in" for
        # "out". Forgetting it would make a value saved from the first, used
        # later, read the second. A $@ read already made is refused here.)
        elsif ($op eq 'EntryDef' && $s->is_package_scalar) {
            out('a $@ read B::SoN made one node with an earlier one') if $s->symbol eq '@' && $b->{memo}{ refaddr($s) };
            $b->value($s);
            $ctl = $s;
        }
        # A PACKAGE SCALAR WRITTEN: what it held is read first, then stored.
        elsif ($op eq 'EntryWrite' && ( $s->inputs->[0] isa Chalk::IR::Node && $s->inputs->[0]->is_package_scalar )) {
            out('a local') if $s->can('local') && $s->local;
            my $val = $b->as($b->value($s->inputs->[1]), '%Slot');
            $b->hash_reads_settled('a package store');
            $b->emit(op => 'GStore', type => 'void', inputs => [$val], attr => { global => $b->global_of($s->inputs->[0]) });
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # `local @a` / `local %h` (B::SoN's glob binds): THE SWAP puts a fresh
        # aggregate in the global, the old one's reference saved first for
        # THE RESTORE, which puts that back. A reference taken to the old one
        # keeps its contents; a sub called inside the scope sees the new one.
        elsif ($op eq 'EntryWrite' && $s->binds && ( $s->inputs->[0] isa Chalk::IR::Node && $s->inputs->[0]->is_package_aggregate )) {
            my ($t, $v, $mem) = $s->inputs->@*;
            my $h = $t->sigil eq '%';
            $b->hash_reads_settled('a local');
            $b->reads_before($_) for $b->{passed}->@*;
            my $slot;
            if (blessed($v) && $v->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && !$v->inputs->@* && !$v->stored_whole_into) {
                # the save: a Ref over a read of this name at this store's memory version
                for my $r ( grep { blessed($_) && $_->operation eq 'Ref' } _all_nodes( $b->{mop}, $b->{ret} ) ) {
                    my $in = $r->inputs->[0];
                    next unless ( $in isa Chalk::IR::Node && $in->is_package_aggregate ) && _pkg_agg_name($in) eq _pkg_agg_name($t)
                        && blessed( $in->inputs->[-1] ) && refaddr( $in->inputs->[-1] ) == refaddr($mem);
                    my $old = $b->pkg_agg($in);
                    $b->{agg_save}{ refaddr($r) } = $h ? $old : $b->emit(op => 'ARef', type => '%Slot', inputs => [$old]);
                }
                $slot = $h ? $b->emit(op => 'HNew', type => '%Slot')
                           : $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->emit(op => 'NewArray', type => '%Array*') ]);
            }
            elsif (blessed($v) && $v->operation eq 'Ref') {
                $slot = $b->{agg_save}{ refaddr($v) } // out('a local aggregate restored with no save made');
            }
            else { out('a glob bind of a package aggregate') }
            $b->emit(op => 'GStore', type => 'void', inputs => [$slot], attr => { global => $b->global_named( _pkg_agg_name($t) ) });
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # A PACKAGE ARRAY OR HASH STORED WHOLE (`@a = LIST`): its one aggregate
        # refilled in place -- a reference taken to it sees the new contents.
        elsif ($op eq 'EntryWrite' && ( $s->inputs->[0] isa Chalk::IR::Node && $s->inputs->[0]->is_package_aggregate ) && blessed($s->inputs->[1])
               && $s->inputs->[1]->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/) {
            out('a local') if $s->can('local') && $s->local;
            my ($t, $v) = $s->inputs->@*;
            my $h = $t->sigil eq '%';
            my $list = $b->emit(op => 'NewArray', type => '%Array*');
            for my $e (grep { blessed($_) } $v->inputs->@*) {
                if (_is_list($e)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $list, $b->array_of($e) ]) }
                else { $b->emit(op => 'APush', type => 'void', inputs => [ $list, $b->as($b->value($e), '%Slot') ]) }
            }
            $b->hash_reads_settled('a package store');
            $b->reads_before($_) for $b->{passed}->@*;
            $b->emit(op => $h ? 'HAssign' : 'AAssign', type => 'void', inputs => [ $b->pkg_agg($t), $list ]);   # where it stands: a local may have swapped it
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # `@X::ISA = (...)`: the run-time MOP's parents of X, replaced.
        elsif ($op eq 'EntryWrite' && $b->isa_write($s)) { $ctl = $s }
        # A `my @a` PINNED WHERE IT RUNS (B::SoN pins one in a loop body or an
        # arm): a fresh array there, each time control reaches it.
        elsif ($op eq 'ArrayLiteral' && ( $s->stamp // '' ) =~ /\A(?:Array|ArrayRef)\z/) { $b->value($s); $ctl = $s }   # static type
        # A `{...}` PINNED WHERE IT RUNS: a fresh hash there, each time.
        elsif ($op eq 'HashLiteral' && ( $s->stamp // '' ) eq 'HashRef') { $b->value($s); $ctl = $s }   # static type
        # A `my %h = (...)` LIST PINNED where it runs: made by the assign that
        # stores it into its hash, in place.
        elsif ($op eq 'HashLiteral' && ( $s->stamp // '' ) eq 'Hash') { $ctl = $s }
        # A chdir OR A require is made where it stands (the next -d reads its cwd).
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:chdir|require)\z/) { $b->value($s); $ctl = $s }
        # `$#a = N` where it stands: the array resized (t2_aset_len).
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) eq 'set_arylen') {
            my @a = grep { blessed($_) } $s->inputs->@*;
            pop @a if $s->can('memory_input') && $s->memory_input;
            $b->emit(op => 'ASetLen', type => 'void', inputs => [ $b->array_of( $a[0] ), $b->as( $b->value( $a[1] ), 'i64' ) ]);
            $b->{memo}{ refaddr($s) } = $b->value( $a[1] );
            $ctl = $s;
        }
        # A FOUR-ARGUMENT substr (an lvalue substr, an s/// into one): its part
        # replaced in the `my` scalar where it stands.
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) eq 'substr') { $b->substr_write($s); $ctl = $s }
        # A SHIFT OF @_ BOUND TO AN ARGUMENT is on the chain for its order; its
        # value is the argument. A direct call is made where it stands.
        elsif ($op eq 'Call' && ( $b->{args}{ refaddr($s) } || $s->is_sub_call )) {
            $b->value($s);
            push $b->{passed}->@*, $s;   # B::SoN versions memory at a call
            $ctl = $s;
        }
        else { out("a statement $op" . ( $op eq 'Call' ? ' ' . ( $s->dispatch_kind // '' ) . ' ' . ( $s->name // '' ) : '' )) }
    }
    return $ctl;
}

# EVAL FRAMES. B::SoN's block eval (and try): `$@ = ""` stored before it, its
# body on the chain after the node eval_entry names, and a Region (eval_id)
# its end -- whose phis' last input is the value a caught die gives (undef).
# The body opens a frame: a die in it stores $@ and branches to the frame's
# catch; a call in it that comes back dying (the flag a die in a sub sets)
# does too. @t2_eval_depth counts the evals open at run time: a die where
# none is exits.
sub open_eval {
    my ($b, $ctl) = @_;
    my $r = $b->{eval_at}{ refaddr($ctl) } or return;
    return if $b->{eval_opened}{ refaddr($r) }++;
    out('an eval whose body makes a value that may die') if $r->can('eval_may_die') && $r->eval_may_die;
    # IN LIST OR ITS CALLER'S CONTEXT a caught die gives the empty list, not undef.
    out('an eval in list or its caller\'s context') if $r->can('eval_want') && defined $r->eval_want;
    $b->hash_reads_settled('an eval');
    $b->emit(op => 'EvalEnter', type => 'void');
    push $b->{evals}->@*, { region => $r, catch => undef, depth => $b->{depth} // 0, start => $b->{cur}, made_before => { map { ( $_ => 1 ) } keys $b->{memo}->%* } };
}

sub eval_catch {
    my ($b, $f) = @_;
    return $f->{catch} //= do {
        my $here = $b->{cur};
        my $c = $b->new_block('catch');
        $b->{cur} = $here;
        $c;
    };
}

# eval_region_after($ctl) -> the open eval's Region when $ctl is its body's end.
sub eval_region_after {
    my ($b, $ctl) = @_;
    my $f = ( $b->{evals} // [] )->[-1] or return;
    my $r = $f->{region};
    return ( grep { blessed($_) && refaddr($_) == refaddr($ctl) } $r->inputs->@* ) ? $r : undef;
}

sub close_eval {
    my ($b, $r) = @_;
    # (popped once the body's value is made: a divide there is the eval's to catch)
    my $f = $b->{evals}[-1];
    out('an eval closed at another depth') if ( $b->{depth} // 0 ) != $f->{depth};
    out('an eval Region of more than one way in') if $r->inputs->@* != 1;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($r)
                      && !$_->is_memory } ( $r->consumers // [] )->@*;
    my %seen; @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my $dead = $b->{cur}{dead};
    my @in;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        push @in, [ $p, $ty, $dead ? undef : $b->as($b->value( $p->inputs->[0] ), $ty) ];
    }
    pop $b->{evals}->@*;
    my $end = $b->{cur};
    unless ($dead) {
        # AN EVAL ENDING WITHOUT A DIE leaves $@ "" (an inner one's caught die
        # was left in it: "[x]" for "[]").
        $b->emit(op => 'SetErr', type => 'void', inputs => [ $b->const_str('') ]);
        $b->emit(op => 'EvalLeave', type => 'void');
    }
    my $join = $b->new_block('evaljoin');
    $end->{term} = [ 'br', $join ] unless $dead;
    my @from = $dead ? () : ($end);
    my @cv;
    if (my $c = $f->{catch}) {
        $b->{cur} = $c;
        $b->emit(op => 'EvalLeave', type => 'void');
        $b->emit(op => 'ClearDying', type => 'void');
        # (a value made here is the catch's: not seen after -- an undef made in
        # one eval's catch was another's phi input, not dominating it)
        local $b->{memo} = { $b->{memo}->%* };
        @cv = map { $b->as($b->value( $_->[0]->inputs->[-1] ), $_->[1]) } @in;
        $c = $b->{cur};
        $c->{term} = [ 'br', $join ];
        push @from, $c;
    }
    out('an eval of no way to its end') unless @from;
    # A VALUE THE BODY MADE past its first block need not dominate the join
    # (a die skips it): a constant is made again where it is next read;
    # anything else is refused (the 1 one try made was the next try's: "does
    # not dominate all uses"). One made in the first block is before any die.
    my %first = map { ( refaddr($_) => 1 ) } $f->{start}{nodes}->@*;
    # (dropped here, not at that read: one made first in an arm went with the
    # arm's copy, and the next eval read this one -- "does not dominate")
    for my $k (grep { my $m = $b->{memo}{$_}; !$f->{made_before}{$_} && !( ref $m && $first{ refaddr($m) } ) } keys $b->{memo}->%*) {
        $b->{past_eval}{$k} = 1;
        delete $b->{memo}{$k};
    }
    $b->{cur} = $join;
    for my $i (0 .. $#in) {
        my ($p, $ty, $nv) = $in[$i]->@*;
        my @vals = ( ( $dead ? () : $nv ), ( $f->{catch} ? $cv[$i] : () ) );
        $b->{memo}{ refaddr($p) } = @vals == 1 ? $vals[0]
            : $b->emit(op => 'Phi', type => $ty, inputs => \@vals, attr => { from => [@from] });
    }
    push $b->{passed}->@*, $r, $r->memory_phis;   # (its join's memory version: B::SoN's, the $@ a die set)
    return $r;
}

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
    my $go = $f ? $b->eval_catch($f) : do {
        my $up = $b->new_block('unwind');
        $up->{term} = [ 'retval', $b->emit(op => 'Undef', type => '%Slot') ];
        $up;
    };
    my $cont = $b->new_block('cont');
    $here->{term} = [ 'condbr', $d, $go, $cont ];
    $b->{cur} = $cont;
}

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
        out('a read after `my (...) = @_` of no target') unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*;
        $b->{args}{ refaddr($r) } = $arg_of{ $r->symbol } // out('a read after `my (...) = @_` of no target');
    }
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

# emit_entry(%n): a node made at the function's entry (first block's start),
# where each `my` aggregate of the function is made.
sub emit_entry {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::Node::_n(%a);
    unshift $b->{blocks}[0]{nodes}->@*, $n;
    return $n;
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

# if_stmt($If) -> the Region the program continues from: the condition, each
# arm walked in its own block from its Proj (0 true, 1 false), and at the join
# a phi of each value the Region merges, from the end of each arm.
sub if_stmt {
    my ($b, $if) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } $if->successors_by_input;
    out('an if without two arms') unless $proj{0} && $proj{1};
    # EVERY READ MADE SO FAR IS MADE HERE, before the arms: one built in an arm
    # (before a store there) is the arm's, and a use after the join would load
    # it again, after the store (`my $x = $i; if ($c) { $i = 5 } print $x`).
    $b->reads_before($_) for $b->{passed}->@*;
    my $cond = $b->truth($b->value($if->inputs->[1]));
    my $from = $b->{cur};
    my (%end, %blk, %vals);
    for my $i (0, 1) {
        my $blk = $b->new_block($i ? 'else' : 'then');
        $blk{$i} = $blk;
        local $b->{memo} = { $b->{memo}->%* };   # an arm's values are the arm's
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $if->inputs->[1], $i );
        $end{$i} = $b->walk($proj{$i});
        # The arm's memo is kept: its phi inputs are read from it (a call made
        # in the arm is that value, not made again).
        $vals{$i} = { block => $b->{cur}, ctl => $end{$i}, memo => $b->{memo} };
    }
    $from->{term} = [ 'condbr', $cond, $blk{0}, $blk{1} ];
    # IN A LOOP THAT LEAVES OR GOES ROUND FROM ITS BODY (see loop_breaks): an
    # arm that reaches the loop's exit or its latch is that loop's edge, made
    # there; the if goes on from the other arm, or (both left) the body ends.
    if ( my $lx = $b->{loopx} ) {
        my $meet = defined $end{0} && defined $end{1} && do {
            my ($r) = grep { $_->operation eq 'Region' } ( $end{0}->consumers // [] )->@*;
            $r && refaddr($r) != refaddr( $lx->{exit} ) && grep { blessed($_) && refaddr($_) == refaddr($end{1}) } $r->inputs->@*;
        };
        unless ($meet) {
            my %left = map { ( $_ => ( !defined $end{$_} || $b->loop_edge( $lx, $end{$_}, $vals{$_} ) || $b->loop_jump( $end{$_}, $vals{$_} ) ) ) } 0, 1;
            if ( $left{0} && $left{1} ) { $b->{cur} = $b->new_block('left'); $b->{cur}{dead} = 1; $b->{cur}{term} = ['unreachable']; return undef }
            if ( $left{0} || $left{1} ) {
                my $go = $left{0} ? 1 : 0;
                $b->{cur}  = $vals{$go}{block};
                $b->{memo} = $vals{$go}{memo};
                return $end{$go};
            }
        }
    }
    my ($region) = grep { $_->operation eq 'Region' } ( $end{0}->consumers // [] )->@*;
    # ARMS THAT DO NOT MEET: one leaves early (`// return` in an arm) for a
    # merge further out. That arm waits there (jump); the if goes on from the
    # other, which is where its statements continue (pvm 093).
    unless ($region && grep { refaddr($_) == refaddr($end{1}) } grep { blessed($_) } $region->inputs->@*) {
        my %far = map { my $i = $_; ( $i => [ grep { $_->operation eq 'Region' } ( $end{$i}->consumers // [] )->@* ] ) } 0, 1;
        my ($jump) = grep { my $i = $_; $far{$i}->@* == 1 && $far{$i}[0]->reached_by($end{ 1 - $i }) } 0, 1;
        out('an if whose arms do not meet') unless defined $jump;
        my $r = $far{$jump}[0];
        push $b->{jumps}{ refaddr($r) }->@*, { $vals{$jump}->%*, end => $end{$jump} };
        my $go = 1 - $jump;
        $b->{cur}  = $vals{$go}{block};
        $b->{memo} = $vals{$go}{memo};
        return $end{$go};
    }
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($region)
                      && !$_->is_memory } ( $region->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    # Each Region input is an arm's end; the phi's input of the same place is
    # that arm's value -- made in the arm, where it is live.
    my @arm_of = map { my $in = $_; ( grep { refaddr($end{$_}) == refaddr($in) } 0, 1 )[0] } $region->inputs->@*;
    out('an if Region whose ways in are not its arms') if grep { !defined } @arm_of;
    # AN ARM THAT DIED ends where it died: no way into the join from it.
    my @live = grep { !$vals{ $arm_of[$_] }{block}{dead} } 0 .. $#arm_of;
    out('an if both of whose arms die') unless @live;
    my @made;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        my @in;
        for my $k (@live) {
            my $arm = $arm_of[$k];
            local $b->{cur} = $vals{$arm}{block};
            local $b->{memo} = $vals{$arm}{memo};
            local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $if->inputs->[1], $arm );   # (its phi input made in that arm)
            push @in, [ $ty eq '%Array*' ? $b->as_list( $p->inputs->[$k] ) : $b->as($b->value($p->inputs->[$k]), $ty), $arm ];
            # MAKING IT MAY MAKE BLOCKS (a ?: B::SoN folded an inner if into):
            # the arm ends where that left off (it ended before, a phi from
            # the old end, and that block's condbr overwritten by the br).
            $vals{$arm}{block} = $b->{cur};
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block('join');
    $_->{block}{term} = [ 'br', $join ] for grep { !$_->{block}{dead} } values %vals;
    for my $m (@made) {
        my ($p, $ty, $in) = @$m;
        $b->{memo}{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty,
            inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $vals{ $_->[1] }{block} } @$in ] });
    }
    push $b->{passed}->@*, $region->memory_phis;
    return $region;
}

# join_jumps($ctl) -> the merge the walk goes on from, or undef: where control
# runs out at $ctl and $ctl feeds a merge an earlier arm jumped to, that merge
# is made -- each jump and this way in a predecessor, each phi's input made in
# its own predecessor's block.
sub join_jumps {
    my ($b, $ctl) = @_;
    my ($r) = grep { $_->operation eq 'Region' && $b->{jumps}{ refaddr($_) } } ( $ctl->consumers // [] )->@*;
    return undef unless $r;
    my @preds = ( +(delete $b->{jumps}{ refaddr($r) })->@*, { block => $b->{cur}, ctl => $ctl, end => $ctl, memo => $b->{memo} } );
    out('an early exit joined where an arm died') if grep { $_->{block}{dead} } @preds;
    my @ways = $r->inputs->@*;
    my @pred_of = map { my $in = $_; ( grep { blessed($in) && refaddr($preds[$_]{end}) == refaddr($in) } 0 .. $#preds )[0] } @ways;
    out('a merge with a way in no arm reached') if grep { !defined } @pred_of;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($r)
                      && !$_->is_memory } ( $r->consumers // [] )->@*;
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
            push @in, [ $ty eq '%Array*' ? $b->as_list( $p->inputs->[$k] ) : $b->as($b->value($p->inputs->[$k]), $ty), $pr ];
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
    push $b->{passed}->@*, $r->memory_phis;
    return $r;
}

# call($Call) -> the %Slot a direct call of a sub returns: its function, made
# once, called with each argument boxed (one not passed is undef).
sub call {
    my ($b, $c) = @_;
    # A DIRECT CALL OF A CLOSURE (`$f->()` B::SoN resolved): through the code
    # value its AnonSub makes in this function -- its cells are there.
    if (( $c->name // '' ) =~ /__ANON__/) {
        my @anon = grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } +($b->{own_nodes} // [])->@*;
        out('a direct call of a closure made elsewhere') unless @anon == 1;
        my @args = $c->inputs->@*;
        pop @args if $c->can('memory_input') && $c->memory_input;
        return $b->code_call($c, $b->value( $anon[0] ), @args);
    }
    my $sub = $c->target;
    out( $c->name . ' is XS: there is no Perl source to compile' ) if $c->can('xs') && $c->xs;
    out('a direct call with no sub') unless blessed($sub) && $sub->can('graph') && $sub->graph;
    my $fn = $b->func($sub, $c->name);
    my @args = $c->inputs->@*;
    pop @args if $c->can('memory_input') && $c->memory_input;
    # `&f;` IS CALLED WITH THE CALLER'S OWN @_ (the same array: a shift there
    # is seen here): both must take @_ as an array.
    if ($c->can('shares_args') && $c->shares_args) {
        out('an & call sharing @_ of a sub not taking it as a list') unless $fn->{list} && $b->{argsarr};
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $b->{argsarr} ], attr => { fn => $fn->{name} }, site => $c);
    }
    # A SIGNATURE WITH A SLURPY TAIL dies with too few arguments, or an odd
    # count into a slurpy hash (perl's "Too few arguments", "Odd name/value"):
    # refused by name where the call's count is known, as it was before.
    if (defined $fn->{minargs} && !grep { _is_list($_) } @args) {
        out('a call of a signature with too few arguments (perl dies)') if @args < $fn->{minargs};
        out('an odd count into a signature\'s slurpy hash (perl dies)') if ( $fn->{slurpy_sigil} // '' ) eq '%' && ( @args - $fn->{minargs} ) % 2;
    }
    if ($fn->{list}) {
        # @_ BUILT HERE: each scalar pushed, an array's elements appended.
        my $arr = $b->emit(op => 'NewArray', type => '%Array*');
        for my $a (@args) {
            if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
            else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
        }
        $b->hash_reads_settled('a call');
        $b->set_want($c) if $fn->{listret};
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => [$arr], attr => { fn => $fn->{name} }, site => $c);
    }
    out('a call of a sub with a signature of another arity (perl dies)')
        if $fn->{signature} && @args != $fn->{nargs};
    my @pass = map { $b->scalar_arg($_) } @args;
    $b->hash_reads_settled('a call');   # the sub may store into a hash
    push @pass, $b->emit(op => 'Undef', type => '%Slot') while @pass < $fn->{nargs};
    splice @pass, $fn->{nargs};
    $b->set_want($c) if $fn->{listret};
    return $b->emit_call(op => 'Call', type => '%Slot', inputs => \@pass, attr => { fn => $fn->{name} }, site => $c);
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
    # A TIE'S METHODS are the runtime's to call, by these names.
    $called{$_} = 1 for grep { my $t = $_; grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'tie' } _all_nodes($mop, $b->{ret}) } qw(TIEARRAY TIEHASH FETCH STORE FETCHSIZE PUSH POP SHIFT UNSHIFT EXISTS DELETE CLEAR EXTEND STORESIZE FIRSTKEY NEXTKEY);
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
        $b->emit(op => 'MopIsa', type => 'void', inputs => [ $cs, $b->const_str($cls->parent_name) ])
            if defined $cls->parent_name && length $cls->parent_name;
        my %sub = map { ( $_->name => $_ ) } grep { ( $called{can} || $called{ $_->name } ) && $_->graph } ( $cls->subs, $cls->methods );
        for my $sub (@sub{ sort keys %sub }) {
            my $fn = $b->func($sub, $cls->name . '::' . $sub->name);
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
    # ITS CLASSES, the root first (:isa): each class's fields, then its
    # ADJUST blocks, in that order, as perl initializes them.
    my @chain;
    for (my $k = $leaf; $k; $k = defined $k->parent_name && length $k->parent_name ? $b->{mop}->for_class( $k->parent_name ) // out('an :isa of a class not here') : undef) {
        out('an :isa of a package not of the class feature') unless _is_feature_class($k);
        out('an :isa cycle') if @chain > 64;
        unshift @chain, $k;
    }
    my @in = $c->inputs->@*;
    pop @in if $c->can('memory_input') && $c->memory_input;
    my @names = +($c->can('param_names') ? $c->param_names // [] : [])->@*;
    out('a new whose arguments are not name => value') if @names != @in || grep { _is_list($_) } @in;
    my %arg = map { ( $names[$_] => $in[$_] ) } 0 .. $#in;
    my %param = map { ( $_->param_name => 1 ) } grep { defined $_->param_name } map { $_->fields } @chain;
    out("a new with a parameter its class has not ($_)") for grep { !$param{$_} } @names;
    my $obj = $b->emit(op => 'HNew', type => '%Slot');
    $obj = $b->emit(op => 'Bless', type => '%Slot', inputs => [ $obj, $b->const_str( $leaf->name ) ]);
    for my $cls (@chain) {
        my @byix;   # in field order (no sort block: its $b is the builder here)
        $byix[ $_->fieldix ] = $_ for $cls->fields;
        for my $f (grep { defined } @byix) {
            my $key = $b->const_str( $cls->name . '::' . $f->name );
            if ($f->sigil eq '@') {
                out('an array field with a default') if $f->has_default;
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $b->emit(op => 'ARef', type => '%Slot', inputs => [ $b->emit(op => 'NewArray', type => '%Array*') ]) ]);
                next;
            }
            if ($f->sigil eq '%') {
                out('a hash field with a default') if $f->has_default;
                $b->emit(op => 'HSet', type => 'void', inputs => [ $obj, $key, $b->emit(op => 'HNew', type => '%Slot') ]);
                next;
            }
            out('a ' . $f->sigil . ' field') unless $f->sigil eq '$';
            my $v;
            if (defined $f->param_name && exists $arg{ $f->param_name }) { $v = $b->as($b->value( $arg{ $f->param_name } ), '%Slot') }
            elsif ($f->has_default) {
                my $d = $f->default_value;
                out('a field default that is not a constant') unless blessed($d) && $d->operation eq 'Constant';
                $v = $b->as($b->value($d), '%Slot');
            }
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
    pop @args if $c->can('memory_input') && $c->memory_input;
    out('a method call with no invocant') unless @args && blessed($args[0]);
    out('a method call on a list') if _is_list($args[0]);
    # @_, each argument pushed, a list's elements appended.
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    my $inv = $b->as($b->value($args[0]), '%Slot');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $inv ]);
    for my $a (@args[ 1 .. $#args ]) {
        if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
    }
    $b->hash_reads_settled('a method call');
    $b->set_want($c);   # whichever sub it finds may return a list
    # (where perl dies -- no class, no method -- a die, an eval's to catch)
    my $at = ' at ' . ( $c->can('file') ? $c->file // '-' : '-' ) . ' line ' . ( $c->can('line') ? $c->line // 0 : 0 ) . ".\n";
    # A QUALIFIED NAME starts its lookup at its package (mode 1); Pkg::SUPER::m
    # at the @ISA of Pkg, the package the call is in (mode 2).
    my ($start, $mode, $m) = ( '', 0, $c->name );
    if ($m =~ /\A(.+)::SUPER::(\w+)\z/) { ( $start, $mode, $m ) = ( $1, 2, $2 ) }
    elsif ($m =~ /\A(.+)::(\w+)\z/)     { ( $start, $mode, $m ) = ( $1, 1, $2 ) }
    out('a method name T2 cannot split') if $m =~ /::|'/;
    my $fp = $b->emit(op => 'MResolve', type => 'i8*', attr => { mode => $mode },
        inputs => [ $inv, $b->const_str($m), $b->const_str($at), $b->const_str($start) ]);
    return $b->emit_call(op => 'MCall', type => '%Slot', inputs => [ $fp, $arr ], site => $c);
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
    if (( $n->dispatch_kind // '' ) eq 'direct' && ( $n->name // '' ) !~ /__ANON__/) {
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
    if ($b->{tail} && $b->{tail}{call} == refaddr($c)) {   # handed on from this sub's caller
        return $b->emit(op => 'SetWant', type => 'void', inputs => [ $b->{tail}{want} ]);
    }
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
    my $fn = $b->func($sub, $a->name // 'anon', closure => 1);
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

# code_call($Call, $code, @args) -> calling a code value: @_ built (lists
# flattened), its function found (a stop if it is no code), called with its
# cells, in the call's context.
sub code_call {
    my ($b, $c, $code, @args) = @_;
    # `&$code;` IS CALLED WITH THE CALLER'S OWN @_: not built here -- refused.
    out('an & call of a code value sharing @_') if $c->can('shares_args') && $c->shares_args;
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    for my $a (@args) {
        if (_is_list($a)) { $b->emit(op => 'AAppend', type => 'void', inputs => [ $arr, $b->array_of($a) ]) }
        else { $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $b->as($b->value($a), '%Slot') ]) }
    }
    $b->hash_reads_settled('a call of a code value');
    $b->set_want($c);
    return $b->emit_call(op => 'CallCode', type => '%Slot', inputs => [ $code, $arr ], site => $c);
}

# REGEXES ARE GRAPHS. regex_result($match) -> the %Slot its matcher returns
# ([start, end, g1s, g1e, ...] or undef), made once where the match is.
sub regex_result {
    my ($b, $m) = @_;
    my $k = 'rx' . refaddr($m);
    return $b->{memo}{$k} if $b->{memo}{$k};
    my @code = $b->code_bodies($m);
    # A MATCH WHOSE BLOCKS RUN STORES what they store: every read of an earlier
    # version is made before it (a read between two such matches saw the second).
    if (@code) { $b->hash_reads_settled('a match whose code blocks run'); $b->reads_before($_) for $b->{passed}->@* }
    my $subj = $b->as( $b->value( $m->inputs->[0] ), '%Slot' );
    my ( $pat, $flags ) = ( $m->can('pattern') ? $m->pattern : undef, $m->flags // '' );
    my $rlits;
    if ( $m->operation eq 'Match' ) {
        my $re = $m->inputs->[1];
        # INTERPOLATED: constants B::SoN folded, and \Q$x\E literals (arguments).
        if ( my ( $cp, $lits ) = _pattern_parts($re) ) { ( $pat, $rlits ) = ( $cp, $lits ) }
        else {
        # AGAINST A qr VALUE made elsewhere: its matcher, called (a string
        # there is a pattern built at run time: a stop where it is matched).
        unless ( blessed($re) && $re->operation eq 'Constant' && ( $re->const_type // '' ) eq 'regex' ) {
            # (a string by what makes it -- not by its stamp: B::SoN stamps a
            # qr value Str where it is also joined to one -- a pattern built at run time)
            out('a match against a pattern built at run time') if $re isa Chalk::IR::Node && $re->makes_a_string;
            out('a match against a qr value with flags of its own (' . $flags . ')') if $flags =~ /[^u]/;
            return $b->{memo}{$k} = $b->emit_call(op => 'QrMatch', type => '%Slot', inputs => [ $b->as( $b->value($re), '%Slot' ), $subj ]);
        }
        ( $pat, $flags ) = ( $re->value // '', join '', ( $re->can('flags') ? $re->flags // '' : '' ), $flags );
        }
    }
    my @lit = map { $b->as( $b->value($_), '%Slot' ) } +($rlits // [])->@*;
    my %ro = @lit ? ( rlits => scalar @lit ) : ();
    $ro{codes} = scalar @code if @code;
    # m//g IN SCALAR CONTEXT, AND \G: from the subject's pos(), which a /g
    # match then moves (a failed one resets it, unless /c).
    if ( $flags =~ /g/ || ( $pat // '' ) =~ /\\G/ ) {
        my ( $pc, $zc ) = $b->pos_cells( $m->inputs->[0] );
        my $fn = $b->regex_fn( $pat // '', $flags, 'gscalar', %ro );
        my $r = $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $subj, $b->emit(op => 'Load', type => '%Slot', inputs => [$pc]), $b->emit(op => 'Load', type => '%Slot', inputs => [$zc]), @lit ], attr => { fn => $fn->{name} });
        $b->emit(op => 'PosUpdate', type => 'void', inputs => [ $r, $pc, $zc ], attr => { keep => $flags =~ /c/ ? 1 : 0 }) if $flags =~ /g/;
        return $b->{memo}{$k} = $r;
    }
    my $fn = $b->regex_fn( $pat // '', $flags, 'scalar', %ro );
    return $b->{memo}{$k} = $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $subj, @lit, @code ], attr => { fn => $fn->{name} });
}

# code_bodies($match) -> a code value of each `(?{ ... })` body B::SoN lifted
# (in pattern order): arguments of the match's graph, which calls them.
sub code_bodies {
    my ($b, $m) = @_;
    my @names = $m->can('code_bodies') && $m->code_bodies ? $m->code_bodies->@* : ();
    return map {
        my $g = $Chalk::IR::Serialize::JSON::CODE_GRAPHS{$_} // out('a regex code block whose body B::SoN did not give');
        my $sub = $b->{rxcode}{$_} //= Chalk::MOP::Sub->new( name => $_, class => undef, graph => $g, params => ['@_'], uses_args => 1 );
        $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $b->func( $sub, 'rxcode_' . scalar keys $b->{rxcode}->%* )->{name} });
    } @names;
}

# pos_cells($pad) -> the two cells of a variable's pos(): where its next m//g
# starts (undef: none) and where its last /g match was empty (perl's /g does
# not match empty there again). Made at the function's entry, undef.
sub pos_cells {
    my ($b, $pad) = @_;
    out('a pos() of what is not a `my` scalar kept here')
        unless blessed($pad) && $pad->operation eq 'PadAccess' && ( $pad->sigil // '$' ) eq '$' && $pad->is_location;
    my $key = 'pos#' . $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return ( $b->{locs}{$key} //= [ map {
        my $p = Chalk::Target::LLVM::Node::_n(op => 'Alloca', type => '%Slot*', attr => { name => "pos(" . $pad->name . ")$_" });
        unshift $b->{blocks}[0]{nodes}->@*, $p;
        $p
    } 1, 2 ] )->@*;
}

# pos_reset($pad): a variable written has no pos() (perl's), if it keeps one.
sub pos_reset {
    my ($b, $pad) = @_;
    return unless blessed($pad) && $pad->operation eq 'PadAccess';
    my $name = $pad->name;
    return unless grep {
        my $x = $_->operation =~ /\A(?:RegexMatch|Match)\z/ && ( ( $_->flags // '' ) =~ /g/ || ( $_->can('pattern') ? $_->pattern // '' : '' ) =~ /\\G/ ) ? $_->inputs->[0]
              : $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'pos' ? $_->inputs->[0] : undef;
        blessed($x) && $x->operation eq 'PadAccess' && ( $x->name // '' ) eq $name
    } +($b->{own_nodes} // [])->@*;
    $b->emit(op => 'Store', type => 'void', inputs => [ $b->emit(op => 'Undef', type => '%Slot'), $_ ]) for $b->pos_cells($pad);
}

# regex_list($match) -> an array ref of what the match gives in list context.
sub regex_list {
    my ($b, $m) = @_;
    my $k = 'rxl' . refaddr($m);
    return $b->{memo}{$k} if $b->{memo}{$k};
    out('a regex match with code blocks') if $m->can('code_bodies') && $m->code_bodies && $m->code_bodies->@*;
    my ( $pat, $flags ) = ( $m->can('pattern') ? $m->pattern : undef, $m->flags // '' );
    my $rlits;
    if ( $m->operation eq 'Match' ) {
        my $re = $m->inputs->[1];
        if ( my ( $cp, $lits ) = _pattern_parts($re) ) { ( $pat, $rlits ) = ( $cp, $lits ) }
        else {
            out('a match in list context against a qr value made elsewhere')
                unless blessed($re) && $re->operation eq 'Constant' && ( $re->const_type // '' ) eq 'regex';
            ( $pat, $flags ) = ( $re->value // '', join '', ( $re->can('flags') ? $re->flags // '' : '' ), $flags );
        }
    }
    my @lit = map { $b->as( $b->value($_), '%Slot' ) } +($rlits // [])->@*;
    my $fn = $b->regex_fn( $pat // '', $flags, $flags =~ /g/ ? 'all' : 'list', @lit ? ( rlits => scalar @lit ) : () );
    my $subj = $b->as( $b->value( $m->inputs->[0] ), '%Slot' );
    return $b->{memo}{$k} = $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $subj, @lit ], attr => { fn => $fn->{name} });
}

# regex_split($Call) -> an array ref of split's fields: its pattern's graph
# (the split flavor) given the subject and the limit. A pattern built at run
# time has no graph: refused.
sub regex_split {
    my ($b, $c) = @_;
    my $k = 'rxp' . refaddr($c);
    return $b->{memo}{$k} if $b->{memo}{$k};
    my ( $pat, $subj, $limit ) = grep { blessed($_) && !$_->is_memory_version } $c->inputs->@*;
    out('a split of no subject') unless blessed($subj);
    my $fn;
    if ( blessed($pat) && $pat->operation eq 'Constant' && ( $pat->const_type // '' ) eq 'string' && ( $pat->value // '' ) eq ' ' ) {
        $fn = $b->regex_fn( ' ', '', 'split', awk => 1 );
    }
    my @lit;
    if ( blessed($pat) && $pat->operation eq 'Constant' && ( $pat->const_type // '' ) eq 'regex' ) {
        $fn = $b->regex_fn( $pat->value // '', ( $pat->can('flags') ? $pat->flags // '' : '' ), 'split' );
    }
    elsif ( !$fn && ( my ( $cp, $lits ) = _pattern_parts($pat) ) ) {
        @lit = map { $b->as( $b->value($_), '%Slot' ) } @$lits;
        $fn = $b->regex_fn( $cp, '', 'split', @lit ? ( rlits => scalar @lit ) : () );
    }
    out('a split by a pattern built at run time') unless $fn;
    my @args = ( $b->as( $b->value($subj), '%Slot' ), blessed($limit) ? $b->as( $b->value($limit), '%Slot' ) : $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }), '%Slot' ), @lit );
    return $b->{memo}{$k} = $b->emit_call(op => 'Call', type => '%Slot', inputs => \@args, attr => { fn => $fn->{name} });
}

# regex_subst($RegexSubst) -> the %Slot its graph (the subst flavor) gives:
# [the new string, how many it replaced], made once where it stands.
sub regex_subst {
    my ($b, $s) = @_;
    my $k = 'rxs' . refaddr($s);
    return $b->{memo}{$k} if $b->{memo}{$k};
    out('an s/// with code blocks') if $s->can('code_bodies') && $s->code_bodies && $s->code_bodies->@*;
    out('an s/// with an empty pattern (the last pattern that matched)') if ( $s->pattern // '' ) eq '' && !$s->pattern_is_input;
    # s///ge: ITS BODY CALLED PER MATCH by the subst graph (percall), which
    # stores the match's $& $1.. where the body's captures read them.
    if ( $s->can('replacement_body') && defined( my $body = $s->replacement_body ) ) {
        my $g = $Chalk::IR::Serialize::JSON::CODE_GRAPHS{$body} // out('an s///e replacement whose body B::SoN did not give');
        out('an s///e replacement holding an s///e (its matches would overwrite the captures it reads)')
            if grep { $_->operation eq 'RegexSubst' && $_->can('replacement_body') && defined $_->replacement_body }
               $g->component;
        my $sub = $b->{rxcode}{$body} //= Chalk::MOP::Sub->new( name => $body, class => undef, graph => $g, params => ['@_'], uses_args => 1 );
        my $code = $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $b->func( $sub, 'rxrepl_' . scalar keys $b->{rxcode}->%* )->{name} });
        ( my $flags = $s->flags // '' ) =~ s/[er]//g;
        my $subj = $b->as( $b->value( $s->inputs->[0] ), '%Slot' );
        $b->reads_before($_) for $b->{passed}->@*;   # (the body may read and store what reads here read)
        return $b->{memo}{$k} = $b->subst_call( $s, $flags, { percall => 1 }, $subj, $code );
    }
    # A COMPUTED REPLACEMENT is an input between the subject (and a pattern
    # input) and the memory version: B::SoN makes it in the arm of a match of
    # its own -- ONCE.
    my @in = grep { blessed($_) } $s->inputs->@[ ( $s->pattern_is_input ? 2 : 1 ) .. $s->inputs->$#* ];
    my $repl = @in && !$in[0]->is_memory_version ? $in[0] : undef;
    my $flags = $s->flags // '';
    out('an s///g whose replacement is made per match (B::SoN computes it once)') if $repl && $flags =~ /g/;
    $flags =~ s/[er]//g;
    my @args = ( $b->as( $b->value( $s->inputs->[0] ), '%Slot' ) );
    push @args, $b->as( $b->value($repl), '%Slot' ) if $repl;
    return $b->{memo}{$k} = $b->subst_call( $s, $flags, $repl ? { computed => 1 } : { replacement => $s->replacement // '' }, @args );
}

# subst_call($RegexSubst, $flags, \%opts, @args) -> what its subst graph gives.
# AN INTERPOLATED PATTERN (input 1) that is one of a few constant strings (a
# choice of them, concatenated: File::Temp's `X(?=X*$end)`) has a matcher for
# each, the one it is picked at run time; any other is not T2's.
sub subst_call {
    my ($b, $s, $flags, $ro, @args) = @_;
    unless ( $s->pattern_is_input ) {
        my $fn = $b->regex_fn( $s->pattern, $flags, 'subst', %$ro );
        return $b->emit_call(op => 'Call', type => '%Slot', inputs => \@args, attr => { fn => $fn->{name} });
    }
    my $pn   = $s->inputs->[1];
    my @pats = $pn isa Chalk::IR::Node ? $pn->const_choices : ();
    out('an s/// whose pattern is made at run time of what is not a few constants') unless @pats && @pats <= 8;
    my @code = map { $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $b->regex_fn( $_, $flags, 'subst', %$ro )->{name} }) } @pats;
    my $p    = $b->as( $b->value($pn), '%Str' );
    my $code = $code[-1];   # (the pattern is one of them: the choices are all it can be)
    for my $i ( reverse 0 .. $#pats - 1 ) {
        my $cmp = $b->emit(op => 'StrCmp', type => 'i64', inputs => [ $p, $b->as( $b->const_str( $pats[$i] ), '%Str' ) ]);
        my $eq  = $b->emit(op => 'Cmp', type => 'i1', inputs => [ $cmp, $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ], attr => { op => 'eq' });
        $code = $b->emit(op => 'Select', type => '%Slot', inputs => [ $eq, $code[$i], $code ]);
    }
    my $arr = $b->emit(op => 'NewArray', type => '%Array*');
    $b->emit(op => 'APush', type => 'void', inputs => [ $arr, $_ ]) for @args;
    return $b->emit_call(op => 'CallCode', type => '%Slot', inputs => [ $code, $arr ]);
}

# translit($Transliterate) -> the %Slot tr's graph gives: [the new string,
# how many characters it matched], made once where it stands.
sub translit {
    my ($b, $t) = @_;
    my $k = 'rxt' . refaddr($t);
    return $b->{memo}{$k} if $b->{memo}{$k};
    my $key = join "\0", 'tr', $t->from // '', $t->to // '', $t->flags // '';
    my $sub = $b->{rxsub}{$key} //= do {
        my $w = eval { Chalk::Regex::Graph::translit( $t->from // '', $t->to // '', ( $t->flags // '' ) =~ s/r//gr ) };
        out( 'a tr: ' . ( $@ =~ s/\A(?:GAP: )?//r =~ s/\n.*//sr ) ) unless $w;
        Chalk::MOP::Sub->new( name => 'tr', class => undef, graph => Chalk::IR::Serialize::JSON::_deserialize_graph($w), params => ['@_'], uses_args => 1 );
    };
    my $fn = $b->func( $sub, 'tr_' . scalar keys $b->{rxsub}->%* );
    return $b->{memo}{$k} = $b->emit_call(op => 'Call', type => '%Slot', inputs => [ $b->as( $b->value( $t->inputs->[0] ), '%Slot' ) ], attr => { fn => $fn->{name} });
}

# regex_subst_part($RegexSubst, $i) -> element i of what it gives (0 the new string)
sub regex_subst_part {
    my ($b, $s, $i) = @_;
    my $arr = $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $s->operation eq 'Transliterate' ? $b->translit($s) : $b->regex_subst($s) ]);
    return $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->emit(op => 'Const', type => 'i64', attr => { value => $i }) ]);
}

# regex_subst_count($RegexSubst) -> what s/// gives in place: how many it
# replaced, or "" (perl's false) for none.
sub regex_subst_count {
    my ($b, $s) = @_;
    my $n = $b->regex_subst_part( $s, 1 );
    return $n if $s->operation eq 'Transliterate';   # (tr's count is a number: 0 too)
    my $none = $b->emit(op => 'Cmp', type => 'i1', inputs => [ $b->as( $n, 'i64' ), $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ], attr => { op => 'eq' });
    return $b->emit(op => 'Select', type => '%Slot', inputs => [ $none, $b->as( $b->const_str(''), '%Slot' ), $n ]);
}

# substr_write($Call): substr($s, o, l, R) where it stands -- $s a `my` scalar
# kept here: its new string stored; the call's value the part it replaced.
sub substr_write {
    my ($b, $s) = @_;
    my @a = grep { blessed($_) } $s->inputs->@*;
    pop @a if $s->can('memory_input') && $s->memory_input;
    out('a substr statement of other than four arguments') unless @a == 4;
    my $pad = $a[0];
    out('a four-argument substr of what is not a `my` scalar kept here')
        unless $pad->operation eq 'PadAccess' && ( $pad->sigil // '' ) eq '$' && $pad->is_location;
    my $old = $b->as( $b->value($pad), '%Str' );
    my $off = $b->as( $b->value( $a[1] ), 'i64' );
    my $len = $b->as( $b->value( $a[2] ), 'i64' );
    my $rep = $b->as( $b->value( $a[3] ), '%Str' );
    my $part = $b->emit(op => 'Substr', type => '%Slot', inputs => [ $old, $off, $len, $b->emit(op => 'Const', type => 'i1', attr => { value => 1 }) ]);
    my $new = $b->emit(op => 'SubstrRep', type => '%Slot', inputs => [ $old, $off, $len, $rep ]);
    $b->reads_before( $pad->inputs->[0] );
    $b->emit(op => 'Store', type => 'void', inputs => [ $new, $b->location($pad) ]);
    $b->pos_reset($pad);
    $b->{memo}{ refaddr($s) } = $part;
}

# regex_subst_stmt($RegexSubst): an s/// where it stands -- in place (not /r):
# its new string stored into its subject, a `my` scalar kept here.
sub regex_subst_stmt {
    my ($b, $s) = @_;
    my $subj = $s->inputs->[0];
    my $new = $b->regex_subst_part( $s, 0 );
    return unless $s->is_in_place;   # (its value is the new string: what reads it reads)
    out('an s/// or tr in place of what is not a `my` scalar kept here')
        unless $subj->operation eq 'PadAccess' && ( $subj->sigil // '' ) eq '$' && $subj->is_location;
    my $ptr = $b->location($subj);
    $b->reads_before( $subj->inputs->[0] );
    $b->emit(op => 'Store', type => 'void', inputs => [ $new, $ptr ]);
    $b->pos_reset($subj);
}

# qr_value($Constant) -> a qr// value: an object of class Regexp holding perl's
# string of it (`pattern`) and its matcher, the pattern's graph, as a code
# value (`matcher`) -- a match against the value calls it (QrMatch).
sub qr_value {
    my ($b, $c) = @_;
    my $flags = $c->can('flags') ? $c->flags // '' : '';
    my $fn = $b->regex_fn( $c->value // '', $flags );
    my %f = map { ( $_ => 1 ) } split //, $flags;
    my $str = '(?^' . ( $f{u} ? 'u' : '' ) . join( '', grep { $f{$_} } qw(m s i x) ) . ':' . ( $c->value // '' ) . ')';
    my $h = $b->emit(op => 'HNew', type => '%Slot');
    $b->emit(op => 'HSet', type => 'void', inputs => [ $h, $b->const_str('pattern'), $b->as( $b->const_str($str), '%Slot' ) ]);
    $b->emit(op => 'HSet', type => 'void', inputs => [ $h, $b->const_str('matcher'), $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $fn->{name} }) ]);
    return $b->emit(op => 'Bless', type => '%Slot', inputs => [ $h, $b->const_str('Regexp') ]);
}

# regex_fn($pattern, $flags) -> the function its graph (Chalk::Regex::Graph) is,
# one per pattern and flags.
sub regex_fn {
    my ($b, $pat, $flags, $flavor, %o) = @_;
    $flavor //= 'scalar';
    my $key = join "\0", $flavor, $flags, $pat, map { ( $_, $o{$_} ) } sort keys %o;
    return $b->func( $b->{rxsub}{$key}, 'regex' ) if $b->{rxsub}{$key};
    my $w = eval { Chalk::Regex::Graph::matcher( $pat, $flags, $flavor, %o ) };
    out( 'a regex: ' . ( $@ =~ s/\A(?:GAP: )?//r =~ s/\n.*//sr ) ) unless $w;
    my $sub = $b->{rxsub}{$key} = Chalk::MOP::Sub->new(
        name => 'regex', class => undef, graph => Chalk::IR::Serialize::JSON::_deserialize_graph($w),
        params => ['@_'], uses_args => 1 );
    return $b->func( $sub, 'regex_' . scalar keys $b->{rxsub}->%* );
}

# regex_capture($RegexCapture) -> $N of the match it names: undef where its
# group took no part. Read only where that match is known to have succeeded
# (an if's or ?:'s arm on it): elsewhere perl reads the last match that did.
sub regex_capture {
    my ($b, $c) = @_;
    my $m = $c->inputs->[0];
    out('a capture of no regex match') unless blessed($m) && $m->operation =~ /\A(?:RegexMatch|Match)\z/;
    # IN AN s///e BODY (its match has no subject: the one that called it): the
    # match's $& $1.. as the subst graph stored them, undef where none took part.
    if ( $m->operation eq 'RegexMatch' && !grep { blessed($_) } $m->inputs->@* ) {
        my $caps = $b->emit(op => 'GArray', type => '%Array*', attr => { global => $b->global_named('pkgarr::T2::SubstCaps') });
        return $b->as( $b->emit(op => 'AGet', type => '%Slot', inputs => [ $caps, $b->emit(op => 'Const', type => 'i64', attr => { value => $c->n }) ]), $b->type_of($c) );
    }
    out('a capture read where its match may have failed (perl reads the last match that succeeded)')
        unless ( $b->{rx_ok} // {} )->{ refaddr($m) };
    my $n = $c->n;
    out('a capture of no group of its pattern') if $n < 1;
    my $arr = $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->regex_result($m) ]);
    my ( $s, $e ) = map { $b->as( $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->emit(op => 'Const', type => 'i64', attr => { value => 2 * $n + $_ }) ]), 'i64' ) } 0, 1;
    my $str = $b->as( $b->value( $m->inputs->[0] ), '%Str' );
    my $len = $b->emit(op => 'Arith', type => 'i64', inputs => [ $e, $s ], attr => { op => 'sub' });
    my $sub = $b->emit(op => 'Substr', type => '%Slot', inputs => [ $str, $s, $len, $b->emit(op => 'Const', type => 'i1', attr => { value => 1 }) ]);
    my $none = $b->emit(op => 'Cmp', type => 'i1', inputs => [ $s, $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }) ], attr => { op => 'lt' });
    return $b->as( $b->emit(op => 'Select', type => '%Slot', inputs => [ $none, $b->emit(op => 'Undef', type => '%Slot'), $sub ]), $b->type_of($c) );
}

# _pattern_parts($node) -> (pattern, [nodes]): an interpolated pattern of
# constants (B::SoN folded them) and \Q$x\E pieces -- each a literal known at
# run time, a placeholder in the pattern (Chalk::Regex::Parse::$RLIT + k) and
# an argument of its graph. () when it is anything else.
sub _pattern_parts {
    my ($n) = @_;
    my @lits;
    my $walk;
    $walk = sub ($x) {
        return undef unless blessed($x);
        my $op = $x->operation;
        return $x->value // '' if $op eq 'Constant' && ( $x->const_type // '' ) =~ /\A(?:string|integer)\z/;
        return $walk->( $x->inputs->[0] ) if $op eq 'Coerce';
        if ( $op eq 'Concat' ) {
            my @p = map { $walk->($_) } grep { blessed($_) } $x->inputs->@*;
            return undef if grep { !defined } @p;
            return join '', @p;
        }
        if ( $op eq 'Call' && ( $x->dispatch_kind // '' ) eq 'builtin' && ( $x->name // '' ) eq 'quotemeta' ) {
            my ($arg) = grep { blessed($_) } $x->inputs->@*;
            my $c = $arg isa Chalk::IR::Node ? $arg->const_pattern : undef;
            return quotemeta $c if defined $c;    # (known here: quoted here)
            return undef if @lits >= 32;
            push @lits, $arg;
            return chr( $Chalk::Regex::Parse::RLIT + $#lits );
        }
        return undef;
    };
    my $pat = $walk->($n);
    return defined $pat ? ( $pat, \@lits ) : ();
}

# _rx_arm(\%ok, $cond, $arm) -> the matches known to have succeeded in arm
# $arm (0 the true one) of a branch on $cond: a match, or not a match.
sub _rx_arm {
    my ($ok, $cond, $arm) = @_;
    my %ok = +($ok // {})->%*;
    if ( blessed($cond) && $cond->operation =~ /\A(?:RegexMatch|Match)\z/ ) { $ok{ refaddr($cond) } = 1 if $arm == 0 }
    elsif ( blessed($cond) && $cond->operation eq 'Not' && blessed( $cond->inputs->[0] ) && $cond->inputs->[0]->operation =~ /\A(?:RegexMatch|Match)\z/ ) {
        $ok{ refaddr( $cond->inputs->[0] ) } = 1 if $arm == 1;
    }
    return \%ok;
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
    # A LIST RETURN: B::SoN's Return(list, scalar) -- the list, and what the
    # sub gives in scalar context (its last, a count, undef). The caller's
    # context (@t2_want, set before the call) picks one.
    my $valueless = $ret->can('valueless') && $ret->valueless;   # `()`, a bare return
    # `return values %h` (keys too): one input, B::SoN's, in the caller's
    # context -- the list, or its count. A list return as well.
    my $hkv = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && ( $ret->inputs->[0]->dispatch_kind // '' ) eq 'builtin' && ( $ret->inputs->[0]->name // '' ) =~ /\A(?:keys|values)\z/
        && ( $ret->inputs->[0]->can('want') ? $ret->inputs->[0]->want // '' : '' ) ne 'scalar'   # `scalar(keys %h)`: a count always
        ? $ret->inputs->[0] : undef;
    my $listret = $ret->inputs->@* == 2 || $valueless || $hkv;
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
        out("method $name has a slurpy parameter")
            if grep { $_->operation eq 'Parameter' && ( $_->can('sigil') ? $_->sigil // '$' : '$' ) ne '$' } @gn
            or grep { ( ref($_) ? $_->{name} // $_->{sigil} // '' : $_ // '' ) =~ /\A[@%]/ } +($sub->can('params') ? $sub->params // [] : [])->@*;
        $margs{ refaddr($_) } = 0 for grep { $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq 'self' } @gn;
        $margs{ refaddr($_) } = $_->index + 1 for grep { $_->operation eq 'Parameter' } @gn;
        $margs{np} = $np;
    }
    my $an = bless {}, 'Chalk::Target::LLVM::Context';
    my @reads = $is_method ? () : eval { $an->_collect_positional_arg_reads($g, $name) };
    # @_ READ AS A LIST (join(@_), "@_", scalar(@_), for (@_)): the sub takes
    # @_ as one %Array its caller builds -- the list convention. A write to
    # $_[N] (the caller's variable) or a signature is not T2's.
    # A CLOSURE takes @_ as one array always (its code value's calling
    # convention), its captured cells as its environment.
    my $list = !$is_method && !$@ && ( $an->{_args_read_as_a_list} || $closure ) && !$an->{_args_written} && !$an->{_args_slurpy} && !$an->{_args_signature};
    # A SLURPY TAIL (`my ($c, @x) = @_`, `sub f ($c, @x)` -- perigrin: the same)
    # takes @_ as one array: the positional targets its elements 0..k-1, the
    # slurpy one a copy of the rest.
    my $slurpy = !$is_method && !$@ && !$closure && !$an->{_args_written} && !$an->{_args_read_as_a_list} ? $an->{_args_slurpy} : undef;
    my @positional = $slurpy ? @reads : ();
    $list = 1 if $slurpy;
    out("closure $name reads \@_ other than T2 takes it") if $closure && !$list;
    # A CAPTURE USED BUT BY A CELL READ OR WRITE: B::SoN spells `$t += 1` on
    # one as Coerce(CellParam) + 1, with no write -- lowered, $t never changed
    # (0 for 16). Refused, as Context.pm refuses it.
    out("closure $name uses a capture other than by reading or writing it (an op-assign)")
        if grep { my $p = $_; grep { blessed($_) && $_->operation !~ /\A(?:CellRead|CellWrite|MakeCell)\z/ } ( $p->consumers // [] )->@* }
           grep { $_->operation eq 'CellParam' } $g->component;
    out("sub $name captures a variable (a named sub's closure)") if !$closure
        && grep { $_->operation eq 'CellParam' } $g->component;
    # $_[N] READ ANYWHERE is the Nth argument: Context.pm's binder keeps one
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
    if ($sig && !$is_method) {
        my $decl = $sub->can('signature') ? $sub->signature // {} : {};
        out("sub $name has an optional signature parameter")
            if $decl->{optional} || ( $decl->{mandatory} // scalar @reads ) != ( $slurpy ? @positional : @reads );
    }
    ( my $id = $name ) =~ s/\W+/_/g;
    # Two subs one name (a method call's bare name): the second numbered.
    $id .= '_' . scalar keys $b->{funcs}->%* if grep { $_->{name} eq "\@f_$id" } values +($b->{funcs} // {})->%*;
    my $nargs = $is_method ? 1 + $margs{np} : $list ? 1 : scalar @reads;
    my $fn = $b->{funcs}{ refaddr($sub) } = { name => "\@f_$id", wrapper => "\@w_$id", nargs => $nargs,
        signature => $sig, list => $list, listret => $listret, closure => $closure, blocks => [] , minargs => ( $slurpy && $sig ? scalar @positional : undef ),
        slurpy_sigil => ( $slurpy && $sig ? ( $slurpy->can('sigil') ? $slurpy->sigil // '@' : '@' ) : undef ) };
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
    local $b->{memo} = {};
    local $b->{args} = $is_method ? { map { ( $_ => $argn[ $margs{$_} ] ) } grep { $_ ne 'np' } keys %margs }
                                  : { ( map { ( refaddr( $reads[$_] ) => $argn[$_] ) } 0 .. $#reads ), ( map { ( refaddr( $_->[0] ) => $argn[ $_->[1] ] ) } @also ) };
    local $b->{self} = $is_method ? $argn[0] : undef;   # a field's object
    local $b->{env} = $closure ? do { my $e = Chalk::Target::LLVM::Node::_n(op => 'Arg', type => '%Slot**', attr => { index => 1 }); $e->set_name('%env'); $e } : undef;
    local $b->{own_nodes} = [ $g->component ];
    local $b->{eval_at} = { map { ( refaddr( $_->eval_entry ) => $_ ) } grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } $b->{own_nodes}->@* };
    local $b->{evals} = [];
    local $b->{eval_opened} = {};
    local $b->{in_func} = 1;
    local $b->{ret} = $ret;
    local $b->{passed} = [ grep { $_->operation eq 'MemStart' } $g->component ];
    local $b->{readers};
    $b->index_readers($g->component);
    local $b->{depth} = 0;
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj)\z/ ? $start->inputs->[0]
               : out("no way back to Start in $name");
    }
    $b->new_block('entry');
    # THE CALLER'S CONTEXT, read first (a call in the body sets it).
    my $want = $b->emit(op => 'GetWant', type => 'i1');
    if ($slurpy) {
        # A SIGNATURE'S ARITY: at least its positional parameters (perl dies
        # with fewer -- a run-time stop here, as a signature's wrapper's is).
        $b->emit(op => 'ArgsMin', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional }) if $sig;
        $b->emit(op => 'ArgsPairs', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional })
            if $sig && ( $slurpy->can('sigil') ? $slurpy->sigil // '' : '' ) eq '%';
        # ITS PARAMETERS, made here: each its argument, the slurpy one the rest.
        for my $p (grep { $_->operation eq 'Parameter' } $g->component) {
            my $sg = $p->can('sigil') ? $p->sigil // '$' : '$';
            $b->{memo}{ refaddr($p) } = $sg eq '$'
                ? $b->emit(op => 'AGet', type => '%Slot', inputs => [ $argsarr, $b->emit(op => 'Const', type => 'i64', attr => { value => $p->index }) ])
                : $b->args_rest($argsarr, $p->index, $sg);
        }
    }
    # `return g()` IS CALLED IN THE CALLER'S CONTEXT: it is handed on.
    my $tail = $ret->inputs->@* == 1 && blessed( $ret->inputs->[0] ) && $ret->inputs->[0]->operation eq 'Call'
        && ( $ret->inputs->[0]->dispatch_kind // '' ) eq 'direct' ? $ret->inputs->[0] : undef;
    local $b->{tail} = $tail ? { call => refaddr($tail), want => $want } : undef;
    $b->make_constant_arrays($g->component);
    local $b->{jumps} = {};   # this function's early exits
    $b->walk($start);
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
    if ($hkv) {
        my $h = $b->hash_of( $hkv->inputs->[0] );
        my $l = $b->emit(op => $hkv->name eq 'keys' ? 'HKeys' : 'HValues', type => '%Array*', inputs => [$h]);
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
        $b->emit(op => 'AAppend', type => 'void', inputs => [ $copy, $b->as_list($v) ]);
        my $l = $b->emit(op => 'ARef', type => '%Slot', inputs => [$copy]);
        my $sv = blessed( $ret->inputs->[1] ) ? $b->as($b->value( $ret->inputs->[1] ), '%Slot') : $b->emit(op => 'Undef', type => '%Slot');
        $r = $b->emit(op => 'Select', type => '%Slot', inputs => [ $want, $l, $sv ]);
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

# phi_type($Phi) -> a merge's T2 type: its stamp's, except a Str (a Num may
# reach it) or a stamp T1 could not give (a recursive sub's result) -- boxed.
sub phi_type {
    my ($b, $phi) = @_;
    my $st = $phi->stamp // ''; # static type
    # THE LIST A SUB RETURNS, merged from its returns (`return` in one arm, a
    # last value in the other): an array, each arm's value a list of it.
    return '%Array*' if grep { blessed($_) && $_->operation eq 'Return' && $_->inputs->@* == 2 && refaddr( $_->inputs->[0] ) == refaddr($phi) }
        ( $phi->consumers // [] )->@*;
    return '%Slot' if $st =~ /\A(?:Str|Unknown|None|Scalar)\z/ || $st =~ /\AMaybe\[/;   # a Maybe: T or undef
    # A LIST A LOOP BUILDS (map, grep): one array, its back edge a ListAppend
    # to it. Another array phi (`@p = ()` in a loop) is not this.
    if ($st =~ /\A(?:Array|List)\z/) {
        out("a phi stamped $st") unless grep { blessed($_) && $_->operation eq 'ListAppend' } $phi->inputs->@*;
        return '%Array*';
    }
    return $SCALAR{$st} // out("a phi stamped $st");
}

# loop($Loop) -> the control node the program continues from: a header of
# phis (each its initial value, then the body's) and the condition, a body
# walked forward back to the header, and an exit.
sub loop {
    my ($b, $L) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } $L->successors_by_input;
    my ($bodyp, $exitp) = @proj{0, 1};
    return $b->loop_breaks($L) if !$bodyp && !$exitp && $b->loop_exit($L);
    out('a loop without a body and an exit') unless $bodyp && $exitp;
    local $b->{loopx};   # (its body's ifs are its own: an outer loop's edges are not here)
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($L)
                      && !$_->is_memory } ( $L->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @cond = grep { $_->operation !~ /\A(?:Phi|Proj)\z/ } $L->successors;
    out('a loop condition that is not one value') unless @cond == 1;
    out('a loop phi with other than two ways in') if grep { scalar( $_->inputs->@* ) != 2 } @phis;

    $b->reads_before($_) for $b->{passed}->@*;   # see if_stmt
    my $pre = $b->{cur};
    # A LIST THE LOOP BUILDS starts empty each time the loop is entered: a
    # fresh array here (the empty literal, made once at entry, was every
    # pass's of an outer loop: "xa c ya c a c" for "xa c ya c").
    my @init = map {
        my $i0 = $_->inputs->[0];
        $b->loop_type($_) eq '%Array*' && blessed($i0) && $i0->operation eq 'ArrayLiteral' && !$i0->inputs->@*
            ? $b->emit(op => 'NewArray', type => '%Array*')
            : $b->as($b->value($i0), $b->loop_type($_))
    } @phis;
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
    my @mphis = $L->memory_phis;
    $b->reads_before($_) for @mphis;
    push $b->{passed}->@*, @mphis;
    my $cond = $b->truth($b->value($cond[0]));
    my $head_end = $b->{cur};
    my $body = $b->new_block('body');
    my @back;
    {
        # A value made in the body is the body's: not seen after the loop.
        local $b->{memo} = { $b->{memo}->%* };
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $cond[0], 0 );   # (a body runs where its condition held)
        $b->walk($bodyp);
        @back = map { $b->as($b->value($phis[$_]->inputs->[1]), $t2[$_]->type) } 0 .. $#phis;
    }
    my $body_end = $b->{cur};
    out('a loop body that dies at its end') if $body_end->{dead};
    $body_end->{term} = [ 'br', $head ];
    for my $i (0 .. $#t2) {
        push $t2[$i]->inputs->@*, $back[$i];
        push $t2[$i]->attr->{from}->@*, $body_end;
    }
    my $exit = $b->new_block('exit');
    $head_end->{term} = [ 'condbr', $cond, $body, $exit ];
    my ($region) = grep { $_->operation eq 'Region' } ( $exitp->consumers // [] )->@*;
    # THE EXIT'S MEMORY is a version too: a read at it, before a store after.
    push $b->{passed}->@*, $region->memory_phis if $region;
    return $region // $exitp;
}

# loop_breaks($Loop) -> the control the program goes on from: A LOOP THAT
# LEAVES OR GOES ROUND FROM ITS BODY (B::SoN's `while (1) { ... next if C;
# ... last }`, a bare block's `redo`): no test at its head. Its body is walked
# from the Loop; an arm reaching the Loop's exit Region leaves (a way into
# the exit, merged after), one reaching its latch -- a control with no way on,
# or a Region of such -- goes round (the latch merged, its values the head
# phis' back edges).
sub loop_breaks {
    my ($b, $L) = @_;
    my $R = $b->loop_exit($L);
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($L)
                      && !$_->is_memory } ( $L->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    out('a loop phi with other than two ways in') if grep { scalar( $_->inputs->@* ) != 2 } @phis;
    $b->reads_before($_) for $b->{passed}->@*;
    my @init = map {
        my $i0 = $_->inputs->[0];
        $b->loop_type($_) eq '%Array*' && blessed($i0) && $i0->operation eq 'ArrayLiteral' && !$i0->inputs->@*
            ? $b->emit(op => 'NewArray', type => '%Array*')
            : $b->as($b->value($i0), $b->loop_type($_))
    } @phis;
    my $pre_end = $b->{cur};
    my $head = $b->new_block('loop');
    $pre_end->{term} = [ 'br', $head ];
    my @t2 = map {
        my $p = $b->emit(op => 'Phi', type => $b->loop_type($phis[$_]), inputs => [ $init[$_] ], attr => { from => [$pre_end] });
        $b->{memo}{ refaddr( $phis[$_] ) } = $p;
    } 0 .. $#phis;
    my @mphis = $L->memory_phis;
    $b->reads_before($_) for @mphis;
    push $b->{passed}->@*, @mphis;
    my $lx = { exit => $R, exits => [], latches => [] };
    my $outer_memo = $b->{memo};
    my $head_memo;
    {
        local $b->{memo}  = { $b->{memo}->%* };
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        local $b->{loopx} = $lx;
        $head_memo = { $b->{memo}->%* };
        my $e = $b->walk($L);
        $b->loop_edge( $lx, $e, { block => $b->{cur}, memo => $b->{memo} } )
            || out('a loop body that ends neither going round nor leaving') if defined $e;
    }
    # THE LATCH: the ways round merged (one: that arm itself); its values are
    # the head phis' back edges.
    my @lat = grep { !$_->{block}{dead} } $lx->{latches}->@*;
    out('a loop that never goes round') unless @lat;
    # A WAY ROUND THROUGH A REGION THAT FEEDS THE LATCH (a `redo` in a nested
    # arm): that Region merged first, its merge one way into the next.
    while (1) {
        my %by = map { ( refaddr($_->{region}) => $_->{region} ) } grep { $_->{region} } @lat;
        my ($inner) = grep { my $r = $_; my @o = $r->out_regions; @o == 1 } values %by;
        last unless $inner;
        my ($outer) = $inner->out_regions;
        my @in = grep { $_->{region} && refaddr($_->{region}) == refaddr($inner) } @lat;
        my ( $blk, $memo ) = $b->merge_at( $inner, 'round', $head_memo, @in );
        @lat = ( ( grep { !( $_->{region} && refaddr($_->{region}) == refaddr($inner) ) } @lat ),
                 { block => $blk, memo => $memo, end => $inner, region => $outer } );
    }
    my %lr = map { ( ( $_->{region} ? refaddr( $_->{region} ) : 0 ) => $_->{region} ) } @lat;
    out('a loop whose ways round do not meet at one latch') if keys %lr > 1;
    my ($latch) = values %lr;
    my ( $lblk, $lmemo ) = blessed($latch) ? $b->merge_at( $latch, 'latch', $head_memo, @lat ) : ( $lat[0]{block}, $lat[0]{memo} );
    my @back;
    {
        local $b->{cur}  = $lblk;
        local $b->{memo} = $lmemo;
        @back = map { $b->as($b->value($phis[$_]->inputs->[1]), $t2[$_]->type) } 0 .. $#phis;
        $lblk = $b->{cur};
    }
    $lblk->{term} = [ 'br', $head ];
    for my $i (0 .. $#t2) {
        push $t2[$i]->inputs->@*, $back[$i];
        push $t2[$i]->attr->{from}->@*, $lblk;
    }
    # THE EXIT: the ways out merged, with the exit Region's phis.
    my @out = grep { !$_->{block}{dead} } $lx->{exits}->@*;
    out('a loop that never leaves') unless @out;
    ( $b->{cur}, $b->{memo} ) = $b->merge_at( $R, 'exit', $outer_memo, @out );
    push $b->{passed}->@*, $R->memory_phis;
    return $R;
}

# loop_exit($Loop) -> the Region the program goes on from after it: of the
# Regions B::SoN heads with it (its exit, and the merge of its ways round,
# which has no way on), the one with a way on.
sub loop_exit {
    my ($b, $L) = @_;
    my @r = grep { $_->operation eq 'Region' && blessed( $_->head ) && refaddr( $_->head ) == refaddr($L) && $_->goes_on }
        +($b->{own_nodes} // [])->@*;
    out('a loop with more than one exit') if @r > 1;
    return $r[0];
}

# loop_jump($end, $arm) -> true (and recorded as a jump, see if_stmt) when an
# arm in a loop body ends at a merge out past the loop (`return 0 unless ...`
# reaching the sub's last merge): the walk after the loop joins it there.
sub loop_jump {
    my ($b, $e, $arm) = @_;
    return 0 unless blessed($e) && !$e->successors;
    my @r = grep { $_->operation eq 'Region' } ( $e->consumers // [] )->@*;
    return 0 unless @r == 1 && $r[0]->goes_on;
    push $b->{jumps}{ refaddr( $r[0] ) }->@*, { %$arm, end => $e };
    return 1;
}

# loop_edge($lx, $end, $arm) -> true (and recorded) when control $end leaves
# the loop $lx is walking (it feeds its exit Region) or goes round (it has no
# way on, or feeds only a Region that has none: the latch).
sub loop_edge {
    my ($b, $lx, $e, $arm) = @_;
    return 0 unless blessed($e);
    my @r = grep { $_->operation eq 'Region' } ( $e->consumers // [] )->@*;
    if ( @r == 1 && refaddr( $r[0] ) == refaddr( $lx->{exit} ) ) { push $lx->{exits}->@*, { %$arm, end => $e }; return 1 }
    return 0 if $e->successors;
    if ( !@r ) { push $lx->{latches}->@*, { %$arm, end => $e }; return 1 }
    if ( @r == 1 && !$r[0]->goes_on ) { push $lx->{latches}->@*, { %$arm, end => $e, region => $r[0] }; return 1 }
    return 0;
}

# merge_at($Region, $name, $base, @arms) -> (block, memo): a block the arms (each
# {block, memo, end}, end a way into the Region) go on to, the Region's phis
# made there from each arm's value -- and the memo after it.
sub merge_at {
    my ($b, $r, $name, $base, @preds) = @_;   # $base: the memo where every arm began
    my @ways = grep { blessed($_) } $r->inputs->@*;
    my @pred_of = map { my $in = $_; ( grep { refaddr( $preds[$_]{end} ) == refaddr($in) } 0 .. $#preds )[0] } @ways;
    my @live = grep { defined $pred_of[$_] } 0 .. $#ways;   # (a way from an arm that died is no way in)
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($r)
                      && !$_->is_memory } ( $r->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @made;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        my @in;
        for my $k (@live) {
            my $pr = $preds[ $pred_of[$k] ];
            local $b->{cur}  = $pr->{block};
            local $b->{memo} = $pr->{memo};
            push @in, [ $ty eq '%Array*' ? $b->as_list( $p->inputs->[$k] ) : $b->as($b->value($p->inputs->[$k]), $ty), $pr ];
            $pr->{block} = $b->{cur};
        }
        push @made, [ $p, $ty, \@in ];
    }
    my $join = $b->new_block($name);
    $_->{block}{term} = [ 'br', $join ] for @preds;
    local $b->{cur} = $join;
    my %memo = %$base;
    for my $m (@made) {
        my ( $p, $ty, $in ) = @$m;
        $memo{ refaddr($p) } = $b->emit(op => 'Phi', type => $ty, inputs => [ map { $_->[0] } @$in ], attr => { from => [ map { $_->[1]{block} } @$in ] });
    }
    return ( $join, \%memo );
}

# A LOOP PHI'S TYPE: its stamp, except a Str one, which a Num may reach on a
# later pass -- boxed, as a merge of differing arms is.
sub loop_type { my ($b, $phi) = @_; return $b->phi_type($phi) }

# The T2 type a T1 value is, decided once.
sub type_of {
    my ($b, $v) = @_;
    my $op = $v->operation;
    return '%Slot' if $op eq 'EnvRead' || $op eq 'DefinedOr' || $op eq 'RegexCapture';   # may be undef (a capture: its group took no part)
    return '%Slot' if ( $v->stamp // '' ) eq 'Regex';   # a qr value: an object of class Regexp
    return '%Array*' if $op =~ /\A(?:RegexMatch|Match)\z/ && _is_list($v);   # a match in list context: its list
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'split') {
        # IN SCALAR CONTEXT split gives its count of fields (not T2's yet)
        out('a split in scalar context') if grep { blessed($_) && $_->operation eq 'Assign' && !( $_->can('targets') && defined $_->targets )
            && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->can('sigil') ? $_->inputs->[0]->sigil // '$' : '$' ) eq '$' } ( $v->consumers // [] )->@*;
        return '%Array*';
    }
    # A SUB'S ARGUMENT AND RESULT are whatever its callers pass and it returns:
    # T1 types them per call site (add(2,3) Int, though add(0.5,1) is 1.5),
    # so in T2 each is a %Slot, read by its tag.
    return '%Slot' if $b->{args}{ refaddr($v) };
    # AN ARRAY is an %Array of %Slot, by pointer; a count of it an i64, an
    # element a %Slot (it holds what was stored, by its tag).
    # AN ARRAY REFERENCE is a %Slot (tag 6) over an %Array: a scalar.
    return $v->sigil eq '@' ? '%Array*' : '%Slot' if $v->is_package_aggregate;   # a hash is its %Slot
    return '%Slot' if $op eq 'ArrayLiteral' && ( $v->stamp // '' ) eq 'ArrayRef'; # static type
    return '%Slot' if $op eq 'Ref';
    return '%Slot' if $op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$';
    return '%Array*' if $op eq 'ArrayLiteral' || $v->is_array_deref || $v->is_my_array || $op eq 'ArgsSource' || $op eq 'ListAppend';
    return 'i64' if $op eq 'Count';
    return '%Slot' if $op eq 'Subscript';
    # A HASH REFERENCE is a %Slot (tag 5) over a %Hash: it is a scalar.
    return '%Slot' if $op eq 'HashLiteral' && ( $v->stamp // '' ) =~ /\A(?:HashRef|Hash)\z/; # static type
    return '%Slot' if $v->is_my_hash;
    # length of a scalar: undef for undef, so a %Slot; of a string, an i64.
    return ( ( $v->inputs->[0]->stamp // '' ) !~ /\A(?:Array|ArrayRef)\z/ && $b->type_of($v->inputs->[0]) eq '%Slot' ) ? '%Slot' : 'i64' if $op eq 'Length'; # static type
    my $hk = $v->can('kind') ? $v->kind // '' : '';
    return 'i1' if $op eq 'Exists' && $hk =~ /\A(?:hash|array)\z/;
    return '%Slot' if $op eq 'Delete' && $hk eq 'hash';
    return ( $v->stamp // '' ) eq 'Scalar' ? '%Slot' : '%Array*'   # static type
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'caller';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'substr';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/;
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:ftdir|chdir|reftype_of_ref)\z/;
    return 'i64' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'require';
    return 'i64'   if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'index';
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        return $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar' ? 'i64' : '%Array*';
    }
    return '%Array*' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:sort|reverse)\z/
        && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/;   # static type
    return '%Slot' if $op eq 'Call' && ( $v->name // '' ) =~ /\A(?:shift|pop)\z/;
    return '%Str' if $op eq 'Call' && $v->changes_case;
    return '%Str' if $op eq 'Call' && ( $v->name // '' ) eq 'join';
    return '%Array*' if $v->is_argv;
    return '%Slot' if $v->is_package_scalar;   # what it holds is what was stored last, anywhere
    return '%Slot*' if $op eq 'MakeCell' || $op eq 'CellParam';   # a captured variable's storage
    return '%Slot' if $op eq 'CellRead' || $op eq 'AnonSub';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'indirect';
    if ($op eq 'FieldAccess') {
        my (undef, $sg) = $b->field_of($v);
        return $sg eq '@' ? '%Array*' : '%Slot';   # a scalar's value, or a hash's (its %Slot)
    }
    return '%Str' if $op eq 'EntryDef';
    return '%Slot' if $op eq 'PadAccess' && $v->is_location;
    return '%Slot' if $op eq 'Increment' || $op eq 'Decrement';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) =~ /\A(?:direct|method)\z/;
    # AN OBJECT is its blessed reference; ref() of one its class, or HASH.
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless' || $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'blessed';
    return '%Slot' if $op eq 'Call' && $v->is_tie_builtin;
    return '%Str' if $op eq 'RefType';
    return 'i64' if $op eq 'Print';
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
    return '%Slot' if $st =~ /\AMaybe\[/;   # T or undef: a %Slot
    return $SCALAR{$st} // out("a value stamped $st ($op)");
}

# value($t1) -> the T2 node for a T1 value, built once.
sub value {
    my ($b, $v) = @_;
    out('a value an eval made, read past its end')
        if delete $b->{past_eval}{ refaddr($v) } and $v->operation ne 'Constant';
    return $b->{memo}{ refaddr($v) } //= $b->_value($v);
}

sub _value {
    my ($b, $v) = @_;
    # $& $` $' $+ @- @+ %+: of the last match that succeeded -- B::SoN gives
    # them as package variables, of no match: never read as one.
    out( 'the match variable ' . ( $v->sigil // '$' ) . $v->symbol . ' (B::SoN ties it to no match)' )
        if $v->operation eq 'EntryDef' && ( $v->symbol // '' ) =~ /\A(?:[&`'+-]|\d+)\z/;
    return $b->pkg_agg($v) if $v->is_package_aggregate;
    # $] IS THE VERSION OF THE PERL T2 IS: the one compiling (whose semantics it
    # keeps), read-only.
    return $b->as( $b->const_str("$]"), $b->type_of($v) )   # (its text: "5.042000")
        if blessed($v) && $v->operation eq 'EntryDef' && ( $v->sigil // '' ) eq '$' && ( $v->symbol // '' ) eq ']' && ( ( $v->can('package') ? $v->package : undef ) // 'main' ) eq 'main';
    # THE LITERAL A PACKAGE AGGREGATE WAS STORED FROM is how B::SoN gives a
    # later read of the name: read as the aggregate, which a push or another
    # sub may have changed since (a copy of the literal printed "1 2" for "1 2 3").
    if (my $t = $v->stored_whole_into) { return $b->pkg_agg($t) }
    # A qr// VALUE (a regex constant read as a value): an object of class Regexp.
    return $b->qr_value($v) if $v->operation eq 'Constant' && ( $v->const_type // '' ) eq 'regex';
    # A PRINT THAT RAN AS A STATEMENT (in an arm of && or ||) read as a value
    # after the join: perl's print returns 1, and the merge reads it only on
    # the path where it ran.
    return $b->emit(op => 'Const', type => 'i64', attr => { value => 1 })
        if $v->operation eq 'Print' && $v->can('control_in') && blessed($v->control_in);
    # AN ARGUMENT READ (a shift, $_[N], a signature parameter) is the argument.
    if (my $arg = $b->{args}{ refaddr($v) }) { return $arg }
    # (a read after the Assign takes it as input; a target read is its input)
    if ($b->{argsarr} && $v->operation eq 'PadAccess'
        && ( my ($as) = ( ( grep { blessed($_) && $_->is_args_list_assign } $v->inputs->@* ),
                          ( grep { blessed($_) && $_->is_args_list_assign && grep { blessed($_) && refaddr($_) == refaddr($v) } $_->inputs->@[ 0 .. $_->inputs->$#* - 1 ] } ( $v->consumers // [] )->@* ) ) )) {
        out('a read of `my (...) = @_` in a sub that shifts @_') if $b->{args_mutated};
        return $b->args_elem($as, $v);
    }
    my $op = $v->operation;
    my $ty = $b->type_of($v);
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'direct') { return $b->call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'method') { return $b->method_call($v) }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'indirect') {
        my ($code, @args) = $v->inputs->@*;
        pop @args if $v->can('memory_input') && $v->memory_input;
        return $b->code_call($v, $b->as($b->value($code), '%Slot'), @args);
    }
    if ($op eq 'MakeCell') {
        # THE CELL IS THE VARIABLE'S OWN STORAGE (the maker reads and writes it
        # as the closure does). A variable a loop renews, captured in it, is a
        # new one each pass: not this (one storage per call).
        my $var = Chalk::Target::LLVM::Context::_cell_variable($v) // out('a captured variable that is not one kept in memory');
        out('a variable captured in a loop body or an arm') if $b->{depth};
        return $b->location($var);
    }
    if ($op eq 'CellParam') {
        my $env = $b->{env} // out('a captured variable outside a closure');
        my $ix = $b->emit(op => 'Const', type => 'i64', attr => { value => $v->index });
        return $b->emit(op => 'EnvGet', type => '%Slot*', inputs => [ $env, $ix ]);
    }
    if ($op eq 'CellRead') {
        return $b->emit(op => 'Load', type => '%Slot', inputs => [ $b->value( $v->inputs->[0] ) ]);
    }
    if ($op eq 'AnonSub') { return $b->code_value($v) }
    # A push B::SoN left off the chain, a body's last statement (an ADJUST's):
    # made where its value is wanted -- its Return, the only use allowed.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'push' && !$v->is_pinned) {
        out('a push off the chain used other than by a return')
            if grep { blessed($_) && $_->operation ne 'Return' } ( $v->consumers // [] )->@*;
        $b->array_stmt($v);
        return $b->{memo}{ refaddr($v) };
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'bless') {
        my @in = $v->inputs->@*;
        pop @in if $v->can('memory_input') && $v->memory_input;
        # ONE ARGUMENT blesses into the package the bless is in: not known here.
        out('a bless of one argument') unless @in == 2;
        return $b->emit(op => 'Bless', type => '%Slot',
            inputs => [ $b->as($b->value($in[0]), '%Slot'), $b->as($b->value($in[1]), '%Str') ]);
    }
    # blessed($x): the class a reference was blessed into, else undef.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'blessed') {
        my @in = grep { blessed($_) } $v->inputs->@*;
        pop @in if $v->can('memory_input') && $v->memory_input;
        out('a blessed of other than one argument') unless @in == 1;
        return $b->emit(op => 'ClassOf', type => '%Slot', inputs => [ $b->as($b->value($in[0]), '%Slot') ]);
    }
    # $$r: what the variable r refers to holds; perl's die where r is no SCALAR
    # reference (a string under strict refs; undef too), its eval's to catch.
    # A FOREACH ALIAS READ (B::SoN's ${ \ $_[i] }, a guard of its existence
    # around it): the deref of a reference to an element is that element.
    if ( $op eq 'PostfixDeref' && ( my $el = $v->alias_element ) ) {
        my $arr = do { local $b->{elem_read} = 1; $b->array_of( $el->inputs->[0] ) };
        return $b->as( $b->emit(op => 'AGet', type => '%Slot', inputs => [ $arr, $b->as( $b->value( $el->inputs->[1] ), 'i64' ) ]), $ty );
    }
    if ($op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$') {
        my $at = $b->deref_at($v);
        my $r = $b->emit(op => 'SDeref', type => '%Slot', inputs => [ $b->as($b->value($v->inputs->[0]), '%Slot') ],
            attr => { strict => ( $v->can('strict') && $v->strict ? 1 : 0 ), %$at });
        $b->after_call;
        return $b->as($r, $ty);
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
    if ($op eq 'FieldAccess') {
        my ($key, $sg) = $b->field_of($v);
        my $self = $b->{self} // out('a field outside a method');
        out('a field read of no one version') if $b->{unversioned}{ refaddr($v) };
        my $slot = $b->emit(op => 'HGet', type => '%Slot', inputs => [ $self, $b->const_str($key) ]);
        return $sg eq '@' ? $b->emit(op => 'ADeref', type => '%Array*', inputs => [$slot]) : $slot;
    }
    if ($v->is_package_scalar) {
        out('a package scalar read of no one version') if $b->{unversioned}{ refaddr($v) };
        return $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->global_of($v) });
    }
    if ($op eq 'Call' && $v->changes_case) {
        # ASCII CASE: past ASCII perl's case is a character's (refused there).
        $b->{past_ascii} //= scalar grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'string' && ( $_->value // '' ) =~ /[^\x00-\x7f]/ }
            _all_nodes($b->{mop}, $b->{ret});
        out('a case change where a string goes past ASCII') if $b->{past_ascii};
        my @a = grep { blessed($_) } $v->inputs->@*;
        pop @a if $v->can('memory_input') && $v->memory_input;
        out('a case change of other than one argument') unless @a == 1;
        my %mode = (uc => 0, lc => 1, ucfirst => 2, lcfirst => 3);
        my $m = $b->emit(op => 'Const', type => 'i64', attr => { value => $mode{ $v->name } });
        return $b->emit(op => 'StrCase', type => '%Str', inputs => [ $b->as($b->value($a[0]), '%Str'), $m ]);
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
        $b->{strs}{$c} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
    }
    # -d PATH: a directory (1), something else there (''), nothing (undef).
    # chdir PATH: 1, or '' where it could not. A require of a file B::SoN
    # followed is done -- its subs are compiled in (1); of any other, not T2's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:ftdir|chdir|require)\z/) {
        my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out( 'a ' . $v->name . ' of no argument' ) unless @a;
        if ( $v->name eq 'require' ) {
            my $f = $a[0];
            out('a require of a file named at run time') unless $f->operation eq 'Constant' && defined $f->value;
            ( my $mod = $f->value ) =~ s{\.pm\z}{}; $mod =~ s{/}{::}g;
            out( 'a require of ' . $f->value . ', not compiled in' )
                unless $Chalk::IR::Serialize::JSON::FOLLOWED{ $f->value } || $Chalk::IR::Serialize::JSON::FOLLOWED{$mod};
            return $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), $ty );
        }
        return $b->as( $b->emit(op => $v->name eq 'ftdir' ? 'FtDir' : 'Chdir', type => '%Slot', inputs => [ $b->as( $b->value( $a[0] ), '%Str' ) ]), $ty );
    }
    # int(X): X's number truncated toward zero. rand(X): a number in [0, X),
    # X 1 when absent or 0 (perl's), from libc's generator -- not perl's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/) {
        my @a = grep { blessed($_) && !$_->is_memory_version } $v->inputs->@*;
        out('an int of no argument (of $_)') if $v->name eq 'int' && !@a;
        my $x = @a ? $b->as( $b->value( $a[0] ), '%Slot' ) : $b->emit(op => 'Undef', type => '%Slot');
        return $b->as( $b->emit(op => $v->name eq 'int' ? 'IntOf' : 'Rand', type => '%Slot', inputs => [$x]), $ty );
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
        $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
        my $q = $b->emit(op => 'Div', type => 'double',
            inputs => [ map { $b->as($b->value($_), 'double') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        $b->after_call;   # (a zero divisor is a die: an eval's to catch)
        return $b->as($q, $ty);
    }
    if ($op eq 'Modulo') {
        # PERL'S % IS OF INTEGERS, its sign the right side's, and dies on zero.
        out('a % not typed Int') unless $ty eq 'i64';
        my $msg = "Illegal modulus zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys $b->{strs}->%*;
        my $r = $b->emit(op => 'Mod', type => 'i64',
            inputs => [ map { $b->as($b->value($_), 'i64') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        $b->after_call;   # (a zero modulus is a die: an eval's to catch)
        return $r;
    }
    # `ref \$x` (B::SoN's reftype_of_ref): what kind of thing $x holds.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'reftype_of_ref') {
        return $b->as( $b->emit(op => 'KindOfRef', type => '%Slot', inputs => [ $b->as( $b->value( $v->inputs->[0] ), '%Slot' ) ]), $ty );
    }
    # -x: perl's, on the value it has at run time (t2_slot_neg).
    if ($op eq 'Negate') {
        return $b->as( $b->emit(op => 'SlotNeg', type => '%Slot', inputs => [ $b->as( $b->value( $v->inputs->[0] ), '%Slot' ) ]), $ty );
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
    # <=>: -1, 0 or 1, as (x > y) - (x < y).
    # shortcut: a NaN operand gives 0, perl's undef; return a %Slot if a NaN program needs it.
    if ($op eq 'NumCmp') {
        my @in = map { $b->value($_) } $v->inputs->@[0, 1];
        my $t = ( grep { $_->type ne 'i64' } @in ) ? 'double' : 'i64';
        my ($gt, $lt) = map { my $c = $_; $b->as($b->emit(op => 'Cmp', type => 'i1', inputs => [ map { $b->as($_, $t) } @in ], attr => { op => $c }), 'i64') } qw(gt lt);
        return $b->as($b->emit(op => 'Arith', type => 'i64', inputs => [ $gt, $lt ], attr => { op => 'sub' }), $ty);
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
        $b->{strs}{$k} //= scalar keys $b->{strs}->%*;
        return $b->emit(op => 'Env', type => '%Slot', attr => { key => $k, id => $b->{strs}{$k} });
    }
    if ($op eq 'DefinedOr' || $op eq 'TernaryExpr' || $op eq 'And' || $op eq 'Or') {
        # A MERGE: its condition, an arm built in each block, a phi at the join.
        my ($cond, $then, $else);
        if ($op eq 'And' || $op eq 'Or') {
            # (OF A LIST -- `@x && sort ...` in list context -- the value is the
            # list or the left side's count, not one scalar: refused)
            out('an && or || of a list') if grep { _is_list($_) || $b->type_of($_) eq '%Array*' } grep { blessed($_) } $v->inputs->@[0, 1];
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
        { local $b->{memo} = { $b->{memo}->%* };
          local $b->{rx_ok} = $v->operation eq 'TernaryExpr' ? _rx_arm( $b->{rx_ok}, $v->inputs->[0], 0 ) : $b->{rx_ok};
          $tv = $b->as( blessed($then) && $then->isa('Chalk::Target::LLVM::Node') ? $then : $b->value($then), $ty ); }
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        { local $b->{memo} = { $b->{memo}->%* };
          $ev = $b->as( blessed($else) && $else->isa('Chalk::Target::LLVM::Node') ? $else : $b->value($else), $ty ); }
        my $eend = $b->{cur};
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $cond, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => $ty, inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
    # substr($s, $off, $len) READ (not an lvalue: B::SoN pins a store): from
    # either end, the rest or a length (negative leaves that many off the end);
    # undef outside the string, as perl's. index($s, $t, $pos): -1 for none.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:substr|index)\z/) {
        my @a = grep { blessed($_) } $v->inputs->@*;
        pop @a if $v->can('memory_input') && $v->memory_input;
        return $b->{memo}{ refaddr($v) } // out('a four-argument substr read before it is made') if $v->name eq 'substr' && @a == 4;
        out('a ' . $v->name . ' of more than three arguments') if @a > 3;
        my $str = $b->as( $b->value( $a[0] ), '%Str' );
        if ($v->name eq 'substr') {
            out('a substr of fewer than two arguments') if @a < 2;
            my $off = $b->as( $b->value( $a[1] ), 'i64' );
            my ( $len, $has ) = @a > 2
                ? ( $b->as( $b->value( $a[2] ), 'i64' ), $b->emit(op => 'Const', type => 'i1', attr => { value => 1 }) )
                : ( $b->emit(op => 'Const', type => 'i64', attr => { value => 0 }), $b->emit(op => 'Const', type => 'i1', attr => { value => 0 }) );
            return $b->emit(op => 'Substr', type => '%Slot', inputs => [ $str, $off, $len, $has ]);
        }
        out('an index of fewer than two arguments') if @a < 2;
        my $pos = @a > 2 ? $b->as( $b->value( $a[2] ), 'i64' ) : $b->emit(op => 'Const', type => 'i64', attr => { value => 0 });
        return $b->emit(op => 'Index', type => 'i64', inputs => [ $str, $b->as( $b->value( $a[1] ), '%Str' ), $pos ]);
    }
    # A REGEX MATCH OF A CONSTANT PATTERN is a call of its own graph
    # (Chalk::Regex::Graph): [start, end, groups...] or undef; it is true when
    # that is defined. A capture reads the offsets of the match it names.
    if ($op eq 'RegexSubst' || $op eq 'Transliterate') {
        # IN PLACE (pinned, of a `my` scalar): how many it replaced. Else --
        # /r, floating, or of a value B::SoN folded a copy into -- the new string.
        return $b->as( $v->is_in_place ? $b->regex_subst_count($v) : $b->regex_subst_part( $v, 0 ), $ty );
    }
    return $b->as( $b->regex_subst_count( $v->inputs->[0] ), $ty ) if $op eq 'RegexSubstCount' || $op eq 'TransliterateCount';
    # pos($s): its cell (undef where no m//g left it)
    return $b->as( $b->emit(op => 'Load', type => '%Slot', inputs => [ ( $b->pos_cells( $v->inputs->[0] ) )[0] ]), $ty )
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'pos';
    return $b->array_of($v) if ( $op eq 'RegexMatch' || $op eq 'Match' ) && _is_list($v);
    return $b->as($b->emit(op => 'Defined', type => 'i1', inputs => [ $b->regex_result($v) ]), $ty) if $op eq 'RegexMatch' || $op eq 'Match';
    return $b->regex_capture($v) if $op eq 'RegexCapture';
    # A REGEX MATCH, literal or a qr value: no engine in T2 yet (the fallback has one).
    out('a regex match: T2 has no regex engine yet') if $op =~ /\A(?:RegexMatch|Match|RegexSubst|Subst|QrConst|Split)\z/;
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
    out("a conversion " . $n->type . " -> $ty") unless exists $Chalk::Target::LLVM::Printer::CONVERT{ $n->type . '>' . $ty };
    return $b->emit(op => 'Convert', type => $ty, inputs => [$n], attr => { from => $n->type });
}

1;
