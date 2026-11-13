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
# $PATH: which path the last lower_program took -- { path => 't2' }, or
# { path => 'fallback', why => T2's reason } -- read by whoever lowered (the
# pipeline puts it on its unit), so a corpus can count T2's share.
our $PATH;
sub lower_program {
    my ($class, $ret, %opt) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {}, mop => $opt{mop} }, 'Chalk::Target::LLVM::T2::Builder';
    # AN EVAL OR A TRY anywhere in the program (the whole program: a sub's own
    # nodes do not show its caller's try)
    $b->{has_eval} = scalar grep { $_->can('eval_id') && defined $_->eval_id || $_->operation eq 'TryCatch' }
        Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
    # A CALL print TAKES THROUGH A COERCE is in list context (print's list);
    # the Coerce lists no consumer, so it is found from the Print.
    # AN ARRAY OR HASH FIELD is a list wherever a list is asked (B::SoN stamps
    # its FieldAccess Scalar: `join "", @s` joined its count, "1" for "p").
    local %Chalk::Target::LLVM::T2::Builder::LIST_FIELD = map { ( refaddr($_) => 1 ) }
        grep { $_->operation eq 'FieldAccess' && ( ( eval { $b->field_of($_) } )[1] // '$' ) =~ /\A[@%]\z/ }
        Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
    # (want=list too: a Coerce before print is also a scalar's -- `my $n = f();
    # print $n` is the call, coerced, B::SoN having folded $n -- 45 for 2)
    local %Chalk::Target::LLVM::T2::Builder::PRINTED = map { ( refaddr( $_->inputs->[0] ) => 1 ) }
        grep { $_->operation eq 'Coerce' && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'Call'
               && ( $_->inputs->[0]->can('want') ? $_->inputs->[0]->want // '' : '' ) eq 'list' }
        map { grep { blessed($_) } $_->inputs->@* }
        grep { $_->operation eq 'Print' } Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
    # caller ANYWHERE: each call of a sub pushes its site, for caller to read.
    local $Chalk::Target::LLVM::T2::Builder::FRAMES = scalar grep {
        $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'caller'
    } Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
    my $ok = eval {
        # A LIST ASSIGN TO AN ARRAY OR HASH (which takes the rest of the list)
        # is not T2's, ON THE CHAIN OR NOT: one B::SoN left floating was never
        # made, and its array read empty (`my ($f, @rest) = ...`: "1 " for "1 2 3").
        Chalk::Target::LLVM::T2::Builder::out('a list assignment to an array or hash') if grep {
            my $a = $_;
            $a->operation eq 'Assign' && $a->can('targets') && defined $a->targets
                # (`my ($c, @x) = @_` is T2's: the arguments, taken by place)
                && !( blessed( $a->inputs->[-1] ) && $a->inputs->[-1]->operation eq 'ArgsSource' )
                && grep { blessed($_) && ( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) =~ /\A[\@%]\z/
                                           || $_->operation =~ /\A(?:ArrayLiteral|HashLiteral|EntryDef)\z/ && ( $_->can('sigil') ? $_->sigil // '' : '' ) ne '$' ) }
                         @{ $a->inputs }[ 0 .. $a->targets - 1 ]
        } Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
        # A SCALAR DEREF where a reference T2 does not make may reach it (to an
        # element, `\(@a)`, `\$_[0]`): refused, not stopped at run time. T2
        # makes one to a `my` scalar kept in memory, an array's, a hash's.
        Chalk::Target::LLVM::T2::Builder::out('a scalar deref where a reference T2 does not make may reach it')
            if grep( { $_->operation eq 'PostfixDeref' && ( $_->sigil // '' ) eq '$' } Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret) )
            && grep { $_->operation eq 'Ref' && !( ( $_->stamp // '' ) =~ /\A(?:ArrayRef|HashRef)\z/
                          || blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'PadAccess' && ( $_->inputs->[0]->sigil // '' ) eq '$' && $_->inputs->[0]->is_location ) }
                     Chalk::Target::LLVM::T2::Builder::_all_nodes($opt{mop}, $ret);
        $b->build($ret); 1 };
    unless ($ok) { $PATH = { path => 'fallback', why => ( $@ =~ s/\n.*//sr ) }; return undef }
    # A PRINTING FAILURE (a conversion T2 lacks) falls back too: it escaped
    # as a death, a GAP where the fallback had lowered it (pvm 140).
    my $ir = eval { Chalk::Target::LLVM::T2::Printer::print_module($b) };
    $PATH = defined $ir ? { path => 't2' } : { path => 'fallback', why => 'T2 printing: ' . ( $@ =~ s/\n.*//sr ) };
    return $ir;
}

package Chalk::Target::LLVM::T2::Builder;

use Chalk::Regex::Graph;   # a constant regex as its own graph
use Chalk::MOP::Sub;
require Chalk::IR::Serialize::JSON;

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
    $b->{own_nodes} = [ _own_nodes($ret) ];
    $b->{eval_at} = { map { ( refaddr( $_->eval_entry ) => $_ ) } grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } @{ $b->{own_nodes} } };
    $b->{evals} = [];
    $b->{passed} = [ _memstarts($ret, 1) ];
    $b->index_readers(_own_nodes($ret));
    $b->new_block('entry');
    $b->emit(op => 'SaveArgs', type => 'void');   # argv, for @ARGV
    # (a tie calls its class's methods too)
    $b->make_mop if grep { $_->operation eq 'Call' && ( ( $_->dispatch_kind // '' ) eq 'method' || ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'tie' ) } _all_nodes($b->{mop}, $ret);
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
    $b->open_eval($ctl);
    while (1) {
        # A STATEMENT AN EVAL'S BODY FOLLOWS opens it; the body's end closes it
        # at its Region, where the body's end and its catch meet.
        $b->open_eval($ctl);
        if (my $r = $b->eval_region_after($ctl)) { $ctl = $b->close_eval($r); next }
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
        # (WHERE EACH STATEMENT STANDS: its turn and its block -- hash_reads_settled
        # makes a waiting read at the store right after the read's own version)
        $b->{at}{ refaddr($s) } = [ ++$b->{seq}, refaddr( $b->{cur} // 0 ) ];
        # A STATEMENT A READ TAKES AS ITS MEMORY must be a version T2 orders
        # reads by (_is_version): a new store kind missing there let reads after
        # it be made after the next store (three wrong answers, slices 14-15).
        out("a statement $op that versions memory T2 does not order reads by")
            if !_is_version($s) && grep { my $m = blessed($_) ? _memory_input($_) : undef; blessed($m) && refaddr($m) == refaddr($s) } ( $s->consumers // [] )->@*;
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
        elsif ($op eq 'If')   { $ctl = $b->if_stmt($s) }
        # A READ OF A TIED AGGREGATE PINNED where it runs (B::SoN): a FETCH,
        # FETCHSIZE or EXISTS call, made here, in order.
        elsif ($op eq 'RegexSubst' || $op eq 'Transliterate') { $b->regex_subst_stmt($s); push @{ $b->{passed} }, $s; $ctl = $s }
        elsif ($op =~ /\A(?:Subscript|Count|Exists|PostfixDeref|RegexMatch|Match)\z/
               || $op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:keys|values|join|sort|caller|pos)\z/) {
            $b->value($s);
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # A tie OR untie in place: every later access of the container is the new metaobject's.
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:tie|untie|bless)\z/) {
            $b->value($s);
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) =~ /\A(?:push|unshift|shift|pop)\z/) {
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
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # A delete (or an exists) on the chain: made where it stands.
        elsif ($op =~ /\A(?:Delete|Exists)\z/ && ( $s->can('kind') ? $s->kind // '' : '' ) eq 'hash') {
            $b->hash_reads_settled('a delete') if $op eq 'Delete';
            $b->value($s);
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # map's `$_` FOR A CALLEE: its body reads the element itself; only code
        # reading the global $_ needs it -- none in the program, a no-op.
        elsif ($op eq 'LocalAlias' && ( $s->can('name') ? $s->name // '' : '' ) eq '_') {
            out('a $_ aliased where the program reads $_')
                if grep { _pkg_scalar($_) && $_->symbol eq '_' && grep { blessed($_) && $_->operation ne 'EntryWrite' } ( $_->consumers // [] )->@* }
                   _all_nodes($b->{mop}, $b->{ret});
            $ctl = $s;
        }
        # `package X;` names the package code after it is in: nothing T2 reads.
        elsif ($op eq 'PackageMark') { $ctl = $s }
        # A CHOICE PINNED WHERE IT RUNS (B::SoN pins one that reads memory, `$n
        # > 1 ? ... : ...` of a package scalar): its value made here, in order.
        elsif ($op eq 'TernaryExpr') { $b->value($s); push @{ $b->{passed} }, $s; $ctl = $s }
        # A READ OF $@ ON THE CHAIN is made where it stands: a caught die sets
        # $@ with no store in the graph, so only its place orders it.
        # (B::SoN gives two reads of $@ around a caught die one version, and
        # the pipeline makes them one node: what is made from the first stands
        # for both -- the outer eval's message printed the inner's, "in" for
        # "out". Forgetting it would make a value saved from the first, used
        # later, read the second. A $@ read already made is refused here.)
        elsif ($op eq 'EntryDef' && _pkg_scalar($s)) {
            out('a $@ read B::SoN made one node with an earlier one') if $s->symbol eq '@' && $b->{memo}{ refaddr($s) };
            $b->value($s);
            $ctl = $s;
        }
        # A PACKAGE SCALAR WRITTEN: what it held is read first, then stored.
        elsif ($op eq 'EntryWrite' && _pkg_scalar($s->inputs->[0])) {
            out('a local') if $s->can('local') && $s->local;
            my $val = $b->as($b->value($s->inputs->[1]), '%Slot');
            $b->hash_reads_settled('a package store');
            $b->emit(op => 'GStore', type => 'void', inputs => [$val], attr => { global => $b->global_of($s->inputs->[0]) });
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # `local @a` / `local %h` (B::SoN's glob binds): THE SWAP puts a fresh
        # aggregate in the global, the old one's reference saved first for
        # THE RESTORE, which puts that back. A reference taken to the old one
        # keeps its contents; a sub called inside the scope sees the new one.
        elsif ($op eq 'EntryWrite' && $s->binds && _pkg_agg($s->inputs->[0])) {
            my ($t, $v, $mem) = $s->inputs->@*;
            my $h = $t->sigil eq '%';
            $b->hash_reads_settled('a local');
            $b->reads_before($_) for @{ $b->{passed} };
            my $slot;
            if (blessed($v) && $v->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && !$v->inputs->@* && !_pkg_literal_of($v)) {
                # the save: a Ref over a read of this name at this store's memory version
                for my $r ( grep { blessed($_) && $_->operation eq 'Ref' } _all_nodes( $b->{mop}, $b->{ret} ) ) {
                    my $in = $r->inputs->[0];
                    next unless _pkg_agg($in) && _pkg_agg_name($in) eq _pkg_agg_name($t)
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
            push @{ $b->{passed} }, $s;
            $ctl = $s;
        }
        # A PACKAGE ARRAY OR HASH STORED WHOLE (`@a = LIST`): its one aggregate
        # refilled in place -- a reference taken to it sees the new contents.
        elsif ($op eq 'EntryWrite' && _pkg_agg($s->inputs->[0]) && blessed($s->inputs->[1])
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
            $b->reads_before($_) for @{ $b->{passed} };
            $b->emit(op => $h ? 'HAssign' : 'AAssign', type => 'void', inputs => [ $b->pkg_agg($t), $list ]);   # where it stands: a local may have swapped it
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
        # A `my %h = (...)` LIST PINNED where it runs: made by the assign that
        # stores it into its hash, in place.
        elsif ($op eq 'HashLiteral' && ( $s->stamp // '' ) eq 'Hash') { $ctl = $s }
        # A SHIFT OF @_ BOUND TO AN ARGUMENT is on the chain for its order; its
        # value is the argument. A direct call is made where it stands.
        elsif ($op eq 'Call' && ( $b->{args}{ refaddr($s) } || ( $s->dispatch_kind // '' ) =~ /\A(?:direct|method|indirect)\z/ )) {
            $b->value($s);
            push @{ $b->{passed} }, $s;   # B::SoN versions memory at a call
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
    push @{ $b->{evals} }, { region => $r, catch => undef, depth => $b->{depth} // 0, start => $b->{cur}, made_before => { map { ( $_ => 1 ) } keys %{ $b->{memo} } } };
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
    return grep( { blessed($_) && refaddr($_) == refaddr($ctl) } $r->inputs->@* ) ? $r : undef;
}

sub close_eval {
    my ($b, $r) = @_;
    # (popped once the body's value is made: a divide there is the eval's to catch)
    my $f = $b->{evals}[-1];
    out('an eval closed at another depth') if ( $b->{depth} // 0 ) != $f->{depth};
    out('an eval Region of more than one way in') if $r->inputs->@* != 1;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($r)
                      && !Chalk::Target::LLVM::Context::_is_memory_phi($_) } ( $r->consumers // [] )->@*;
    my %seen; @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my $dead = $b->{cur}{dead};
    my @in;
    for my $p (@phis) {
        my $ty = $b->phi_type($p);
        push @in, [ $p, $ty, $dead ? undef : $b->as($b->value( $p->inputs->[0] ), $ty) ];
    }
    pop @{ $b->{evals} };
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
        local $b->{memo} = { %{ $b->{memo} } };
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
    my %first = map { ( refaddr($_) => 1 ) } @{ $f->{start}{nodes} };
    # (dropped here, not at that read: one made first in an arm went with the
    # arm's copy, and the next eval read this one -- "does not dominate")
    for my $k (grep { my $m = $b->{memo}{$_}; !$f->{made_before}{$_} && !( ref $m && $first{ refaddr($m) } ) } keys %{ $b->{memo} }) {
        $b->{past_eval}{$k} = 1;
        delete $b->{memo}{$k};
    }
    $b->{cur} = $join;
    for my $i (0 .. $#in) {
        my ($p, $ty, $nv) = @{ $in[$i] };
        my @vals = ( ( $dead ? () : $nv ), ( $f->{catch} ? $cv[$i] : () ) );
        $b->{memo}{ refaddr($p) } = @vals == 1 ? $vals[0]
            : $b->emit(op => 'Phi', type => $ty, inputs => \@vals, attr => { from => [@from] });
    }
    push @{ $b->{passed} }, $r, _memory_phis($r);   # (its join's memory version: B::SoN's, the $@ a die set)
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
    $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
    my $pk = ( $v->can('package') ? $v->package : undef ) // 'main';
    $b->{strs}{$pk} //= scalar keys %{ $b->{strs} };
    return { msg => $msg, id => $b->{strs}{$msg}, pk => $pk, pkid => $b->{strs}{$pk} };
}

sub hash_reads_settled {
    my ($b, $what) = @_;
    # (ONCE AT A TIME: a read made here may itself settle -- a sort with a
    # comparator, made as a read at a version -- and in again it was the same
    # unmade read, without end: "Deep recursion", then out of memory)
    return if $b->{settling};
    local $b->{settling} = 1;
    for my $ver (@{ $b->{passed} }) {
        my @waiting = grep { $b->_through_ref($_) && !$b->{memo}{ refaddr($_) } } @{ $b->{readers}{ refaddr($ver) } // [] };
        next unless @waiting;
        # MADE HERE WHERE NOTHING RAN BETWEEN: the read's version is the
        # statement just before this one, in this block, and the read is under
        # no ?:, &&, || or // -- so here it reads (or dies) as perl's did there.
        my $at = $b->{at}{ refaddr($ver) }
            // ( $ver->operation eq 'MemStart' ? [ 0, refaddr( $b->{blocks}[0] // 0 ) ] : undef );   # (the function's entry: before its first statement)
        my $next = $at && $at->[0] == $b->{seq} - 1 && $at->[1] == refaddr( $b->{cur} // 0 );
        out("a read through a reference waiting across $what")
            unless $next && !grep { _guarded($_, {}) } @waiting;
        $b->value($_) for @waiting;
    }
    $b->reads_before($_) for @{ $b->{passed} };
}

# _guarded($n) -> true when a value $n flows into a choice (?:, &&, ||, //, a
# phi): made unconditionally, it might be made where perl's is not.
sub _guarded {
    my ($n, $seen) = @_;
    return 0 if $seen->{ refaddr($n) }++;
    for my $c (grep { blessed($_) } @{ $n->consumers // [] }) {
        my $op = $c->operation;
        return 1 if $op =~ /\A(?:TernaryExpr|And|Or|DefinedOr|Phi)\z/;
        next if _is_version($c) || $op =~ /\A(?:Return|Print)\z/;
        return 1 if _guarded($c, $seen);
    }
    return 0;
}

# _through_ref($read) -> true for a read through a reference: a hash element,
# or an array's element, count or copy where the array is a scalar's.
sub _through_ref {
    my ($b, $n) = @_;
    my $op = $n->operation;
    if ($op =~ /\A(?:Subscript|Exists)\z/ && ( $n->can('kind') ? $n->kind // '' : '' ) eq 'hash') {
        return _named_hash($n->inputs->[0]) || $n->inputs->[0]->operation eq 'FieldAccess' ? 0 : 1;   # a `my %h`, a hash field: never a stop
    }
    return 0 unless $op =~ /\A(?:Subscript|Count|PostfixDeref)\z/;
    my $c = $n->inputs->[0];
    $c = $c->inputs->[0] while _aderef($c);
    return 0 unless blessed($c);
    # (a \@a, a [...], @_, a `my @a`, @ARGV: an array it has, never a stop)
    return 0 if $c->operation =~ /\A(?:Ref|ArrayLiteral|ArgsSource)\z/ || _array_var($c) || _argv($c);
    return 1;
}

# _isa_var($n) -> the package whose @ISA $n is, or undef.
sub _isa_var {
    my ($n) = @_;
    return undef unless blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) eq '@' && ( $n->symbol // '' ) eq 'ISA';
    my $pkg = $n->can('package') ? $n->package : undef;
    out('an @ISA of no known package') unless defined $pkg && length $pkg;
    return $pkg;
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
    for my $r ( @{ $s->inputs }[ 0 .. $#{ $s->inputs } - 1 ], grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@* ) {
        $b->{memo}{ refaddr($r) } //= $b->args_elem($s, $r);
    }
    for my $t (grep { blessed($_) && $_->operation eq 'PadAccess' && $_->is_location } @{ $s->inputs }[ 0 .. $#{ $s->inputs } - 1 ]) {
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->{memo}{ refaddr($t) }, $b->location($t) ]);   # (see args_assign)
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
        $b->{lvals}{ $t->symbol } = $a;
        $b->{args_vals}{ refaddr($a) } = 1;
        # A TARGET KEPT IN MEMORY (a closure captures it): the argument stored
        # there too -- read through its cell, it was undef ("0 0" for "10 50").
        $b->emit(op => 'Store', type => 'void', inputs => [ $b->as($a, '%Slot'), $b->location($t) ]) if $t->is_location;
    }
    for my $r (grep { blessed($_) && $_->operation eq 'PadAccess' } ( $s->consumers // [] )->@*) {
        next if $b->{args}{ refaddr($r) };
        next if _is_list_target($r);   # the next list assign's target, versioned by this one
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
        && !grep { $_->operation eq 'AnonSub' } @{ $b->{own_nodes} // [] };
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
        && ( !$pad->shared || grep( { $_->operation eq 'MakeCell' && ( $_->cell_name // '' ) eq $pad->name } @{ $b->{own_nodes} // [] } ) || $b->_own_shared($pad) );
    my $key = $pad->name . '#' . ( $pad->can('targ') ? $pad->targ // '' : '' );
    return $b->{locs}{$key} //= do {
        # A VARIABLE A CLOSURE CAPTURES (shared) lives on the heap -- made at
        # its function's entry, fresh each call -- so a closure outliving the
        # call still holds it; the maker and the closure share it.
        # (captured: marked shared, or named by a MakeCell here -- `my ($k) = @_`
        # captured was not marked, and its closure read freed stack: "0 0")
        my $captured = $pad->shared || grep { $_->operation eq 'MakeCell' && ( $_->cell_name // '' ) eq $pad->name } @{ $b->{own_nodes} // [] };
        # (REFERENCED -- `\$x` -- it outlives the call too)
        $captured ||= grep { $_->operation eq 'Ref' && grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && ( $_->symbol // '' ) eq ( $pad->symbol // '' ) } $_->inputs->@* } @{ $b->{own_nodes} // [] };
        my $p = Chalk::Target::LLVM::T2::_n(op => ( $captured ? 'HeapCell' : 'Alloca' ), type => '%Slot*', attr => { name => $pad->name });
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
    # (a read pinned on the chain is made where it stands -- a $@ read made
    # early read the inner eval's message after the outer's die: "in" for "out")
    $b->value($_) for grep { !_pinned($_) && !$b->_needs_unmade_phi($_, {}) && !$b->_through_ref($_) }
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
    return 1 if $op =~ /\A(?:MemStart|Assign|EntryWrite|Delete|CellWrite)\z/;   # a store's version
    return 1 if $op eq 'Call' && $n->can('control_in') && blessed($n->control_in);
    # A READ OF A TIED AGGREGATE is a method call: B::SoN pins it and versions memory at it.
    return 1 if $op =~ /\A(?:Subscript|Count|Exists)\z/ && $n->can('control_in') && blessed($n->control_in);
    # A PINNED MATCH: B::SoN versions memory at it (a /g's pos); no value changes there.
    return 1 if $op =~ /\A(?:RegexMatch|Match)\z/ && $n->can('control_in') && blessed($n->control_in);
    # A PINNED s/// stores its subject's new string (in place).
    return 1 if $op =~ /\A(?:RegexSubst|Transliterate)\z/ && $n->can('control_in') && blessed($n->control_in);
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
    return $in[0] if $op eq 'FieldAccess';
    return $in[1] if $op eq 'CellRead';
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
    for my $n (grep { ( _pkg_scalar($_) || $_->operation eq 'FieldAccess' ) && !$_->inputs->@* } @nodes) {
        my @w = grep { $_->operation =~ /\A(?:EntryWrite|Assign)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) }
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
            attr => { strict => ( $target->can('strict') && $target->strict ? 1 : 0 ), %{ $b->deref_at($target) } });
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
        $b->reads_before($_) for @{ $b->{passed} };
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
        next if _is_list_target($r);
        next unless grep { blessed($_) && refaddr($_) == refaddr($s) } $r->inputs->@*;
        if ( exists $val{ $r->symbol } ) { $b->{memo}{ refaddr($r) } = $val{ $r->symbol }; next }
        my $last = $b->{lvals}{ $r->symbol } // out('a read after a list assignment of no target (' . $r->symbol . ')');
        # (an argument is read where it is: as `my (...) = @_` reads keep it)
        if ( $b->{args_vals}{ refaddr($last) } ) { $b->{args}{ refaddr($r) } = $last } else { $b->{memo}{ refaddr($r) } = $last }
    }
    push @{ $b->{passed} }, $s;
}

# _is_list_target($pad) -> true for a `my` named as an assign's target -- a
# list assign's, or a scalar one's (B::SoN versions it by the memory before
# that assign): a write, not a read.
sub _is_list_target {
    my ($r) = @_;
    return scalar grep {
        my $a = $_;
        blessed($a) && $a->operation eq 'Assign'
            && grep { blessed($_) && refaddr($_) == refaddr($r) }
                    @{ $a->inputs }[ 0 .. ( $a->can('targets') && defined $a->targets ? $a->targets - 1 : 0 ) ]
    } ( $r->consumers // [] )->@*;
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
        next if _pkg_literal_of($lit);   # a package array, read where it is read
        next if grep { !( blessed($_) && $_->operation eq 'Constant' ) } $lit->inputs->@*;
        $b->value($lit);
    }
    # A `my %h = (...)` of constants, or of @_, is made at entry too.
    for my $lit (grep { $_->operation eq 'HashLiteral' && ( $_->stamp // '' ) eq 'Hash' && !_pinned($_) && !_pkg_literal_of($_) } @nodes) { # static type
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
                       Chalk::Target::LLVM::Context::_graph_component($sub->graph)) {
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
            for my $p (@{ $cmp_envpads // [] }) {
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

# A `my %h` NAMED, NOT MADE HERE (`my %e;`): one hash per variable, made at
# its function's entry -- as a `my @a` is.
sub _hash_var {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PadAccess' && ( $n->sigil // '' ) eq '%' && ( !$n->inputs->@* || $n->can('shared') && $n->shared );   # (a shared one, read at a memory version: the one hash; hash_var says whose)
}
# _pkg_agg($n): a package array or hash read by name (`our @a`, `%P::h`) --
# not perl's own (@ISA, @ARGV, %ENV, @INC, %SIG, @_, a stash `%main::`, a
# punctuation name): each has its own meaning, read elsewhere or refused.
sub _pkg_agg {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) =~ /\A[\@%]\z/
        && ( $n->symbol // '' ) =~ /\A[A-Za-z_]\w*\z/
        && $n->symbol !~ /\A(?:ISA|ARGV|ARGVOUT|ENV|INC|SIG|STDIN|STDOUT|STDERR|_)\z/;
}
# _pkg_literal_of($n): the package aggregate a named Array/HashLiteral is
# stored into whole (B::SoN's `@a = LIST`), or undef.
sub _pkg_literal_of {
    my ($n) = @_;
    return undef unless blessed($n) && $n->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/;
    for my $w ( ( $n->consumers // [] )->@* ) {
        next unless blessed($w) && $w->operation eq 'EntryWrite' && !$w->binds   # (a `local`'s fresh one is not stored, bound)
            && blessed( $w->inputs->[1] ) && refaddr( $w->inputs->[1] ) == refaddr($n);
        return $w->inputs->[0] if _pkg_agg( $w->inputs->[0] );
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
sub _pkg_agg_name {
    my ($n) = @_;
    return ( $n->sigil eq '%' ? 'pkghash::' : 'pkgarr::' ) . ( ( $n->can('package') ? $n->package : undef ) // 'main' ) . '::' . $n->symbol;
}
# swapped -> { name => 1 } of the package aggregates a `local` swaps anywhere.
sub swapped {
    my ($b) = @_;
    return $b->{swapped} //= { map { ( _pkg_agg_name( $_->inputs->[0] ) => 1 ) }
        grep { $_->operation eq 'EntryWrite' && $_->binds && _pkg_agg( $_->inputs->[0] ) } _all_nodes( $b->{mop}, $b->{ret} ) };
}
sub _named_hash {
    my ($n) = @_;
    return _hash_var($n) || blessed($n) && $n->operation eq 'HashLiteral' && ( $n->stamp // '' ) eq 'Hash'; # static type
}
# emit_entry(%n): a node made at the function's entry (first block's start),
# where each `my` aggregate of the function is made.
sub emit_entry {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::T2::_n(%a);
    unshift @{ $b->{blocks}[0]{nodes} }, $n;
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
    # A SLURPY HASH PARAMETER: its hash, made at the sub's entry (args_rest).
    return $b->{memo}{ refaddr($n) } if blessed($n) && $n->operation eq 'Parameter' && $b->{memo}{ refaddr($n) };
    return $b->value($n) if _named_hash($n) || _pkg_agg($n) && $n->sigil eq '%';
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
        # \$x: a reference to the variable itself, kept on the heap (tag 9).
        # (NOT IN A LOOP BODY OR AN ARM: a `my` there is a new variable each time,
        # and the one cell made at entry would be all of them -- `2,2` for perl's `1,2`)
        out('a reference to a scalar in a loop body or an arm') if $b->{depth}
            && blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$';
        return $b->emit(op => 'SRef', type => '%Slot', inputs => [ $b->location($t) ])
            if blessed($t) && $t->operation eq 'PadAccess' && ( $t->sigil // '' ) eq '$' && $t->is_location;
        # \%h: a named hash IS its reference here (a %Slot of tag 5), one hash, two names.
        return $b->value($t) if blessed($t) && ( _named_hash($t) || _pkg_agg($t) && $t->sigil eq '%' ) && ( $v->stamp // '' ) eq 'HashRef';   # static type
        out('a reference to what is not an array') unless blessed($t)
            && ( $t->operation eq 'ArrayLiteral' && ( $t->stamp // '' ) eq 'Array' || _aderef($t) || _array_var($t) || _argv($t)
                 || _pkg_agg($t) && $t->sigil eq '@' ) # static
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
    # A HASH COUNTED is its keys (perl 5.26+), not its pairs flattened (4 for 2).
    if ($op eq 'Count' && blessed($in[0]) && ( _named_hash($in[0]) || $in[0]->operation eq 'PostfixDeref' && ( $in[0]->sigil // '' ) eq '%' || $in[0]->operation eq 'FieldAccess' && ( $b->field_of($in[0]) )[1] eq '%' )) {
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
        if ($name =~ /\A(?:tie|tied|untie)\z/) {
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
    # A CALL IN LIST CONTEXT: its result is a list (of one value, maybe). Its
    # use decides, not its stamp (a call stamped List is a scalar's in `my $n =`).
    return _list_use($n) if $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) =~ /\A(?:direct|method|indirect)\z/;
    return 1 if ( $n->stamp // '' ) =~ /\A(?:List|Array|Hash)\z/; # static type
    # A MATCH IN LIST CONTEXT (B::SoN stamps it Boolean): by what takes it.
    return _match_in_list($n) if $n->operation =~ /\A(?:RegexMatch|Match)\z/;
    return 1 if $n->operation eq 'PadAccess' && ( $n->sigil // '' ) =~ /\A[@%]\z/;
    return 1 if $Chalk::Target::LLVM::T2::Builder::LIST_FIELD{ refaddr($n) };
    return 0;
}

# _match_in_list($match) -> 1 if what takes the match takes a list: print (a
# Coerce B::SoN put there is no scalar context), a list's element, a sub
# call's argument, push/unshift/join/sprintf/die/warn, a list assignment.
# Returned, its context is the caller's: refused.
my %LIST_BUILTIN = map { ( $_ => 1 ) } qw(push unshift join sprintf die warn printf);
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
        Chalk::Target::LLVM::T2::Builder::out('a match returned (its context is its caller\'s)') if $op eq 'Return';
        if ( $op eq 'Coerce' && grep { blessed($_) && $_->operation eq 'Print' } ( $c->consumers // [] )->@* ) { $list = 1; next }
        $list = 1 if $op =~ /\A(?:Print|ArrayLiteral|ListAppend)\z/ && $is_in->($n);
        $list = 1 if $op eq 'Call' && ( $c->dispatch_kind // '' ) =~ /\A(?:direct|method|indirect)\z/;
        $list = 1 if $op eq 'Call' && ( $c->dispatch_kind // '' ) eq 'builtin' && $LIST_BUILTIN{ $c->name // '' };
        $list = 1 if $op eq 'Assign' && blessed( $c->inputs->[-1] ) && refaddr( $c->inputs->[-1] ) == refaddr($n)
            && ( ( $c->can('targets') && defined $c->targets ) || grep { blessed($_) && $_->can('sigil') && ( $_->sigil // '' ) =~ /\A[\@%]\z/ } @{ $c->inputs }[ 0 .. $#{ $c->inputs } - 1 ] );
    }
    return $list;
}

# _aderef($n): `@$r`, `@{...}`, `$r->@*` -- an array deref (a `${...}` is a
# scalar's: not this).
sub _aderef {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PostfixDeref' && ( $n->sigil // '@' ) eq '@';
}

# A PACKAGE SCALAR (`our $g`, `$::s`, `$P::v`): one global %Slot every sub
# reads and writes. perl's own ($/, $", $0, $_, ...) are not. ($a and $b ARE: a sort sets them before each call of its comparator.)
# ($_ is one: B::SoN spells a foreach's aliasing as stores to it, the
# element written back, and its value restored after.)
my %PERLS_OWN = map { ( $_ => 1 ) } qw(ARGV ENV INC STDIN STDOUT STDERR 0 AUTOLOAD);
sub _pkg_scalar {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) eq '$'
        && ( ( $n->symbol // '' ) =~ /\A[A-Za-z_]\w*\z/ && !$PERLS_OWN{ $n->symbol } || ( $n->symbol // '' ) eq '@' );   # ($@: the runtime's, die sets it)
}
sub global_of {
    my ($b, $n) = @_;
    return '@t2_err' if $n->symbol eq '@';
    my $name = ( ( $n->can('package') ? $n->package : undef ) // 'main' ) . '::' . $n->symbol;
    return $b->global_named($name);
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

# @ARGV: the program's arguments, one array (made from argv on first use).
sub _argv {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'EntryDef' && ( $n->sigil // '' ) eq '@' && ( $n->symbol // '' ) eq 'ARGV'
        && ( ( $n->can('package') ? $n->package : undef ) // 'main' ) eq 'main';
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
        my @pos = grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($c) } 0 .. $#{ $u->inputs };
        # (the call as a memory version -- a read after it, a store's memory --
        # is not a use of its value)
        # (only its memory position: `push @a, f()` has f() as its value AND its memory)
        my $m = _memory_input($u);
        if (blessed($m) && refaddr($m) == refaddr($c)) {
            my ($mi) = reverse grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($m) } 0 .. $#{ $u->inputs };
            @pos = grep { $_ != $mi } @pos;
        }
        # (a LIST assign's last input is its list, not its memory: `my ($x, $y) = f()`)
        @pos = grep { $_ != $#{ $u->inputs } } @pos if $u->operation =~ /\A(?:Assign|EntryWrite|Delete|Exists)\z/
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

# A `my @a` NAMED, NOT MADE HERE: B::SoN's PadAccess of an array declared
# once in its sub (one declared in a loop body or an arm is an ArrayLiteral
# pinned there, made each time). One %Array per variable, made at its
# function's entry: fresh each call. A closure's (shared) is not T2's.
sub _array_var {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'PadAccess' && ( $n->sigil // '' ) eq '@' && ( !$n->inputs->@* || $n->can('shared') && $n->shared );
}

sub array_var {
    my ($b, $pad) = @_;
    if (blessed($pad) && defined( my $i = ( $b->{cmp_env} // {} )->{ refaddr($pad) } )) { return $b->emit(op => 'ADeref', type => '%Array*', inputs => [ $b->emit(op => 'CmpEnv', type => '%Slot', attr => { index => $i }) ]) }
    # A FILE'S ARRAY: likewise, the global holding its reference.
    return $b->{locs}{ '@file#' . $pad->symbol } //= $b->emit_entry(op => 'GArray', type => '%Array*', attr => { global => $b->global_named( 'my::@' . $pad->symbol ) })
        if $pad->can('file') && $pad->file;
    out('an array a closure shares') if $pad->can('shared') && $pad->shared && !$b->_own_shared($pad);
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
    if (blessed($n) && ( $n->operation =~ /\A(?:ArrayLiteral|ArgsSource)\z/ || _aderef($n) || _array_var($n) || _argv($n)
                         || _pkg_agg($n) && $n->sigil eq '@'
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
    return $b->emit(op => 'HPairs', type => '%Array*', inputs => [ $b->hash_of($n) ]) if _named_hash($n)
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
    if (my $pkg = _isa_var($n)) {
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
        my $mem = _memory_input($c) // ( $c->operation =~ /\A(?:EntryDef|PadAccess)\z/ ? $in[0] : undef );
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
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $if->inputs->[1], $i );
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
    out('an early exit joined where an arm died') if grep { $_->{block}{dead} } @preds;
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
    push @{ $b->{passed} }, _memory_phis($r);
    return $r;
}

# call($Call) -> the %Slot a direct call of a sub returns: its function, made
# once, called with each argument boxed (one not passed is undef).
sub call {
    my ($b, $c) = @_;
    # A DIRECT CALL OF A CLOSURE (`$f->()` B::SoN resolved): through the code
    # value its AnonSub makes in this function -- its cells are there.
    if (( $c->name // '' ) =~ /__ANON__/) {
        my @anon = grep { $_->operation eq 'AnonSub' && ( $_->name // '' ) eq $c->name } @{ $b->{own_nodes} // [] };
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
    $called{$_} = 1 for grep { my $t = $_; grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'tie' } _all_nodes($mop, $b->{ret}) } qw(TIEARRAY TIEHASH FETCH STORE FETCHSIZE PUSH POP SHIFT UNSHIFT EXISTS DELETE CLEAR EXTEND FIRSTKEY NEXTKEY);
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
    my @names = @{ $c->can('param_names') ? $c->param_names // [] : [] };
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
    $b->{strs}{$c} //= scalar keys %{ $b->{strs} };
    return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
}

# _all_nodes($mop, $ret) -> the program's nodes and every package sub's.
# _arg_subscript($n) -> $n is $_[N]: a Subscript of @_ by a constant index.
sub _arg_subscript {
    my ($n) = @_;
    return blessed($n) && $n->operation eq 'Subscript' && blessed( $n->inputs->[0] ) && $n->inputs->[0]->operation eq 'ArgsSource'
        && blessed( $n->inputs->[1] ) && $n->inputs->[1]->operation eq 'Constant' && ( $n->inputs->[1]->value // '' ) =~ /\A\d+\z/;
}

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
        @{ $b->{own_nodes} // [] };
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

# func($sub, $name) -> the T2 function a sub is: `%Slot (%Slot args...)`, its
# REGEXES ARE GRAPHS. regex_result($match) -> the %Slot its matcher returns
# ([start, end, g1s, g1e, ...] or undef), made once where the match is.
sub regex_result {
    my ($b, $m) = @_;
    my $k = 'rx' . refaddr($m);
    return $b->{memo}{$k} if $b->{memo}{$k};
    my @code = $b->code_bodies($m);
    # A MATCH WHOSE BLOCKS RUN STORES what they store: every read of an earlier
    # version is made before it (a read between two such matches saw the second).
    if (@code) { $b->hash_reads_settled('a match whose code blocks run'); $b->reads_before($_) for @{ $b->{passed} } }
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
            out('a match against a pattern built at run time') if _made_a_string($re);
            out('a match against a qr value with flags of its own (' . $flags . ')') if $flags =~ /[^u]/;
            return $b->{memo}{$k} = $b->emit_call(op => 'QrMatch', type => '%Slot', inputs => [ $b->as( $b->value($re), '%Slot' ), $subj ]);
        }
        ( $pat, $flags ) = ( $re->value // '', join '', ( $re->can('flags') ? $re->flags // '' : '' ), $flags );
        }
    }
    my @lit = map { $b->as( $b->value($_), '%Slot' ) } @{ $rlits // [] };
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
    my @names = $m->can('code_bodies') && $m->code_bodies ? @{ $m->code_bodies } : ();
    return map {
        my $g = $Chalk::IR::Serialize::JSON::CODE_GRAPHS{$_} // out('a regex code block whose body B::SoN did not give');
        my $sub = $b->{rxcode}{$_} //= Chalk::MOP::Sub->new( name => $_, class => undef, graph => $g, params => ['@_'], uses_args => 1 );
        $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $b->func( $sub, 'rxcode_' . scalar keys %{ $b->{rxcode} } )->{name} });
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
    return @{ $b->{locs}{$key} //= [ map {
        my $p = Chalk::Target::LLVM::T2::_n(op => 'Alloca', type => '%Slot*', attr => { name => "pos(" . $pad->name . ")$_" });
        unshift @{ $b->{blocks}[0]{nodes} }, $p;
        $p
    } 1, 2 ] };
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
    } @{ $b->{own_nodes} // [] };
    $b->emit(op => 'Store', type => 'void', inputs => [ $b->emit(op => 'Undef', type => '%Slot'), $_ ]) for $b->pos_cells($pad);
}

# regex_list($match) -> an array ref of what the match gives in list context.
sub regex_list {
    my ($b, $m) = @_;
    my $k = 'rxl' . refaddr($m);
    return $b->{memo}{$k} if $b->{memo}{$k};
    out('a regex match with code blocks') if $m->can('code_bodies') && $m->code_bodies && @{ $m->code_bodies };
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
    my @lit = map { $b->as( $b->value($_), '%Slot' ) } @{ $rlits // [] };
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
    my ( $pat, $subj, $limit ) = grep { blessed($_) && !_is_version($_) } $c->inputs->@*;
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
    out('an s/// with code blocks') if $s->can('code_bodies') && $s->code_bodies && @{ $s->code_bodies };
    out('an s/// with an empty pattern (the last pattern that matched)') if ( $s->pattern // '' ) eq '' && !$s->pattern_is_input;
    # s///ge: ITS BODY CALLED PER MATCH by the subst graph (percall), which
    # stores the match's $& $1.. where the body's captures read them.
    if ( $s->can('replacement_body') && defined( my $body = $s->replacement_body ) ) {
        my $g = $Chalk::IR::Serialize::JSON::CODE_GRAPHS{$body} // out('an s///e replacement whose body B::SoN did not give');
        out('an s///e replacement holding an s///e (its matches would overwrite the captures it reads)')
            if grep { $_->operation eq 'RegexSubst' && $_->can('replacement_body') && defined $_->replacement_body }
               Chalk::Target::LLVM::Context::_graph_component($g);
        my $sub = $b->{rxcode}{$body} //= Chalk::MOP::Sub->new( name => $body, class => undef, graph => $g, params => ['@_'], uses_args => 1 );
        my $code = $b->emit(op => 'CodeOfFn', type => '%Slot', attr => { fn => $b->func( $sub, 'rxrepl_' . scalar keys %{ $b->{rxcode} } )->{name} });
        ( my $flags = $s->flags // '' ) =~ s/[er]//g;
        my $subj = $b->as( $b->value( $s->inputs->[0] ), '%Slot' );
        $b->reads_before($_) for @{ $b->{passed} };   # (the body may read and store what reads here read)
        return $b->{memo}{$k} = $b->subst_call( $s, $flags, { percall => 1 }, $subj, $code );
    }
    # A COMPUTED REPLACEMENT is an input between the subject (and a pattern
    # input) and the memory version: B::SoN makes it in the arm of a match of
    # its own -- ONCE.
    my @in = grep { blessed($_) } @{ $s->inputs }[ ( $s->pattern_is_input ? 2 : 1 ) .. $#{ $s->inputs } ];
    my $repl = @in && !_is_version( $in[0] ) && !Chalk::Target::LLVM::Context::_is_memory_phi( $in[0] ) ? $in[0] : undef;
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
    my @pats = _const_choices($pn);
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

# _const_choices($node) -> the strings a pattern node can be: a constant, a
# concatenation of such, a choice (?:) of such. () for anything else.
sub _const_choices {
    my ($n) = @_;
    return () unless blessed($n);
    my $op = $n->operation;
    return ( $n->value // '' ) if $op eq 'Constant' && ( $n->const_type // '' ) =~ /\A(?:string|integer)\z/;
    return _const_choices( $n->inputs->[0] ) if $op eq 'Coerce';
    if ( $op eq 'Concat' ) {
        my @a = _const_choices( $n->inputs->[0] ) or return ();
        my @z = _const_choices( $n->inputs->[1] ) or return ();
        return map { my $x = $_; map { "$x$_" } @z } @a;
    }
    if ( $op eq 'TernaryExpr' ) {
        my @a = _const_choices( $n->inputs->[1] ) or return ();
        my @z = _const_choices( $n->inputs->[2] ) or return ();
        my %seen;
        return grep { !$seen{$_}++ } @a, @z;
    }
    return ();
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
    my $fn = $b->func( $sub, 'tr_' . scalar keys %{ $b->{rxsub} } );
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

# _in_place($node) -> an s/// or tr that writes its subject: pinned, not /r,
# of a variable (B::SoN gives a copy's -- `(my $t = $s) =~ s///` -- as the
# value it was given: the node's value is then the new string).
sub _in_place {
    my ($s) = @_;
    my $subj = $s->inputs->[0];
    return ( $s->flags // '' ) !~ /r/ && $s->can('control_in') && blessed( $s->control_in )
        && blessed($subj) && $subj->operation eq 'PadAccess';
}

# regex_subst_stmt($RegexSubst): an s/// where it stands -- in place (not /r):
# its new string stored into its subject, a `my` scalar kept here.
sub regex_subst_stmt {
    my ($b, $s) = @_;
    my $subj = $s->inputs->[0];
    my $new = $b->regex_subst_part( $s, 0 );
    return unless _in_place($s);   # (its value is the new string: what reads it reads)
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
    return $b->func( $sub, 'regex_' . scalar keys %{ $b->{rxsub} } );
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
            my $c = _const_pattern($arg);
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

# _made_a_string($node) -> 1 where what makes it makes a string, never a qr
# value: input (%ENV), a concatenation, a string builtin, a default of those.
sub _made_a_string {
    my ($n) = @_;
    return 0 unless blessed($n);
    my $op = $n->operation;
    return 1 if $op =~ /\A(?:EnvRead|Concat|Interpolate)\z/;
    return 1 if $op eq 'Constant' && ( $n->const_type // '' ) =~ /\A(?:string|integer)\z/;
    return 1 if $op eq 'Call' && ( $n->dispatch_kind // '' ) eq 'builtin' && ( $n->name // '' ) =~ /\A(?:join|sprintf|lc|uc|lcfirst|ucfirst|substr|quotemeta|sprintf)\z/;
    return _made_a_string( $n->inputs->[0] ) && _made_a_string( $n->inputs->[1] ) if $op eq 'DefinedOr';
    return 0;
}

# _const_pattern($node) -> the string an interpolated pattern is where B::SoN
# folded it to constants (a string, or strings joined), else undef.
sub _const_pattern {
    my ($n) = @_;
    return undef unless blessed($n);
    my $op = $n->operation;
    return $n->value // '' if $op eq 'Constant' && ( $n->const_type // '' ) =~ /\A(?:string|integer)\z/;
    return _const_pattern( $n->inputs->[0] ) if $op eq 'Coerce';
    if ( $op eq 'Concat' ) {
        my @p = map { _const_pattern($_) } grep { blessed($_) } $n->inputs->@*;
        return undef if grep { !defined } @p;
        return join '', @p;
    }
    return undef;
}

# _rx_arm(\%ok, $cond, $arm) -> the matches known to have succeeded in arm
# $arm (0 the true one) of a branch on $cond: a match, or not a match.
sub _rx_arm {
    my ($ok, $cond, $arm) = @_;
    my %ok = %{ $ok // {} };
    if ( blessed($cond) && $cond->operation =~ /\A(?:RegexMatch|Match)\z/ ) { $ok{ refaddr($cond) } = 1 if $arm == 0 }
    elsif ( blessed($cond) && $cond->operation eq 'Not' && blessed( $cond->inputs->[0] ) && $cond->inputs->[0]->operation =~ /\A(?:RegexMatch|Match)\z/ ) {
        $ok{ refaddr( $cond->inputs->[0] ) } = 1 if $arm == 1;
    }
    return \%ok;
}

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
        my @gn = Chalk::Target::LLVM::Context::_graph_component($g);
        out("method $name reads \@_") if grep { $_->operation eq 'ArgsSource' } @gn;
        my $np = $sub->can('params') ? scalar @{ $sub->params // [] } : 0;
        out("method $name has a parameter past its declared ones")
            if grep { $_->operation eq 'Parameter' && ( $_->index // 0 ) >= $np } @gn;
        out("method $name has a slurpy parameter")
            if grep { $_->operation eq 'Parameter' && ( $_->can('sigil') ? $_->sigil // '$' : '$' ) ne '$' } @gn
            or grep { ( ref($_) ? $_->{name} // $_->{sigil} // '' : $_ // '' ) =~ /\A[@%]/ } @{ $sub->can('params') ? $sub->params // [] : [] };
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
           grep { $_->operation eq 'CellParam' } Chalk::Target::LLVM::Context::_graph_component($g);
    out("sub $name captures a variable (a named sub's closure)") if !$closure
        && grep { $_->operation eq 'CellParam' } Chalk::Target::LLVM::Context::_graph_component($g);
    # $_[N] READ ANYWHERE is the Nth argument: Context.pm's binder keeps one
    # read per index, and a position never read is a hole it refuses. A sub
    # that reads @_ only so binds every such read -- after a store, twice --
    # to its argument; an unread position is a placeholder (its argument
    # passed, unused).
    my @also;
    if (!$is_method && !$list && !$@ && @reads && !$an->{_args_written} && !$an->{_args_read_as_a_list}
            && !$an->{_args_slurpy} && !$an->{_args_signature}
            && !grep { blessed($_) && !_arg_subscript($_) } @reads) {
        my %by;
        push @{ $by{ $_->inputs->[1]->value } }, $_ for grep { _arg_subscript($_) } Chalk::Target::LLVM::Context::_graph_component($g);
        my $max = -1;   # (not sort: a sort block's $b is the builder here)
        $max < $_ and $max = $_ for keys %by;
        @reads = map { $by{$_} ? $by{$_}[0] : bless( {}, 'Chalk::Target::LLVM::T2::Unread' ) } 0 .. $max;
        @also = map { my $i = $_; map { [ $_, $i ] } @{ $by{$i} }[ 1 .. $#{ $by{$i} } ] } grep { $by{$_} } 0 .. $max;
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
    $id .= '_' . scalar keys %{ $b->{funcs} } if grep { $_->{name} eq "\@f_$id" } values %{ $b->{funcs} // {} };
    my $nargs = $is_method ? 1 + $margs{np} : $list ? 1 : scalar @reads;
    my $fn = $b->{funcs}{ refaddr($sub) } = { name => "\@f_$id", wrapper => "\@w_$id", nargs => $nargs,
        signature => $sig, list => $list, listret => $listret, closure => $closure, blocks => [] , minargs => ( $slurpy && $sig ? scalar @positional : undef ),
        slurpy_sigil => ( $slurpy && $sig ? ( $slurpy->can('sigil') ? $slurpy->sigil // '@' : '@' ) : undef ) };
    my @argn = map { Chalk::Target::LLVM::T2::_n(op => 'Arg', type => '%Slot', attr => { index => $_ }) } 0 .. ( $is_method ? $nargs : scalar @reads ) - 1;
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
    local $b->{seq} = 0;   # (its own statements' turns: its entry is turn 0)
    local $b->{locs} = {};
    local $b->{memo} = {};
    local $b->{args} = $is_method ? { map { ( $_ => $argn[ $margs{$_} ] ) } grep { $_ ne 'np' } keys %margs }
                                  : { ( map { ( refaddr( $reads[$_] ) => $argn[$_] ) } 0 .. $#reads ), ( map { ( refaddr( $_->[0] ) => $argn[ $_->[1] ] ) } @also ) };
    local $b->{self} = $is_method ? $argn[0] : undef;   # a field's object
    local $b->{env} = $closure ? do { my $e = Chalk::Target::LLVM::T2::_n(op => 'Arg', type => '%Slot**', attr => { index => 1 }); $e->set_name('%env'); $e } : undef;
    local $b->{own_nodes} = [ Chalk::Target::LLVM::Context::_graph_component($g) ];
    local $b->{eval_at} = { map { ( refaddr( $_->eval_entry ) => $_ ) } grep { $_->operation eq 'Region' && $_->can('eval_entry') && blessed( $_->eval_entry ) } @{ $b->{own_nodes} } };
    local $b->{evals} = [];
    local $b->{eval_opened} = {};
    local $b->{in_func} = 1;
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
    # THE CALLER'S CONTEXT, read first (a call in the body sets it).
    my $want = $b->emit(op => 'GetWant', type => 'i1');
    if ($slurpy) {
        # A SIGNATURE'S ARITY: at least its positional parameters (perl dies
        # with fewer -- a run-time stop here, as a signature's wrapper's is).
        $b->emit(op => 'ArgsMin', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional }) if $sig;
        $b->emit(op => 'ArgsPairs', type => 'void', inputs => [ $argsarr ], attr => { n => scalar @positional })
            if $sig && ( $slurpy->can('sigil') ? $slurpy->sigil // '' : '' ) eq '%';
        # ITS PARAMETERS, made here: each its argument, the slurpy one the rest.
        for my $p (grep { $_->operation eq 'Parameter' } Chalk::Target::LLVM::Context::_graph_component($g)) {
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
    $b->make_constant_arrays(Chalk::Target::LLVM::Context::_graph_component($g));
    local $b->{jumps} = {};   # this function's early exits
    $b->walk($start);
    out('an early exit to a merge never reached') if %{ $b->{jumps} };
    out('an eval left open at the end') if @{ $b->{evals} };
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
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $cond[0], 0 );   # (a body runs where its condition held)
        $b->walk($bodyp);
        @back = map { $b->as($b->value($phis[$_]->inputs->[1]), $t2[$_]->type) } 0 .. $#phis;
    }
    my $body_end = $b->{cur};
    out('a loop body that dies at its end') if $body_end->{dead};
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
    return $v->sigil eq '@' ? '%Array*' : '%Slot' if _pkg_agg($v);   # a hash is its %Slot
    return '%Slot' if $op eq 'ArrayLiteral' && ( $v->stamp // '' ) eq 'ArrayRef'; # static type
    return '%Slot' if $op eq 'Ref';
    return '%Slot' if $op eq 'PostfixDeref' && ( $v->sigil // '' ) eq '$';
    return '%Array*' if $op eq 'ArrayLiteral' || _aderef($v) || _array_var($v) || $op eq 'ArgsSource' || $op eq 'ListAppend';
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
    return ( $v->stamp // '' ) eq 'Scalar' ? '%Slot' : '%Array*'   # static type
        if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'caller';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'substr';
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/;
    return 'i64'   if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'index';
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:keys|values)\z/) {
        return $v->name eq 'keys' && ( $v->can('want') ? $v->want // '' : '' ) eq 'scalar' ? 'i64' : '%Array*';
    }
    return '%Array*' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:sort|reverse)\z/
        && ( $v->stamp // '' ) =~ /\A(?:Array|List)\z/;   # static type
    return '%Slot' if $op eq 'Call' && ( $v->name // '' ) =~ /\A(?:shift|pop)\z/;
    return '%Str' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:uc|lc|ucfirst|lcfirst)\z/;
    return '%Str' if $op eq 'Call' && ( $v->name // '' ) eq 'join';
    return '%Array*' if _argv($v);
    return '%Slot' if _pkg_scalar($v);   # what it holds is what was stored last, anywhere
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
    return '%Slot' if $op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:tie|tied|untie)\z/;
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
    return $b->pkg_agg($v) if _pkg_agg($v);
    # $] IS THE VERSION OF THE PERL T2 IS: the one compiling (whose semantics it
    # keeps), read-only.
    return $b->as( $b->const_str("$]"), $b->type_of($v) )   # (its text: "5.042000")
        if blessed($v) && $v->operation eq 'EntryDef' && ( $v->sigil // '' ) eq '$' && ( $v->symbol // '' ) eq ']' && ( ( $v->can('package') ? $v->package : undef ) // 'main' ) eq 'main';
    # THE LITERAL A PACKAGE AGGREGATE WAS STORED FROM is how B::SoN gives a
    # later read of the name: read as the aggregate, which a push or another
    # sub may have changed since (a copy of the literal printed "1 2" for "1 2 3").
    if (my $t = _pkg_literal_of($v)) { return $b->pkg_agg($t) }
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
        && ( my ($as) = ( grep( { blessed($_) && _args_list_assign($_) } $v->inputs->@* ),
                          grep( { blessed($_) && _args_list_assign($_) && grep { blessed($_) && refaddr($_) == refaddr($v) } @{ $_->inputs }[ 0 .. $#{ $_->inputs } - 1 ] } ( $v->consumers // [] )->@* ) ) )) {
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
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'push' && !_pinned($v)) {
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
    if (_pkg_scalar($v)) {
        out('a package scalar read of no one version') if $b->{unversioned}{ refaddr($v) };
        return $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->global_of($v) });
    }
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:uc|lc|ucfirst|lcfirst)\z/) {
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
        $b->{strs}{$c} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
    }
    # int(X): X's number truncated toward zero. rand(X): a number in [0, X),
    # X 1 when absent or 0 (perl's), from libc's generator -- not perl's.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:int|rand)\z/) {
        my @a = grep { blessed($_) && !_is_version($_) } $v->inputs->@*;
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
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
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
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
        my $r = $b->emit(op => 'Mod', type => 'i64',
            inputs => [ map { $b->as($b->value($_), 'i64') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        $b->after_call;   # (a zero modulus is a die: an eval's to catch)
        return $r;
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
        $b->{strs}{$k} //= scalar keys %{ $b->{strs} };
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
        { local $b->{memo} = { %{ $b->{memo} } };
          local $b->{rx_ok} = $v->operation eq 'TernaryExpr' ? _rx_arm( $b->{rx_ok}, $v->inputs->[0], 0 ) : $b->{rx_ok};
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
    # substr($s, $off, $len) READ (not an lvalue: B::SoN pins a store): from
    # either end, the rest or a length (negative leaves that many off the end);
    # undef outside the string, as perl's. index($s, $t, $pos): -1 for none.
    if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) =~ /\A(?:substr|index)\z/) {
        my @a = grep { blessed($_) } $v->inputs->@*;
        pop @a if $v->can('memory_input') && $v->memory_input;
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
        return $b->as( _in_place($v) ? $b->regex_subst_count($v) : $b->regex_subst_part( $v, 0 ), $ty );
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
    out("a conversion " . $n->type . " -> $ty") unless exists $Chalk::Target::LLVM::T2::Printer::CONVERT{ $n->type . '>' . $ty };
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
    # THE PROGRAM'S PACKAGE SCALARS BY NAME, for a string used as a reference
    # without strict refs (t2_symref).
    {
        my @add;
        my $n = 0;
        for my $name (sort grep { /\A[\w:]+::\w+\z/ && !/\Amy::/ } keys %{ $bld->{globals} // {} }) {
            my $len = do { use bytes; length $name };
            push @L, sprintf('@sym%d = private unnamed_addr constant [%d x i8] c"%s\00"', $n, $len + 1, $name);
            push @add, sprintf('  call void @t2_symtab_add(i8* getelementptr ([%d x i8], [%d x i8]* @sym%d, i64 0, i64 0), i64 %d, %%Slot* %s)', $len + 1, $len + 1, $n, $len, $bld->{globals}{$name});
            $n++;
        }
        push @L, 'define internal void @t2_symtab_init() {', @add, '  ret void', '}';
    }
    push @L, 'define i32 @main(i32 %argc, i8** %argv) {', _blocks($bld->{blocks}), '}', '';
    # EACH SUB A FUNCTION: `%Slot (%Slot %a0, ...)`, its blocks printed alike.
    for my $fn (sort { $a->{name} cmp $b->{name} } values %{ $bld->{funcs} // {} }) {
        my $i = 0;
        $_->set_name('%v' . $i++) for map { @{ $_->{nodes} } } @{ $fn->{blocks} };
        push @L, "define internal %Slot $fn->{name}(" . ( $fn->{closure} ? '%Array* %a0, %Slot** %env' : $fn->{list} ? '%Array* %a0' : join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) ) . ') {',
            _blocks($fn->{blocks}), '}', '';
        if ($fn->{closure}) {   # its code value's entry: a list context gets a list
            my @cn = $fn->{listret} ? ('  ret %Slot %r') : ('  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)', '  ret %Slot %rn');
            push @L, "define internal %Slot $fn->{name}_cw(%Array* %args, %Slot** %env) {", '  %w = load i1, i1* @t2_want',
                "  %r = call %Slot $fn->{name}(%Array* %args, %Slot** %env)", @cn, '}', '';
            next;
        }
        # ITS WRAPPER (a method's entry) gives a list context a reference to a
        # list: the sub's own (a list return), or one of its one value.
        my @norm = $fn->{listret} ? ('  ret %Slot %r') : ('  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)', '  ret %Slot %rn');
        if ($fn->{list}) {   # @_ already an %Array
            push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {", '  %w = load i1, i1* @t2_want',
                "  %r = call %Slot $fn->{name}(%Array* %args)", @norm, '}', '';
            next;
        }
        # ITS WRAPPER, a method's entry: @_ as an %Array, each argument its
        # element (undef past the end). A signature's arity perl checks.
        push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {", '  %w = load i1, i1* @t2_want';
        if ($fn->{signature}) {
            push @L, '  %n = call i64 @t2_alen(%Array* %args)', "  %ok = icmp eq i64 %n, $fn->{nargs}",
                '  br i1 %ok, label %call, label %bad', 'bad:',
                '  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)',
                '  unreachable', 'call:';
        }
        push @L, "  %a$_ = call %Slot \@t2_aget(%Array* %args, i64 $_)" for 0 .. $fn->{nargs} - 1;
        push @L, "  %r = call %Slot $fn->{name}(" . join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) . ')',
            @norm, '}', '';
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
        push @L, $k eq 'unreachable' ? '  unreachable'
               : $k eq 'ret'    ? '  ret i32 0'
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
    return "$nm = call %Slot* \@t2_cell_new()  ; my $a{name}, captured" if $op eq 'HeapCell';
    return "call void \@t2_die(" . $arg->(@in) . ')' if $op eq 'Die';
    return "$nm = call %Str \@t2_die_msg(" . $arg->(@in) . ')' if $op eq 'DieMsg';
    return "call void \@t2_die_unwind(" . $arg->(@in) . ')' if $op eq 'DieUnwind';
    return "call void \@t2_set_err(" . $arg->(@in) . ')' if $op eq 'SetErr';
    return "call void \@t2_eval_enter()" if $op eq 'EvalEnter';
    return "call void \@t2_eval_leave()" if $op eq 'EvalLeave';
    return "store i1 0, i1* \@t2_dying" if $op eq 'ClearDying';
    return "$nm = load i1, i1* \@t2_dying" if $op eq 'IsDying';
    return "$nm = call %Slot** \@t2_env_new(" . $arg->(@in) . ')' if $op eq 'EnvNew';
    return "call void \@t2_env_set(" . $arg->(@in) . ')' if $op eq 'EnvSet';
    return "$nm = call %Slot* \@t2_env_get(" . $arg->(@in) . ')' if $op eq 'EnvGet';
    return "$nm = call %Slot \@t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* $a{fn}_cw to i8*), " . $arg->(@in) . ')' if $op eq 'CodeNew';
    if ($op eq 'CallCode') {
        return "$nm.e = call %Slot** \@t2_code_env(%Slot " . $in[0]->name . ")\n  $nm.p = call i8* \@t2_code_fn(%Slot " . $in[0]->name
            . ")\n  $nm.f = bitcast i8* $nm.p to %Slot (%Array*, %Slot**)*\n  $nm = call %Slot $nm.f(%Array* " . $in[1]->name . ", %Slot** $nm.e)";
    }
    return "$nm = load %Slot, %Slot* " . $in[0]->name if $op eq 'Load';
    return "$nm = call %Slot \@t2_slot_numify(" . $arg->(@in) . ')' if $op eq 'Numify';
    return "$nm = call %Slot \@t2_slot_int(" . $arg->(@in) . ')' if $op eq 'IntOf';
    return "$nm = call %Slot \@t2_slot_rand(" . $arg->(@in) . ')' if $op eq 'Rand';
    return "store %Slot " . $in[0]->name . ", %Slot* " . $in[1]->name if $op eq 'Store';
    return "$nm = call %Slot \@t2_slot_$a{op}(" . $arg->(@in) . ')' if $op eq 'SlotStep';
    return "$nm = call %Slot \@t2_slot_$a{op}(" . $arg->(@in) . ')' if $op eq 'SlotArith';
    if ($op eq 'Mod') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call i64 \@t2_mod(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    if ($op eq 'SDeref' || $op eq 'SStore') {
        my $len = do { use bytes; length $a{msg} };
        my $at = "i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len";
        my $pl = do { use bytes; length $a{pk} };
        $at .= ", i8* getelementptr ([" . ( $pl + 1 ) . " x i8], [" . ( $pl + 1 ) . " x i8]* \@s$a{pkid}, i64 0, i64 0), i64 $pl";
        return "$nm = call %Slot \@t2_sderef(" . $arg->(@in) . ", i1 $a{strict}, $at)" if $op eq 'SDeref';
        return "call void \@t2_sstore(" . $arg->(@in) . ", i1 $a{strict}, $at)";
    }
    return "$nm = call %Slot \@t2_sref(%Slot* " . $in[0]->name . ')' if $op eq 'SRef';
    if ($op eq 'SCell') { my $p = $in[0]->name; return "$nm.p = extractvalue %Slot $p, 1\n  $nm = inttoptr i64 $nm.p to %Slot*" }
    if ($op eq 'Div') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call double \@t2_div(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    return "$nm = call %Str \@t2_concat(" . $arg->(@in) . ')' if $op eq 'Concat';
    return "$nm = call i64 \@t2_strcmp(" . $arg->(@in) . ')' if $op eq 'StrCmp';
    return "$nm = call %Str \@t2_strcase(" . $arg->(@in) . ')' if $op eq 'StrCase';
    return "$nm = extractvalue %Str " . $in[0]->name . ', 1' if $op eq 'StrLen';
    return "$nm = call %Slot \@t2_slot_length(" . $arg->(@in) . ')' if $op eq 'SlotLength';
    return "$nm = call %Array* \@t2_new_array()" if $op eq 'NewArray';
    return "$nm = call %Slot \@t2_hnew()" if $op eq 'HNew';
    return "call void \@t2_save_args(i32 %argc, i8** %argv)" if $op eq 'SaveArgs';
    return "$nm = load i1, i1* \@t2_want" if $op eq 'GetWant';
    return "store i1 " . $in[0]->name . ", i1* \@t2_want" if $op eq 'SetWant';
    return "$nm = select i1 " . $in[0]->name . ', ' . $arg->( @in[ 1, 2 ] ) if $op eq 'Select';
    return "$nm = load %Slot, %Slot* $a{global}" if $op eq 'GLoad';
    return "$nm = call %Slot \@t2_ghash(%Slot* $a{global})" if $op eq 'GHash';
    return "$nm = call %Array* \@t2_garray(%Slot* $a{global})" if $op eq 'GArray';
    return "$nm = getelementptr %Slot, %Slot* $a{global}, i64 0" if $op eq 'GAddr';
    return "store %Slot " . $in[0]->name . ", %Slot* $a{global}" if $op eq 'GStore';
    return "$nm = call %Array* \@t2_argv()" if $op eq 'Argv';
    return "$nm = call %Slot \@t2_bless(" . $arg->(@in) . ')' if $op eq 'Bless';
    return "$nm = call %Slot \@t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* \@t2_stash_tramp to i8*), %Slot** bitcast (%Slot (%Array*)* $a{fn}_w to %Slot**))" if $op eq 'CodeOfFn';
    return "$nm = call %Slot \@t2_qr_match(" . $arg->(@in) . ')' if $op eq 'QrMatch';
    return "call void \@t2_pos_update(%Slot " . $in[0]->name . ", %Slot* " . $in[1]->name . ", %Slot* " . $in[2]->name . ", i1 " . ( $a{keep} ? 1 : 0 ) . ")" if $op eq 'PosUpdate';
    return "$nm = call %Slot \@t2_class_of(" . $arg->(@in) . ')' if $op eq 'ClassOf';
    return "$nm = call %Str \@t2_reftype(" . $arg->(@in) . ')' if $op eq 'RefType';
    return "call void \@t2_universal_setup()" if $op eq 'MopUniversal';
    return "call void \@t2_mop_var(" . $arg->(@in) . ", %Slot* $a{global})" if $op eq 'MopVar';
    return "call void \@t2_mop_class(" . $arg->(@in) . ')' if $op eq 'MopClass';
    return "call void \@t2_mop_isa(" . $arg->(@in) . ')' if $op eq 'MopIsa';
    return "$nm = call %Array* \@t2_mop_isa_arr(" . $arg->(@in) . ')' if $op eq 'MopIsaArr';
    return "call void \@t2_mop_isa_set(" . $arg->(@in) . ')' if $op eq 'MopIsaSet';
    return "call void \@t2_mop_def(" . $arg->(@in) . ", i8* bitcast (%Slot (%Array*)* $a{fn}_w to i8*))" if $op eq 'MopDef';
    return "$nm = call i8* \@t2_mresolve(" . $arg->(@in) . ", i8 $a{mode})" if $op eq 'MResolve';
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
    return "call void \@t2_aunshift(" . $arg->(@in) . ')' if $op eq 'AUnshift';
    return "$nm = call %Array* \@t2_args_from(" . $arg->(@in) . ')' if $op eq 'ArgsFrom';
    return "call void \@t2_args_min(%Array* " . $in[0]->name . ", i64 $a{n})" if $op eq 'ArgsMin';
    return "call void \@t2_args_pairs(%Array* " . $in[0]->name . ", i64 $a{n})" if $op eq 'ArgsPairs';
    return "$nm = call %Array* \@t2_asort(" . $arg->(@in) . ", i1 $a{num}, i1 $a{desc})" if $op eq 'ASort';
    return "$nm = call %Array* \@t2_asort_by(" . $arg->(@in) . ", %Slot ()* $a{fn}, %Slot* $a{ga}, %Slot* $a{gb})" if $op eq 'ASortBy';
    return "$nm = call %Slot \@t2_cmp_env_at(i64 $a{index})" if $op eq 'CmpEnv';
    return "$nm = call %Slot \@t2_hderef_r(" . $arg->(@in) . ')' if $op eq 'HDerefR';
    return "$nm = call %Array* \@t2_arev(" . $arg->(@in) . ')' if $op eq 'ARev';
    return "call void \@t2_aassign(" . $arg->(@in) . ')' if $op eq 'AAssign';
    return "call void \@t2_hassign(" . $arg->(@in) . ')' if $op eq 'HAssign';
    return "call void \@t2_aunshiftl(" . $arg->(@in) . ')' if $op eq 'AUnshiftL';
    return "$nm = call %Slot \@t2_tie_array(" . $arg->(@in) . ')' if $op eq 'TieArray';
    return "$nm = call %Slot \@t2_tie_hash(" . $arg->(@in) . ')' if $op eq 'TieHash';
    return "$nm = call %Slot \@t2_tied(" . $arg->(@in) . ')' if $op eq 'TiedA';
    return "$nm = call %Slot \@t2_tied_h(" . $arg->(@in) . ')' if $op eq 'TiedH';
    return "call void \@t2_untie(" . $arg->(@in) . ')' if $op eq 'UntieA';
    return "call void \@t2_untie_h(" . $arg->(@in) . ')' if $op eq 'UntieH';
    return "call void \@t2_aappend(" . $arg->(@in) . ')' if $op eq 'AAppend';
    return "call void \@t2_apush_if(" . $arg->(@in) . ')' if $op eq 'APushIf';
    return "$nm = call %Slot \@t2_one_of(" . $arg->(@in) . ')' if $op eq 'OneOf';
    return "$nm = call %Slot \@t2_aref(" . $arg->(@in) . ')' if $op eq 'ARef';
    return "$nm = call %Array* \@t2_aderef(" . $arg->(@in) . ')' if $op eq 'ADeref';
    return "$nm = call %Array* \@t2_aderef_r(" . $arg->(@in) . ')' if $op eq 'ADerefR';
    if ($op eq 'ASet') {
        my $len = do { use bytes; length $a{msg} };
        return "call void \@t2_aset(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    my %aop = (ALen => 'i64 @t2_alen', AGet => '%Slot @t2_aget', AShift => '%Slot @t2_ashift', APop => '%Slot @t2_apop', Join => '%Str @t2_join');
    return "$nm = call $aop{$op}(" . $arg->(@in) . ')' if $aop{$op};
    return "call void \@t2_" . ( ( $a{fd} // 1 ) == 2 ? 'eprint' : 'print' ) . '(' . $arg->(@in) . ')' if $op eq 'Print';
    return "call void \@t2_exit(" . $arg->(@in) . ')' if $op eq 'Exit';
    return "call void \@t2_frame_push(" . $arg->(@in) . ')' if $op eq 'FramePush';
    return 'call void @t2_frame_pop()' if $op eq 'FramePop';
    return "$nm = call %Array* \@t2_caller(" . $arg->(@in) . ')' if $op eq 'Caller';
    return "$nm = call %Slot \@t2_caller_pkg(" . $arg->(@in) . ')' if $op eq 'CallerPkg';
    return "$nm = call %Slot \@t2_substr(" . $arg->(@in) . ')' if $op eq 'Substr';
    return "$nm = call i64 \@t2_index(" . $arg->(@in) . ')' if $op eq 'Index';
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
define internal void @t2_eprint(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  ret void
}
; THE CALL STACK caller reads: three slots a frame (package, file, line),
; pushed by each call of a sub while the program reads caller.
@t2_frames = internal global %Array* null
define internal %Array* @t2_frames_get() {
  %f = load %Array*, %Array** @t2_frames
  %z = icmp eq %Array* %f, null
  br i1 %z, label %mk, label %ok
mk:
  %n = call %Array* @t2_new_array()
  store %Array* %n, %Array** @t2_frames
  ret %Array* %n
ok:
  ret %Array* %f
}
define internal void @t2_frame_push(%Str %p, %Str %f, i64 %l) {
  %a = call %Array* @t2_frames_get()
  %sp = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush_d(%Array* %a, %Slot %sp)
  %sf = call %Slot @t2_box_str(%Str %f)
  call void @t2_apush_d(%Array* %a, %Slot %sf)
  %sl = call %Slot @t2_box_i64(i64 %l)
  call void @t2_apush_d(%Array* %a, %Slot %sl)
  ret void
}
define internal void @t2_frame_pop() {
  %a = call %Array* @t2_frames_get()
  %x = call %Slot @t2_apop_d(%Array* %a)
  %y = call %Slot @t2_apop_d(%Array* %a)
  %z = call %Slot @t2_apop_d(%Array* %a)
  ret void
}
; t2_frame_at(n) -> the index of frame n's package (n up from the innermost), or -1.
define internal i64 @t2_frame_at(i64 %n) {
  %a = call %Array* @t2_frames_get()
  %len = call i64 @t2_alen_d(%Array* %a)
  %n1 = add i64 %n, 1
  %k = mul i64 %n1, 3
  %neg = icmp slt i64 %n, 0
  %short = icmp slt i64 %len, %k
  %no = or i1 %neg, %short
  %base = sub i64 %len, %k
  %r = select i1 %no, i64 -1, i64 %base
  ret i64 %r
}
define internal %Array* @t2_caller(i64 %n) {
  %r = call %Array* @t2_new_array()
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  call void @t2_apush_d(%Array* %r, %Slot %p)
  %i1 = add i64 %i, 1
  %f = call %Slot @t2_aget_d(%Array* %a, i64 %i1)
  call void @t2_apush_d(%Array* %r, %Slot %f)
  %i2 = add i64 %i, 2
  %l = call %Slot @t2_aget_d(%Array* %a, i64 %i2)
  call void @t2_apush_d(%Array* %r, %Slot %l)
  br label %none
none:
  ret %Array* %r
}
define internal %Slot @t2_caller_pkg(i64 %n) {
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  ret %Slot %p
none:
  ret %Slot zeroinitializer
}
; substr(s, off[, len]): perl's translate_substr_offsets (pp.c), in signed ints --
; a negative offset counts from the end (still before it: clamped, unless the
; end is too). The bytes copied, NUL-ended. OUTSIDE THE STRING perl answers
; undef with a warning under `use warnings`, which T2 does not know: stopped
; at run time (exit 255), as the fallback does, not answered half right.
@lit_substr_out = private unnamed_addr constant [47 x i8] c"substr outside of string: stopped (chalk, T2)\0A\00"
define internal %Slot @t2_substr(%Str %s, i64 %off, i64 %len, i1 %has) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %oneg = icmp slt i64 %off, 0
  %npos = icmp sgt i64 %n, 0
  %adj = and i1 %oneg, %npos
  %offn = add i64 %off, %n
  %p1 = select i1 %adj, i64 %offn, i64 %off
  %past = icmp sgt i64 %p1, %n
  br i1 %past, label %undef, label %ends
ends:
  %lneg = icmp slt i64 %len, 0
  %fromend = add i64 %n, %len
  %p1neg = icmp slt i64 %p1, 0
  %p1len = add i64 %p1, %len
  %room = sub i64 %n, %p1
  %toolong = icmp sgt i64 %len, %room
  %fwd = select i1 %toolong, i64 %n, i64 %p1len
  %pos2 = select i1 %p1neg, i64 %p1len, i64 %fwd
  %withlen = select i1 %lneg, i64 %fromend, i64 %pos2
  %p2a = select i1 %has, i64 %withlen, i64 %n
  %p2neg = icmp slt i64 %p2a, 0
  %both = and i1 %p2neg, %p1neg
  br i1 %both, label %undef, label %clamp
clamp:
  %p2b = select i1 %p2neg, i64 0, i64 %p2a
  %p1b = select i1 %p1neg, i64 0, i64 %p1
  %under = icmp slt i64 %p2b, %p1b
  %p2c = select i1 %under, i64 %p1b, i64 %p2b
  %over = icmp sgt i64 %p2c, %n
  %p2 = select i1 %over, i64 %n, i64 %p2c
  %l = sub i64 %p2, %p1b
  %l1b = add i64 %l, 1
  %buf = call i8* @malloc(i64 %l1b)
  %src = getelementptr i8, i8* %p, i64 %p1b
  call i8* @memcpy(i8* %buf, i8* %src, i64 %l)
  %end = getelementptr i8, i8* %buf, i64 %l
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %l)
  %rs = call %Slot @t2_box_str(%Str %r)
  ret %Slot %rs
undef:
  call i64 @write(i32 2, i8* getelementptr ([47 x i8], [47 x i8]* @lit_substr_out, i64 0, i64 0), i64 46)
  call void @exit(i32 255)
  unreachable
}
; index(s, t, pos): the first place at or after pos (clamped into the string) t is, or -1.
define internal i64 @t2_index(%Str %s, %Str %t, i64 %pos0) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %q = extractvalue %Str %t, 0
  %m = extractvalue %Str %t, 1
  %pneg = icmp slt i64 %pos0, 0
  %pa = select i1 %pneg, i64 0, i64 %pos0
  %pbig = icmp sgt i64 %pa, %n
  %pos = select i1 %pbig, i64 %n, i64 %pa
  br label %loop
loop:
  %i = phi i64 [ %pos, %entry ], [ %i1, %next ]
  %e = add i64 %i, %m
  %fits = icmp sle i64 %e, %n
  br i1 %fits, label %cmp, label %none
cmp:
  %at = getelementptr i8, i8* %p, i64 %i
  %c = call i32 @memcmp(i8* %at, i8* %q, i64 %m)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
define internal void @t2_exit(i64 %v) {
  %c = trunc i64 %v to i32
  call void @exit(i32 %c)
  unreachable
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
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
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
; t2_slot_int(x) / t2_slot_rand(x): perl's int and rand of a slot.
declare double @llvm.trunc.f64(double)
declare i32 @rand()
define internal %Slot @t2_slot_int(%Slot %s) {
  %d = call double @t2_slot_num(%Slot %s)
  %t = call double @llvm.trunc.f64(double %d)
  %r = call %Slot @t2_box_num(double %t)
  ret %Slot %r
}
define internal %Slot @t2_slot_rand(%Slot %s) {
  %x = call double @t2_slot_num(%Slot %s)
  %z = fcmp oeq double %x, 0.0
  %m = select i1 %z, double 1.0, double %x
  %r = call i32 @rand()
  %rd = sitofp i32 %r to double
  %u = fdiv double %rd, 2147483648.0
  %v = fmul double %u, %m
  %b = call %Slot @t2_box_num(double %v)
  ret %Slot %b
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
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret double 0.0
ok:
  %q = fdiv double %x, %y
  ret double %q
}
define internal i64 @t2_mod(i64 %x, i64 %y, i8* %msg, i64 %n) {
entry:
  %z = icmp eq i64 %y, 0
  br i1 %z, label %die, label %ok
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret i64 0
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
  ; (perl's /^[a-zA-Z]*[0-9]*$/: no letters at all is magic too -- "007"++ is "008")
  %g0 = icmp uge i8 %c0, 48
  %e0 = icmp ule i8 %c0, 57
  %d0 = and i1 %g0, %e0
  %ok0 = or i1 %l0, %d0
  br i1 %ok0, label %loop, label %no
loop:
  %i = phi i64 [ 1, %first ], [ %i1, %next ]
  %digits = phi i1 [ %d0, %first ], [ %d1, %next ]
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
  %f0 = icmp eq i8 %f, 48
  %lead0 = select i1 %fA, i8 65, i8 97
  %lead = select i1 %f0, i8 49, i8 %lead0   ; (a digit's is 1: "99"++ is "100")
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
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
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
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
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
  %c = call %Slot @t2_class_of(%Slot %s)
  br label %h
h:
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %fmt
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  %rxn = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %rxc = call i64 @t2_strcmp(%Str %cn, %Str %rxn)
  %isrx = icmp eq i64 %rxc, 0
  br i1 %isrx, label %qr, label %obj2
qr:
  %pk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_qrpat, i64 0, i64 0), i64 7)
  %pv = call %Slot @t2_hget(%Slot %s, %Str %pk)
  %ps = call %Str @t2_slot_str(%Slot %pv)
  ret %Str %ps
obj2:
  %eq = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_eqhash, i64 0, i64 0), i64 1)
  %bt = call %Str @t2_basetype(%Slot %s)
  %eh = call %Str @t2_concat(%Str %eq, %Str %bt)
  %ck = call %Str @t2_concat(%Str %kind, %Str %eh)
  br label %fmt
fmt:
  %pre = phi %Str [ %kind, %h ], [ %ck, %obj2 ]
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
; (field 4: the class a bless gave it, undef until -- an array's or a hash's)
%Array = type { i64, i64, %Slot*, %Meta*, %Slot }
declare i8* @realloc(i8*, i64)
declare i8* @memmove(i8*, i8*, i64)
define internal %Array* @t2_new_array() {
  %m = call i8* @malloc(i64 48)
  %a = bitcast i8* %m to %Array*
  store %Array zeroinitializer, %Array* %a
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_default, %Meta** %mp
  ret %Array* %a
}
define internal i64 @t2_alen_d(%Array* %a) {
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
define internal void @t2_apush_d(%Array* %a, %Slot %v) {
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %n
  store %Slot %v, %Slot* %p
  ret void
}
; t2_aunshift(a, v): v in front, every element one further on.
define internal void @t2_aunshift_d(%Array* %a, %Slot %v) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %from = getelementptr %Slot, %Slot* %els, i64 %im
  %e = load %Slot, %Slot* %from
  %to = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot %e, %Slot* %to
  br label %loop
done:
  store %Slot %v, %Slot* %els
  ret void
}
define internal %Slot @t2_aget_d(%Array* %a, i64 %i) {
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
define internal void @t2_aset_d(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn) {
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
define internal %Slot @t2_apop_d(%Array* %a) {
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
define internal %Slot @t2_ashift_d(%Array* %a) {
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
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
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
@lit_code = private unnamed_addr constant [5 x i8] c"CODE\00"
@lit_scalar = private unnamed_addr constant [7 x i8] c"SCALAR\00"
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
@msg_blessnot = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: a bless of what is not a hash or array reference\0A\00"
define internal %Slot @t2_bless(%Slot %h, %Str %c) {
entry:
  %t = extractvalue %Slot %h, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %set, label %other
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %bad
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %h)
  %tcs = call %Slot @t2_box_str(%Str %c)
  call void @t2_hset(%Slot %tb, %Str %k, %Slot %tcs)
  ret %Slot %h
bad:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_blessnot, i64 0, i64 0), i64 77)
  unreachable
set:
  %cs = call %Slot @t2_box_str(%Str %c)
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  store %Slot %cs, %Slot* %cp
  ret %Slot %h
}
; t2_class_of(s) -> the class a hash or array reference was blessed into
; (a boxed Str), else undef.
define internal %Slot @t2_class_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %agg, label %other
agg:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  %c = load %Slot, %Slot* %cp
  ret %Slot %c
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %none
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %s)
  %tc = call %Slot @t2_hget(%Slot %tb, %Str %k)
  ret %Slot %tc
none:
  ret %Slot zeroinitializer
}
; A SCALAR OR CODE REFERENCE'S CLASS: no header to hold it, so a table keyed
; by its address (t2_addr_key).
@t2_blessings = internal global %Slot zeroinitializer
define internal %Str @t2_addr_key(%Slot %s) {
  %a = extractvalue %Slot %s, 1
  %b = call %Slot @t2_box_i64(i64 %a)
  %k = call %Str @t2_slot_str(%Slot %b)
  ret %Str %k
}
; A SCALAR REFERENCE (`\$x`) is a %Slot of tag 9 whose payload is the
; variable's heap cell.
define internal %Slot @t2_sref(%Slot* %c) {
  %i = ptrtoint %Slot* %c to i64
  %s = call %Slot @t2_slot(i8 9, i64 %i)
  ret %Slot %s
}
@lit_sc_undef = private unnamed_addr constant [51 x i8] c"Can't use an undefined value as a SCALAR reference\00"
@lit_sc_not = private unnamed_addr constant [23 x i8] c"Not a SCALAR reference\00"
@lit_sc_str0 = private unnamed_addr constant [20 x i8] c"Can't use string (\22\00"
@lit_sc_str1 = private unnamed_addr constant [46 x i8] c"\22) as a SCALAR ref while \22strict refs\22 in use\00"
@lit_sc_more = private unnamed_addr constant [5 x i8] c"\22...\00"
@msg_symref = private unnamed_addr constant [65 x i8] c"chalk: refused at run time: a string as a reference (no strict)\0A\00"
; t2_sderef_cell(r, strict, at, n) -> the cell r refers to; null after
; perl's die (what r is named), a stop for a name without strict refs.
define internal %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  switch i8 %t, label %str [ i8 9, label %ok
                             i8 0, label %undef
                             i8 5, label %not
                             i8 6, label %not
                             i8 7, label %not
                             i8 8, label %not ]
ok:
  %v = extractvalue %Slot %r, 1
  %c = inttoptr i64 %v to %Slot*
  ret %Slot* %c
undef:
  br i1 %strict, label %undefdie, label %none
undefdie:
  %u = call %Str @t2_str(i8* getelementptr ([51 x i8], [51 x i8]* @lit_sc_undef, i64 0, i64 0), i64 50)
  br label %die
not:
  %nm = call %Str @t2_str(i8* getelementptr ([23 x i8], [23 x i8]* @lit_sc_not, i64 0, i64 0), i64 22)
  br label %die
str:
  br i1 %strict, label %strdie, label %sym
sym:
  %nm0 = call %Str @t2_slot_str(%Slot %r)
  %pks = call %Str @t2_str(i8* %pk, i64 %pkn)
  %cell = call %Slot* @t2_symref(%Str %nm0, %Str %pks)
  ret %Slot* %cell
strdie:
  %sv = call %Str @t2_slot_str(%Slot %r)
  %sl = extractvalue %Str %sv, 1
  %long = icmp ugt i64 %sl, 32
  %cut = select i1 %long, i64 32, i64 %sl
  %sp = extractvalue %Str %sv, 0
  %head = call %Str @t2_str(i8* %sp, i64 %cut)
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %head)
  %more = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_sc_more, i64 0, i64 0), i64 4)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %more)
  %p1b = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 0)
  %tail0 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 0), i64 45)
  %tail1 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 1), i64 44)
  %lp = select i1 %long, %Str %p2, %Str %p1
  %tl = select i1 %long, %Str %tail1, %Str %tail0
  %sm = call %Str @t2_concat(%Str %lp, %Str %tl)
  br label %die
die:
  %m0 = phi %Str [ %u, %undefdie ], [ %nm, %not ], [ %sm, %strdie ]
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  ret %Slot* null
none:
  ret %Slot* null
}
; THE PROGRAM'S PACKAGE SCALARS BY NAME ("main::x" -> a SCALAR reference to its
; global), for a string used as a reference without strict refs; one no one
; named is made on first use, as perl's. t2_symtab_init (the printer's) fills it.
@t2_symtab = internal global %Slot zeroinitializer
@t2_symtab_ready = internal global i1 0
@lit_colons = private unnamed_addr constant [3 x i8] c"::\00"
@lit_mainpk = private unnamed_addr constant [5 x i8] c"main\00"
define internal void @t2_symtab_add(i8* %p, i64 %n, %Slot* %g) {
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %k = call %Str @t2_str(i8* %p, i64 %n)
  %s = call %Slot @t2_sref(%Slot* %g)
  call void @t2_hset(%Slot %t, %Str %k, %Slot %s)
  ret void
}
; t2_has_colons(s) -> whether s holds "::"
define internal i1 @t2_has_colons(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %last
  br i1 %more, label %look, label %no
look:
  %a = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %a
  %i2 = add i64 %i, 1
  %b = getelementptr i8, i8* %p, i64 %i2
  %d = load i8, i8* %b
  %c1 = icmp eq i8 %c, 58
  %d1 = icmp eq i8 %d, 58
  %both = and i1 %c1, %d1
  br i1 %both, label %yes, label %next
next:
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal %Slot* @t2_symref(%Str %name, %Str %pk) {
entry:
  %ready = load i1, i1* @t2_symtab_ready
  br i1 %ready, label %go, label %init
init:
  store i1 1, i1* @t2_symtab_ready
  call void @t2_symtab_init()
  br label %go
go:
  %q = call i1 @t2_has_colons(%Str %name)
  br i1 %q, label %qual, label %unq
qual:
  %np = extractvalue %Str %name, 0
  %c0 = load i8, i8* %np
  %lead = icmp eq i8 %c0, 58
  br i1 %lead, label %lead_main, label %have
lead_main:
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_mainpk, i64 0, i64 0), i64 4)
  %ml = call %Str @t2_concat(%Str %m, %Str %name)
  br label %have
unq:
  %cc = call %Str @t2_str(i8* getelementptr ([3 x i8], [3 x i8]* @lit_colons, i64 0, i64 0), i64 2)
  %p1 = call %Str @t2_concat(%Str %pk, %Str %cc)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %name)
  br label %have
have:
  %full = phi %Str [ %name, %qual ], [ %ml, %lead_main ], [ %p2, %unq ]
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %s = call %Slot @t2_hget(%Slot %t, %Str %full)
  %st = extractvalue %Slot %s, 0
  %found = icmp eq i8 %st, 9
  br i1 %found, label %old, label %new
old:
  %v = extractvalue %Slot %s, 1
  %oc = inttoptr i64 %v to %Slot*
  ret %Slot* %oc
new:
  %mem = call i8* @malloc(i64 16)
  %nc = bitcast i8* %mem to %Slot*
  store %Slot zeroinitializer, %Slot* %nc
  %ns = call %Slot @t2_sref(%Slot* %nc)
  call void @t2_hset(%Slot %t, %Str %full, %Slot %ns)
  ret %Slot* %nc
}
define internal %Slot @t2_sderef(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %undef, label %load
undef:
  ret %Slot zeroinitializer
load:
  %v = load %Slot, %Slot* %c
  ret %Slot %v
}
@msg_sstore_undef = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a store through an undefined scalar reference\0A\00"
define internal void @t2_sstore(%Slot %r, %Slot %v, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %viv, label %go
viv:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_sstore_undef, i64 0, i64 0), i64 74)
  unreachable
go:
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %done, label %st
st:
  store %Slot %v, %Slot* %c
  br label %done
done:
  ret void
}
; t2_reftype(s) -> perl's ref(): an object's class, HASH, or "" for no reference.
define internal %Str @t2_reftype(%Slot %s) {
entry:
  %c = call %Slot @t2_class_of(%Slot %s)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %plain
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  ret %Str %cn
plain:
  %b = call %Str @t2_basetype(%Slot %s)
  ret %Str %b
}
; t2_basetype(s) -> what s refers to, blessed or not: HASH, ARRAY, CODE,
; SCALAR, or "" for no reference.
define internal %Str @t2_basetype(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %none [ i8 5, label %hash
                              i8 6, label %arr
                              i8 8, label %code
                              i8 9, label %sc ]
hash:
  %h = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 4)
  ret %Str %h
arr:
  %a = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_array, i64 0, i64 0), i64 5)
  ret %Str %a
code:
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_code, i64 0, i64 0), i64 4)
  ret %Str %k
sc:
  %q = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_scalar, i64 0, i64 0), i64 6)
  ret %Str %q
none:
  %e = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 0)
  ret %Str %e
}
@t2_stashes = internal global %Slot zeroinitializer
@lit_isa = private unnamed_addr constant [5 x i8] c"@ISA\00"
@lit_cm = private unnamed_addr constant [20 x i8] c"Can't call method \22\00"
@lit_undefv = private unnamed_addr constant [24 x i8] c"\22 on an undefined value\00"
@lit_unbl = private unnamed_addr constant [25 x i8] c"\22 on unblessed reference\00"
@lit_nopkg = private unnamed_addr constant [40 x i8] c"\22 without a package or object reference\00"
@lit_lom = private unnamed_addr constant [29 x i8] c"Can't locate object method \22\00"
@lit_via = private unnamed_addr constant [16 x i8] c"\22 via package \22\00"
@lit_q = private unnamed_addr constant [2 x i8] c"\22\00"
@lit_forgot = private unnamed_addr constant [32 x i8] c"\22 (perhaps you forgot to load \22\00"
@lit_qp = private unnamed_addr constant [4 x i8] c"\22?)\00"
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
@t2_want = internal global i1 0   ; the caller's context: 1 a list
@t2_argc = internal global i32 0
@t2_argvp = internal global i8** null
@t2_ARGV = internal global %Array* null
define internal void @t2_save_args(i32 %c, i8** %v) {
  store i32 %c, i32* @t2_argc
  store i8** %v, i8*** @t2_argvp
  ; perl's $@ starts "" (defined)
  %e = call %Str @t2_str(i8* null, i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  store %Slot %es, %Slot* @t2_err
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
; t2_aderef_r(s) -> for an element read through it: the array s refers to; an
; undef s reads as an empty one (perl's makes it), anything else stops.
define internal %Array* @t2_aderef_r(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  %e = call %Array* @t2_new_array()
  ret %Array* %e
go:
  %a = call %Array* @t2_aderef(%Slot %s)
  ret %Array* %a
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
@msg_oneof = private unnamed_addr constant [88 x i8] c"chalk: refused at run time: a list of other than one value passed as one argument (T2)\0A\00"
; t2_one_of(a) -> a's one element; a stop when it has another number.
define internal %Slot @t2_one_of(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %one = icmp eq i64 %n, 1
  br i1 %one, label %ok, label %bad
ok:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  ret %Slot %v
bad:
  call void @t2_stop(i8* getelementptr ([88 x i8], [88 x i8]* @msg_oneof, i64 0, i64 0), i64 87)
  unreachable
}
; t2_list_of(v, want) -> in a list context a reference to a list of v; else v.
define internal %Slot @t2_list_of(%Slot %v, i1 %w) {
entry:
  br i1 %w, label %list, label %one
list:
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot %v)
  %r = call %Slot @t2_aref(%Array* %a)
  ret %Slot %r
one:
  ret %Slot %v
}
; CLOSURES: a captured variable's storage on the heap; a code value (tag 8)
; points at {its function, its cells}.
define internal %Slot* @t2_cell_new() {
  %m = call i8* @malloc(i64 16)
  %c = bitcast i8* %m to %Slot*
  store %Slot zeroinitializer, %Slot* %c
  ret %Slot* %c
}
define internal %Slot** @t2_env_new(i64 %n) {
  %b = mul i64 %n, 8
  %b1 = add i64 %b, 8
  %m = call i8* @malloc(i64 %b1)
  %e = bitcast i8* %m to %Slot**
  ret %Slot** %e
}
define internal void @t2_env_set(%Slot** %e, i64 %i, %Slot* %c) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  store %Slot* %c, %Slot** %p
  ret void
}
define internal %Slot* @t2_env_get(%Slot** %e, i64 %i) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  %c = load %Slot*, %Slot** %p
  ret %Slot* %c
}
define internal %Slot @t2_code_new(i8* %f, %Slot** %e) {
  %m = call i8* @malloc(i64 16)
  %pf = bitcast i8* %m to i8**
  store i8* %f, i8** %pf
  %pe0 = getelementptr i8*, i8** %pf, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  store %Slot** %e, %Slot*** %pe
  %i = ptrtoint i8* %m to i64
  %s = call %Slot @t2_slot(i8 8, i64 %i)
  ret %Slot %s
}
@msg_notcode = private unnamed_addr constant [69 x i8] c"chalk: refused at run time: a call of what is not a code value (T2)\0A\00"
define internal i8** @t2_code_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 8
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([69 x i8], [69 x i8]* @msg_notcode, i64 0, i64 0), i64 68)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to i8**
  ret i8** %p
}
define internal i8* @t2_code_fn(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %f = load i8*, i8** %p
  ret i8* %f
}
define internal %Slot** @t2_code_env(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %pe0 = getelementptr i8*, i8** %p, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  %e = load %Slot**, %Slot*** %pe
  ret %Slot** %e
}
; t2_die(msg, at): perl's uncaught die -- the message to STDERR, `at` (" at
; FILE line N.\n") after it unless it ends in a newline; exit 255.
@lit_died = private unnamed_addr constant [5 x i8] c"Died\00"
define internal %Str @t2_die_msg(%Str %m, %Str %at) {
entry:
  %n = extractvalue %Str %m, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %died, label %last
died:
  ; die "" is "Died at FILE line N."
  %dm = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_died, i64 0, i64 0), i64 4)
  %dr = call %Str @t2_concat(%Str %dm, %Str %at)
  ret %Str %dr
last:
  %p = extractvalue %Str %m, 0
  %li = sub i64 %n, 1
  %lp = getelementptr i8, i8* %p, i64 %li
  %lc = load i8, i8* %lp
  %nl = icmp eq i8 %lc, 10
  br i1 %nl, label %done, label %addat
addat:
  %r = call %Str @t2_concat(%Str %m, %Str %at)
  ret %Str %r
done:
  ret %Str %m
}
define internal void @t2_die(%Str %m) {
  %p = extractvalue %Str %m, 0
  %n = extractvalue %Str %m, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  call void @exit(i32 255)
  unreachable
}
; EVAL: $@ (@t2_err), the evals open at run time, and the dying flag a die
; in a sub sets for its callers to unwind by.
@t2_err = internal global %Slot zeroinitializer
@t2_eval_depth = internal global i64 0
@t2_dying = internal global i1 0
define internal void @t2_set_err(%Str %m) {
  %s = call %Slot @t2_box_str(%Str %m)
  store %Slot %s, %Slot* @t2_err
  ret void
}
define internal void @t2_eval_enter() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = add i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
define internal void @t2_eval_leave() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = sub i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
define internal void @t2_die_unwind(%Str %m) {
entry:
  %d = load i64, i64* @t2_eval_depth
  %open = icmp sgt i64 %d, 0
  br i1 %open, label %catch, label %exit
catch:
  call void @t2_set_err(%Str %m)
  store i1 1, i1* @t2_dying
  ret void
exit:
  call void @t2_die(%Str %m)
  unreachable
}
define internal void @t2_apush_if(%Array* %a, %Slot %v, i1 %c) {
entry:
  br i1 %c, label %push, label %done
push:
  call void @t2_apush(%Array* %a, %Slot %v)
  br label %done
done:
  ret void
}
define internal void @t2_aappend_d(%Array* %d, %Array* %s) {
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
@msg_caseascii = private unnamed_addr constant [71 x i8] c"chalk: refused at run time: a case change of a string past ASCII (T2)\0A\00"
; t2_strcase(s, mode) -> s in ASCII case: 0 uc, 1 lc, 2 ucfirst, 3 lcfirst.
define internal %Str @t2_strcase(%Str %s, i64 %mode) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %cap = add i64 %n, 1
  %buf = call i8* @malloc(i64 %cap)
  %up = icmp eq i64 %mode, 0
  %up1 = icmp eq i64 %mode, 2
  %toup = or i1 %up, %up1
  %first = icmp sge i64 %mode, 2
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %put ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %sp
  ; A BYTE PAST ASCII: perl's case of it depends on how it was read -- a stop.
  %high = icmp slt i8 %c, 0
  br i1 %high, label %past, label %ascii
past:
  call void @t2_stop(i8* getelementptr ([71 x i8], [71 x i8]* @msg_caseascii, i64 0, i64 0), i64 70)
  unreachable
ascii:
  %notfirst = icmp ne i64 %i, 0
  %keep = and i1 %first, %notfirst
  br i1 %keep, label %put0, label %conv
conv:
  br i1 %toup, label %upper, label %lower
upper:
  %isl = icmp uge i8 %c, 97
  %isl2 = icmp ule i8 %c, 122
  %lw = and i1 %isl, %isl2
  %cu = sub i8 %c, 32
  %ru = select i1 %lw, i8 %cu, i8 %c
  br label %put
lower:
  %isu = icmp uge i8 %c, 65
  %isu2 = icmp ule i8 %c, 90
  %uw = and i1 %isu, %isu2
  %cl = add i8 %c, 32
  %rl = select i1 %uw, i8 %cl, i8 %c
  br label %put
put0:
  br label %put
put:
  %r = phi i8 [ %ru, %upper ], [ %rl, %lower ], [ %c, %put0 ]
  %dp = getelementptr i8, i8* %buf, i64 %i
  store i8 %r, i8* %dp
  %i2 = add i64 %i, 1
  br label %loop
done:
  %out = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %out
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
; t2_mop_isa_arr(class) -> class's @ISA, the array lookup walks; made empty
; (and stored) when the class has none yet.
define internal %Array* @t2_mop_isa_arr(%Str %c) {
entry:
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %ok, label %make
ok:
  %iv = extractvalue %Slot %isa, 1
  %a = inttoptr i64 %iv to %Array*
  ret %Array* %a
make:
  %n = call %Array* @t2_new_array()
  call void @t2_mop_isa_set(%Str %c, %Array* %n)
  ret %Array* %n
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
; t2_mfind1(class, m, skip) -> m's code in class (unless skip) or, depth first,
; its @ISA; null.
define internal i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %own, label %none
own:
  br i1 %skip, label %parents, label %look
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
  %r = call i8* @t2_mfind1(%Str %pn, %Str %m, i1 0)
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
; UNIVERSAL: perl's stash at the root of every method lookup, holding isa,
; can, DOES and VERSION. t2_universal_setup makes it.
@lit_universal = private unnamed_addr constant [10 x i8] c"UNIVERSAL\00"
@lit_u_isa = private unnamed_addr constant [4 x i8] c"isa\00"
@lit_u_can = private unnamed_addr constant [4 x i8] c"can\00"
@lit_u_does = private unnamed_addr constant [5 x i8] c"DOES\00"
define internal %Str @t2_universal_key() {
  %k = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_universal, i64 0, i64 0), i64 9)
  ret %Str %k
}
define internal void @t2_universal_setup() {
  %u = call %Str @t2_universal_key()
  call void @t2_mop_class(%Str %u)
  %i = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_isa, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %i, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %c = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_can, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %c, i8* bitcast (%Slot (%Array*)* @t2_u_can_w to i8*))
  %d = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_u_does, i64 0, i64 0), i64 4)
  call void @t2_mop_def(%Str %u, %Str %d, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %v = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_vname, i64 0, i64 0), i64 7)
  call void @t2_mop_def(%Str %u, %Str %v, i8* bitcast (%Slot (%Array*)* @t2_u_version_w to i8*))
  ret void
}
; t2_mfind_u(class, m, skip) -> as t2_mfind1, and failing that UNIVERSAL's.
define internal i8* @t2_mfind_u(%Str %c, %Str %m, i1 %skip) {
entry:
  %r = call i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %root
ok:
  ret i8* %r
root:
  %u = call %Str @t2_universal_key()
  %ru = call i8* @t2_mfind1(%Str %u, %Str %m, i1 0)
  ret i8* %ru
}
; t2_inv_class(inv) -> an object's class, or a class name (t2_mresolve checked it).
define internal %Str @t2_inv_class(%Slot %inv) {
entry:
  %t = extractvalue %Slot %inv, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %isref = or i1 %ish, %isa
  br i1 %isref, label %ref, label %name
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %cn = call %Str @t2_slot_str(%Slot %cl)
  ret %Str %cn
name:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  ret %Str %nn
}
; t2_isa_walk(class, target) -> class is target or, depth first, inherits it.
define internal i1 @t2_isa_walk(%Str %c, %Str %target) {
entry:
  %d = call i64 @t2_strcmp(%Str %c, %Str %target)
  %same = icmp eq i64 %d, 0
  br i1 %same, label %yes, label %stash
stash:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %parents, label %no
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %no
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %no
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i1 @t2_isa_walk(%Str %pn, %Str %target)
  br i1 %r, label %yes, label %next
next:
  %i2 = add i64 %i, 1
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
; t2_bool(b) -> perl's true (1) or false (the empty string).
define internal %Slot @t2_bool(i1 %b) {
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
; UNIVERSAL::isa (and DOES): method isa ($other) { $self isa $other }
define internal %Slot @t2_u_isa_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %o = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %os = call %Str @t2_slot_str(%Slot %o)
  %b = call i1 @t2_isa_walk(%Str %c, %Str %os)
  %r = call %Slot @t2_bool(i1 %b)
  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)
  ret %Slot %rn
}
; t2_qr_match(re, subject) -> what a qr value's matcher gives: [start, end,
; groups...] or undef. A value of no class Regexp is a pattern built at run
; time: there is no graph of it -- stopped.
@lit_regexp = private unnamed_addr constant [7 x i8] c"Regexp\00"
@lit_matcher = private unnamed_addr constant [8 x i8] c"matcher\00"
@lit_qrpat = private unnamed_addr constant [8 x i8] c"pattern\00"
@msg_qr_runtime = private unnamed_addr constant [63 x i8] c"chalk: refused at run time: a regex pattern built at run time\0A\00"
define internal %Slot @t2_qr_match(%Slot %re, %Slot %subj) {
entry:
  %c = call %Slot @t2_class_of(%Slot %re)
  %cs = call %Str @t2_slot_str(%Slot %c)
  %rx = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %cmp = call i64 @t2_strcmp(%Str %cs, %Str %rx)
  %is = icmp eq i64 %cmp, 0
  br i1 %is, label %call, label %stop
stop:
  call void @t2_stop(i8* getelementptr ([63 x i8], [63 x i8]* @msg_qr_runtime, i64 0, i64 0), i64 62)
  unreachable
call:
  %mk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_matcher, i64 0, i64 0), i64 7)
  %code = call %Slot @t2_hget(%Slot %re, %Str %mk)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %subj)
  store i1 0, i1* @t2_want
  %e = call %Slot** @t2_code_env(%Slot %code)
  %p = call i8* @t2_code_fn(%Slot %code)
  %f = bitcast i8* %p to %Slot (%Array*, %Slot**)*
  %r = call %Slot %f(%Array* %args, %Slot** %e)
  ret %Slot %r
}
; t2_pos_update(r, pos, z, keep): after an m//g -- matched ([start, end, ..]):
; pos is end, z end where the match was empty (else none); failed: both reset,
; unless /c (keep).
define internal void @t2_pos_update(%Slot %r, %Slot* %pc, %Slot* %zc, i1 %keep) {
entry:
  %t = extractvalue %Slot %r, 0
  %ok = icmp ne i8 %t, 0
  br i1 %ok, label %hit, label %miss
hit:
  %a = call %Array* @t2_aderef(%Slot %r)
  %s = call %Slot @t2_aget(%Array* %a, i64 0)
  %e = call %Slot @t2_aget(%Array* %a, i64 1)
  store %Slot %e, %Slot* %pc
  %si = extractvalue %Slot %s, 1
  %ei = extractvalue %Slot %e, 1
  %emp = icmp eq i64 %si, %ei
  %zz = select i1 %emp, %Slot %e, %Slot zeroinitializer
  store %Slot %zz, %Slot* %zc
  ret void
miss:
  br i1 %keep, label %done, label %reset
reset:
  store %Slot zeroinitializer, %Slot* %pc
  store %Slot zeroinitializer, %Slot* %zc
  br label %done
done:
  ret void
}
; t2_stash_tramp(args, env): a stash method called as a code value -- its
; code rides in env.
define internal %Slot @t2_stash_tramp(%Array* %args, %Slot** %env) {
entry:
  %f = bitcast %Slot** %env to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  ret %Slot %r
}
; t2_unloaded_w: an unloaded sub's stash entry (can() finds it by name). Never
; called: a program that may call what can() hands back is refused.
define internal %Slot @t2_unloaded_w(%Array* %args) {
entry:
  unreachable
}
; UNIVERSAL::can: the method as a code value, or undef. (A list context gets a
; list, as a sub's wrapper gives: "[", A->can("x"), "]" read past its end.)
define internal %Slot @t2_u_can_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %m = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %ms = call %Str @t2_slot_str(%Slot %m)
  %fp = call i8* @t2_mfind_u(%Str %c, %Str %ms, i1 0)
  %none = icmp eq i8* %fp, null
  br i1 %none, label %undef, label %code
undef:
  %un = call %Slot @t2_list_of(%Slot zeroinitializer, i1 %w)
  ret %Slot %un
code:
  %e = bitcast i8* %fp to %Slot**
  %cv = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* @t2_stash_tramp to i8*), %Slot** %e)
  %cn = call %Slot @t2_list_of(%Slot %cv, i1 %w)
  ret %Slot %cn
}
@lit_vkey = private unnamed_addr constant [9 x i8] c"$VERSION\00"
@lit_vname = private unnamed_addr constant [8 x i8] c"VERSION\00"
@lit_vver = private unnamed_addr constant [10 x i8] c" version \00"
@lit_vreq = private unnamed_addr constant [33 x i8] c" required--this is only version \00"
@lit_vnodef = private unnamed_addr constant [19 x i8] c" does not define $\00"
@lit_vnodef2 = private unnamed_addr constant [32 x i8] c"::VERSION--version check failed\00"
@lit_vneither = private unnamed_addr constant [59 x i8] c" defines neither package nor VERSION--version check failed\00"
; the call site t2_mresolve last saw (" at FILE line N.\n"): a UNIVERSAL method's die names it
@t2_call_at = internal global %Str zeroinitializer
; t2_mop_var(class, global): class's $VERSION is that global (VERSION reads it by the class's name).
define internal void @t2_mop_var(%Str %c, %Slot* %g) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %gi = ptrtoint %Slot* %g to i64
  %gs = call %Slot @t2_slot(i8 1, i64 %gi)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %gs)
  ret void
}
; t2_vnum(version) -> perl's number for it: decimal ("1.10" is 1.1), or dotted
; ("1.2.3", "v1.2": each part a thousandth of the one before).
define internal double @t2_vnum(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %some = icmp sgt i64 %n, 0
  br i1 %some, label %first, label %decimal
first:
  %c0 = load i8, i8* %p
  %isv = icmp eq i8 %c0, 118
  br i1 %isv, label %dotted, label %count
count:
  %ci = phi i64 [ 0, %first ], [ %ci2, %cstep ]
  %dots = phi i64 [ 0, %first ], [ %dots2, %cstep ]
  %cmore = icmp slt i64 %ci, %n
  br i1 %cmore, label %cstep, label %counted
cstep:
  %cp = getelementptr i8, i8* %p, i64 %ci
  %cc = load i8, i8* %cp
  %isdot = icmp eq i8 %cc, 46
  %inc = zext i1 %isdot to i64
  %dots2 = add i64 %dots, %inc
  %ci2 = add i64 %ci, 1
  br label %count
counted:
  %many = icmp sgt i64 %dots, 1
  br i1 %many, label %dotted, label %decimal
decimal:
  %sl = call %Slot @t2_box_str(%Str %s)
  %d = call double @t2_slot_num(%Slot %sl)
  ret double %d
dotted:
  %st0 = load i8, i8* %p
  %lead = icmp eq i8 %st0, 118
  %i0 = zext i1 %lead to i64
  br label %loop
loop:
  %i = phi i64 [ %i0, %dotted ], [ %inext, %digit ], [ %inext, %dot ]
  %part = phi i64 [ 0, %dotted ], [ %part2, %digit ], [ 0, %dot ]
  %acc = phi double [ 0.0, %dotted ], [ %acc, %digit ], [ %acc2, %dot ]
  %scale = phi double [ 1.0, %dotted ], [ %scale, %digit ], [ %scale2, %dot ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %ch, label %end
ch:
  %chp = getelementptr i8, i8* %p, i64 %i
  %chv = load i8, i8* %chp
  %inext = add i64 %i, 1
  %isd = icmp eq i8 %chv, 46
  br i1 %isd, label %dot, label %digit
dot:
  %pf = sitofp i64 %part to double
  %add = fmul double %pf, %scale
  %acc2 = fadd double %acc, %add
  %scale2 = fdiv double %scale, 1000.0
  br label %loop
digit:
  %dv = zext i8 %chv to i64
  %dd = sub i64 %dv, 48
  %p10 = mul i64 %part, 10
  %part2 = add i64 %p10, %dd
  br label %loop
end:
  %pf2 = sitofp i64 %part to double
  %add2 = fmul double %pf2, %scale
  %r = fadd double %acc, %add2
  ret double %r
}
; UNIVERSAL::VERSION: the class's own $VERSION; with a wanted version,
; perl's check, dying as perl does where it fails.
define internal %Slot @t2_u_version_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %look, label %check
look:
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %g = call %Slot @t2_hget(%Slot %s, %Str %k)
  %gt = extractvalue %Slot %g, 0
  %hasv = icmp eq i8 %gt, 1
  br i1 %hasv, label %load, label %check
load:
  %gi = extractvalue %Slot %g, 1
  %gp = inttoptr i64 %gi to %Slot*
  %vl = load %Slot, %Slot* %gp
  %vt = extractvalue %Slot %vl, 0
  %vdef = icmp ne i8 %vt, 0
  %vk = select i1 %vdef, i8 2, i8 1
  br label %check
check:
  %v = phi %Slot [ zeroinitializer, %entry ], [ zeroinitializer, %look ], [ %vl, %load ]
  %kind = phi i8 [ 0, %entry ], [ 1, %look ], [ %vk, %load ]
  %na = call i64 @t2_alen(%Array* %args)
  %req = icmp sgt i64 %na, 1
  br i1 %req, label %need, label %give
give:
  %rn = call %Slot @t2_list_of(%Slot %v, i1 %w)
  ret %Slot %rn
need:
  %want = call %Slot @t2_aget(%Array* %args, i64 1)
  %rs = call %Str @t2_slot_str(%Slot %want)
  switch i8 %kind, label %cmp [ i8 0, label %neither i8 1, label %nodef ]
cmp:
  %vs = call %Str @t2_slot_str(%Slot %v)
  %vn = call double @t2_vnum(%Str %vs)
  %wn = call double @t2_vnum(%Str %rs)
  %ok = fcmp oge double %vn, %wn
  br i1 %ok, label %give, label %low
low:
  %l0 = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_vver, i64 0, i64 0), i64 9)
  %l1 = call %Str @t2_concat(%Str %c, %Str %l0)
  %l2 = call %Str @t2_concat(%Str %l1, %Str %rs)
  %l3 = call %Str @t2_str(i8* getelementptr ([33 x i8], [33 x i8]* @lit_vreq, i64 0, i64 0), i64 32)
  %l4 = call %Str @t2_concat(%Str %l2, %Str %l3)
  %l5 = call %Str @t2_concat(%Str %l4, %Str %vs)
  br label %die
nodef:
  %n0 = call %Str @t2_str(i8* getelementptr ([19 x i8], [19 x i8]* @lit_vnodef, i64 0, i64 0), i64 18)
  %n1 = call %Str @t2_concat(%Str %c, %Str %n0)
  %n2 = call %Str @t2_concat(%Str %n1, %Str %c)
  %n3 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_vnodef2, i64 0, i64 0), i64 31)
  %n4 = call %Str @t2_concat(%Str %n2, %Str %n3)
  br label %die
neither:
  %e0 = call %Str @t2_str(i8* getelementptr ([59 x i8], [59 x i8]* @lit_vneither, i64 0, i64 0), i64 58)
  %e1 = call %Str @t2_concat(%Str %c, %Str %e0)
  br label %die
die:
  %m = phi %Str [ %l5, %low ], [ %n4, %nodef ], [ %e1, %neither ]
  %at = load %Str, %Str* @t2_call_at
  %full = call %Str @t2_concat(%Str %m, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret %Slot zeroinitializer
}
@lit_tm_fetchsize = private unnamed_addr constant [10 x i8] c"FETCHSIZE\00"
@lit_tm_fetch = private unnamed_addr constant [6 x i8] c"FETCH\00"
@lit_tm_store = private unnamed_addr constant [6 x i8] c"STORE\00"
@lit_tm_push = private unnamed_addr constant [5 x i8] c"PUSH\00"
@lit_tm_pop = private unnamed_addr constant [4 x i8] c"POP\00"
@lit_tm_shift = private unnamed_addr constant [6 x i8] c"SHIFT\00"
@lit_tm_unshift = private unnamed_addr constant [8 x i8] c"UNSHIFT\00"
@lit_tm_exists = private unnamed_addr constant [7 x i8] c"EXISTS\00"
@lit_tm_delete = private unnamed_addr constant [7 x i8] c"DELETE\00"
@lit_tm_firstkey = private unnamed_addr constant [9 x i8] c"FIRSTKEY\00"
@lit_tm_nextkey = private unnamed_addr constant [8 x i8] c"NEXTKEY\00"
@lit_tm_clear = private unnamed_addr constant [6 x i8] c"CLEAR\00"
@lit_tm_tiearray = private unnamed_addr constant [9 x i8] c"TIEARRAY\00"
@lit_tm_tiehash = private unnamed_addr constant [8 x i8] c"TIEHASH\00"
; THE CONTAINER PROTOCOL (perigrin: a tie swaps a container's metaobject).
; Every %Array -- an array, or a hash's pairs -- points at a metaobject:
; a vtable of its operations and a datum (a tie's object). The default's
; entries are the runtime's own functions (t2_aget_d, ...); t2_aget and the
; rest look the operation up there. A tie's entries call the object's
; methods; the other kind's entries stay the default's.
%Meta = type { i8**, %Slot }
@t2_vt_default = internal global [18 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*)
]
@t2_vt_tiearray = internal global [18 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_tie_aget to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_tie_aset to i8*),
  i8* bitcast (i64 (%Array*)* @t2_tie_alen to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_apush to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_apop to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_ashift to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_aunshift to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aappend to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aunshiftl to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*)
]
@t2_vt_tiehash = internal global [18 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hget to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_tie_hset to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_tie_hexists to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hdelete to i8*),
  i8* bitcast (i64 (%Slot)* @t2_tie_hcount to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hkeys to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hvalues to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hpairs to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_tie_hfroma to i8*)
]
@t2_meta_default = internal global %Meta { i8** getelementptr ([18 x i8*], [18 x i8*]* @t2_vt_default, i64 0, i64 0), %Slot zeroinitializer }
; t2_meta(a) -> the metaobject a container points at
define internal %Meta* @t2_meta(%Array* %a) {
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  %m = load %Meta*, %Meta** %mp
  ret %Meta* %m
}
define internal i8* @t2_vt(%Array* %a, i64 %k) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %fp = getelementptr i8*, i8** %vt, i64 %k
  %f = load i8*, i8** %fp
  ret i8* %f
}
define internal %Slot @t2_aget(%Array* %p0, i64 %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 0)
  %fn = bitcast i8* %f to %Slot (%Array*, i64)*
  %r = call %Slot %fn(%Array* %p0, i64 %p1)
  ret %Slot %r
}
define internal void @t2_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 1)
  %fn = bitcast i8* %f to void (%Array*, i64, %Slot, i8*, i64)*
  call void %fn(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4)
  ret void
}
define internal i64 @t2_alen(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 2)
  %fn = bitcast i8* %f to i64 (%Array*)*
  %r = call i64 %fn(%Array* %p0)
  ret i64 %r
}
define internal void @t2_apush(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 3)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal %Slot @t2_apop(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 4)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal %Slot @t2_ashift(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 5)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal void @t2_aunshift(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 6)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal void @t2_aappend(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 7)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
define internal void @t2_aunshiftl(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 8)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
; (a read through undef is undef, as perl's -- which makes the hash; a write
; through one B::SoN spells as the hash made first)
define internal %Slot @t2_hget(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret %Slot zeroinitializer
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 9)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal void @t2_hset(%Slot %p0, %Str %p1, %Slot %p2) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 10)
  %fn = bitcast i8* %f to void (%Slot, %Str, %Slot)*
  call void %fn(%Slot %p0, %Str %p1, %Slot %p2)
  ret void
}
define internal i1 @t2_hexists(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret i1 0
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 11)
  %fn = bitcast i8* %f to i1 (%Slot, %Str)*
  %r = call i1 %fn(%Slot %p0, %Str %p1)
  ret i1 %r
}
define internal %Slot @t2_hdelete(%Slot %p0, %Str %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 12)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal i64 @t2_hcount(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 13)
  %fn = bitcast i8* %f to i64 (%Slot)*
  %r = call i64 %fn(%Slot %p0)
  ret i64 %r
}
define internal %Array* @t2_hkeys(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 14)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hvalues(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 15)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hpairs(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 16)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal void @t2_hfroma(%Slot %p0, %Array* %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 17)
  %fn = bitcast i8* %f to void (%Slot, %Array*)*
  call void %fn(%Slot %p0, %Array* %p1)
  ret void
}
; t2_tie_obj(a) -> the object a tied container's metaobject holds
define internal %Slot @t2_tie_obj(%Array* %a) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  %d = load %Slot, %Slot* %dp
  ret %Slot %d
}
; t2_tie_call(args, name) -> the method name of args[0] called with args, in scalar context
define internal %Slot @t2_tie_call(%Array* %args, %Str %m) {
  %o = call %Slot @t2_aget(%Array* %args, i64 0)
  %e = call %Str @t2_str(i8* null, i64 0)
  %fp = call i8* @t2_mresolve(%Slot %o, %Str %m, %Str %e, %Str %e, i8 0)
  %w = load i1, i1* @t2_want
  store i1 0, i1* @t2_want
  %f = bitcast i8* %fp to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  store i1 %w, i1* @t2_want
  ret %Slot %r
}
define internal i64 @t2_tie_alen(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t0.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t0.args, %Slot %o)
  %t0.m = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_fetchsize, i64 0, i64 0), i64 9)
  %t0 = call %Slot @t2_tie_call(%Array* %t0.args, %Str %t0.m)
  %n = call i64 @t2_slot_i64(%Slot %t0)
  ret i64 %n
}
define internal %Slot @t2_tie_aget(%Array* %p0, i64 %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t1.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t1.args, %Slot %o)
  call void @t2_apush(%Array* %t1.args, %Slot %js)
  %t1.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t1 = call %Slot @t2_tie_call(%Array* %t1.args, %Str %t1.m)
  ret %Slot %t1
}
define internal void @t2_tie_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t2.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t2.args, %Slot %o)
  call void @t2_apush(%Array* %t2.args, %Slot %js)
  call void @t2_apush(%Array* %t2.args, %Slot %p2)
  %t2.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t2 = call %Slot @t2_tie_call(%Array* %t2.args, %Str %t2.m)
  ret void
}
define internal void @t2_tie_apush(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t3.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t3.args, %Slot %o)
  call void @t2_apush(%Array* %t3.args, %Slot %p1)
  %t3.m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %t3 = call %Slot @t2_tie_call(%Array* %t3.args, %Str %t3.m)
  ret void
}
define internal %Slot @t2_tie_apop(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t4.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t4.args, %Slot %o)
  %t4.m = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_tm_pop, i64 0, i64 0), i64 3)
  %t4 = call %Slot @t2_tie_call(%Array* %t4.args, %Str %t4.m)
  ret %Slot %t4
}
define internal %Slot @t2_tie_ashift(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t5.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t5.args, %Slot %o)
  %t5.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_shift, i64 0, i64 0), i64 5)
  %t5 = call %Slot @t2_tie_call(%Array* %t5.args, %Str %t5.m)
  ret %Slot %t5
}
define internal void @t2_tie_aunshift(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t6.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t6.args, %Slot %o)
  call void @t2_apush(%Array* %t6.args, %Slot %p1)
  %t6.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %t6 = call %Slot @t2_tie_call(%Array* %t6.args, %Str %t6.m)
  ret void
}
define internal void @t2_tie_aappend(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal void @t2_tie_aunshiftl(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal %Slot @t2_tie_hget(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t7.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t7.args, %Slot %o)
  call void @t2_apush(%Array* %t7.args, %Slot %ks)
  %t7.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t7 = call %Slot @t2_tie_call(%Array* %t7.args, %Str %t7.m)
  ret %Slot %t7
}
define internal void @t2_tie_hset(%Slot %p0, %Str %p1, %Slot %p2) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t8.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t8.args, %Slot %o)
  call void @t2_apush(%Array* %t8.args, %Slot %ks)
  call void @t2_apush(%Array* %t8.args, %Slot %p2)
  %t8.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t8 = call %Slot @t2_tie_call(%Array* %t8.args, %Str %t8.m)
  ret void
}
define internal i1 @t2_tie_hexists(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t9.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t9.args, %Slot %o)
  call void @t2_apush(%Array* %t9.args, %Slot %ks)
  %t9.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_exists, i64 0, i64 0), i64 6)
  %t9 = call %Slot @t2_tie_call(%Array* %t9.args, %Str %t9.m)
  %b = call i1 @t2_truth_slot(%Slot %t9)
  ret i1 %b
}
define internal %Slot @t2_tie_hdelete(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t10.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t10.args, %Slot %o)
  call void @t2_apush(%Array* %t10.args, %Slot %ks)
  %t10.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_delete, i64 0, i64 0), i64 6)
  %t10 = call %Slot @t2_tie_call(%Array* %t10.args, %Str %t10.m)
  ret %Slot %t10
}
define internal %Array* @t2_tie_hkeys(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_new_array()
  %t11.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t11.args, %Slot %o)
  %t11.m = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_firstkey, i64 0, i64 0), i64 8)
  %t11 = call %Slot @t2_tie_call(%Array* %t11.args, %Str %t11.m)
  br label %loop
loop:
  %k = phi %Slot [ %t11, %entry ], [ %t12, %more ]
  %kt = extractvalue %Slot %k, 0
  %done = icmp eq i8 %kt, 0
  br i1 %done, label %end, label %more
more:
  call void @t2_apush(%Array* %ks, %Slot %k)
  %t12.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t12.args, %Slot %o)
  call void @t2_apush(%Array* %t12.args, %Slot %k)
  %t12.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_nextkey, i64 0, i64 0), i64 7)
  %t12 = call %Slot @t2_tie_call(%Array* %t12.args, %Str %t12.m)
  br label %loop
end:
  ret %Array* %ks
}
define internal i64 @t2_tie_hcount(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  ret i64 %n
}
define internal %Array* @t2_tie_hvalues(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  %t13.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t13.args, %Slot %o)
  call void @t2_apush(%Array* %t13.args, %Slot %k)
  %t13.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t13 = call %Slot @t2_tie_call(%Array* %t13.args, %Str %t13.m)
  call void @t2_apush(%Array* %out, %Slot %t13)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal %Array* @t2_tie_hpairs(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  call void @t2_apush(%Array* %out, %Slot %k)
  %t14.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t14.args, %Slot %o)
  call void @t2_apush(%Array* %t14.args, %Slot %k)
  %t14.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t14 = call %Slot @t2_tie_call(%Array* %t14.args, %Str %t14.m)
  call void @t2_apush(%Array* %out, %Slot %t14)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal void @t2_tie_hfroma(%Slot %p0, %Array* %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t15.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t15.args, %Slot %o)
  %t15.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %t15 = call %Slot @t2_tie_call(%Array* %t15.args, %Str %t15.m)
  %n = call i64 @t2_alen(%Array* %p1)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %p1, i64 %i)
  %i1 = add i64 %i, 1
  %val = call %Slot @t2_aget(%Array* %p1, i64 %i1)
  %t16.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t16.args, %Slot %o)
  call void @t2_apush(%Array* %t16.args, %Slot %k)
  call void @t2_apush(%Array* %t16.args, %Slot %val)
  %t16.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t16 = call %Slot @t2_tie_call(%Array* %t16.args, %Str %t16.m)
  %i2 = add i64 %i, 2
  br label %loop
end:
  ret void
}
; t2_tie(a, vt, class, args, ctor) -> the object ctor (TIEARRAY/TIEHASH) made; a now points at a tie's metaobject holding it
define internal %Slot @t2_tie(%Array* %a, i8** %vt, %Slot %cls, %Array* %rest, %Str %ctor) {
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %cls)
  call void @t2_aappend(%Array* %args, %Array* %rest)
  %o = call %Slot @t2_tie_call(%Array* %args, %Str %ctor)
  %mm = call i8* @malloc(i64 32)
  %m = bitcast i8* %mm to %Meta*
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  store i8** %vt, i8*** %vp
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  store %Slot %o, %Slot* %dp
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* %m, %Meta** %mp
  ret %Slot %o
}
define internal %Slot @t2_tie_array(%Array* %a, %Slot %cls, %Array* %rest) {
  %c = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_tiearray, i64 0, i64 0), i64 8)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([18 x i8*], [18 x i8*]* @t2_vt_tiearray, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
define internal %Slot @t2_tie_hash(%Slot %h, %Slot %cls, %Array* %rest) {
  %a = call %Array* @t2_harr(%Slot %h)
  %c = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_tiehash, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([18 x i8*], [18 x i8*]* @t2_vt_tiehash, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
; t2_tied(a) -> the tie's object, or undef where a has the default metaobject
define internal %Slot @t2_tied(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %no, label %yes
no:
  ret %Slot zeroinitializer
yes:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  ret %Slot %o
}
; t2_untie(a): a back to the default metaobject (its own elements, untouched by the tie)
define internal void @t2_untie(%Array* %a) {
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_default, %Meta** %mp
  ret void
}
define internal void @t2_aunshiftl_d(%Array* %a, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %im)
  call void @t2_aunshift_d(%Array* %a, %Slot %v)
  br label %loop
done:
  ret void
}
define internal %Slot @t2_tied_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %r = call %Slot @t2_tied(%Array* %a)
  ret %Slot %r
}
define internal void @t2_untie_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  call void @t2_untie(%Array* %a)
  ret void
}
; t2_args_from(a, k) -> a fresh array of a's elements from k on (a slurpy's copy).
define internal %Array* @t2_args_from(%Array* %a, i64 %k) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %k, %entry ], [ %i2, %body ]
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
; t2_args_pairs(a, n): a signature's slurpy hash takes pairs -- an odd count
; past n is a stop (perl dies: "Odd name/value argument").
define internal void @t2_args_pairs(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %rest = sub i64 %got, %n
  %odd = and i64 %rest, 1
  %bad = icmp ne i64 %odd, 0
  br i1 %bad, label %stop, label %fine
stop:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_args_min(a, n): a signature's arity -- at least n arguments, else a stop.
define internal void @t2_args_min(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %ok = icmp sge i64 %got, %n
  br i1 %ok, label %fine, label %bad
bad:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_cmp(x, y, num) -> perl's cmp (by string) or <=> (by number): -1, 0, 1.
define internal i64 @t2_cmp(%Slot %x, %Slot %y, i1 %num) {
entry:
  br i1 %num, label %n, label %s
n:
  ; (two Ints compared as integers: past 2**53 a double cannot tell them apart)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %ix = icmp eq i8 %tx, 1
  %iy = icmp eq i8 %ty, 1
  %both = and i1 %ix, %iy
  br i1 %both, label %ints, label %nums
ints:
  %vx = extractvalue %Slot %x, 1
  %vy = extractvalue %Slot %y, 1
  %ilt = icmp slt i64 %vx, %vy
  %igt = icmp sgt i64 %vx, %vy
  %il = select i1 %ilt, i64 -1, i64 0
  %ir = select i1 %igt, i64 1, i64 %il
  ret i64 %ir
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %lt = fcmp olt double %dx, %dy
  %gt = fcmp ogt double %dx, %dy
  %l = select i1 %lt, i64 -1, i64 0
  %r = select i1 %gt, i64 1, i64 %l
  ret i64 %r
s:
  %sx = call %Str @t2_slot_str(%Slot %x)
  %sy = call %Str @t2_slot_str(%Slot %y)
  %c = call i64 @t2_strcmp(%Str %sx, %Str %sy)
  %neg = icmp slt i64 %c, 0
  %pos = icmp sgt i64 %c, 0
  %c1 = select i1 %neg, i64 -1, i64 0
  %c2 = select i1 %pos, i64 1, i64 %c1
  ret i64 %c2
}
; t2_hderef_r(r) -> the hash r holds, read whole; undef an empty hash (perl's
; rvalue %{undef}). What is not a hash stops at its first access.
define internal %Slot @t2_hderef_r(%Slot %r) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %empty, label %as
empty:
  %h = call %Slot @t2_hnew()
  ret %Slot %h
as:
  ret %Slot %r
}
; t2_asort(a, num, desc) -> a new list of a's elements in order (stable, as
; perl's mergesort is).
define internal %Array* @t2_asort(%Array* %a, i1 %num, i1 %desc) {
entry:
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  br label %outer
outer:
  %i = phi i64 [ 1, %entry ], [ %i2, %placed ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %take, label %done
take:
  %v = call %Slot @t2_aget(%Array* %r, i64 %i)
  br label %inner
inner:
  %j = phi i64 [ %i, %take ], [ %jm, %shift ]
  %atstart = icmp eq i64 %j, 0
  br i1 %atstart, label %place, label %look
look:
  %jm = sub i64 %j, 1
  %p = call %Slot @t2_aget(%Array* %r, i64 %jm)
  %c0 = call i64 @t2_cmp(%Slot %p, %Slot %v, i1 %num)
  %cn = sub i64 0, %c0
  %c = select i1 %desc, i64 %cn, i64 %c0
  %after = icmp sgt i64 %c, 0
  br i1 %after, label %shift, label %place
shift:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %p, i8* null, i64 0)
  br label %inner
place:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %v, i8* null, i64 0)
  br label %placed
placed:
  %i2 = add i64 %i, 1
  br label %outer
done:
  ret %Array* %r
}
; t2_asort_by(a, f, ga, gb) -> a new list of a's elements in the order f
; gives: for each pair $a (ga) and $b (gb) are set, f called, and a number
; above 0 puts $a after $b (stable). $a and $b are as they were after.
@t2_cmp_env = internal global %Array* null
define internal %Slot @t2_cmp_env_at(i64 %i) {
  %e = load %Array*, %Array** @t2_cmp_env
  %s = call %Slot @t2_aget(%Array* %e, i64 %i)
  ret %Slot %s
}
@t2_cur_cmp = internal global %Slot ()* null
@t2_cur_ga = internal global %Slot* null
@t2_cur_gb = internal global %Slot* null
; t2_sort_cmp_ab(a, b): the comparator on a pair -- $a and $b set, it called,
; its number given; one that dies leaves the sort (t2_msort_abort).
define double @t2_sort_cmp_ab(%Slot* %a, %Slot* %b) {
entry:
  %ga = load %Slot*, %Slot** @t2_cur_ga
  %gb = load %Slot*, %Slot** @t2_cur_gb
  %va = load %Slot, %Slot* %a
  %vb = load %Slot, %Slot* %b
  store %Slot %va, %Slot* %ga
  store %Slot %vb, %Slot* %gb
  %f = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %c = call %Slot %f()
  %d = load i1, i1* @t2_dying
  br i1 %d, label %die, label %ok
die:
  call void @t2_msort_abort()
  unreachable
ok:
  %n = call double @t2_slot_num(%Slot %c)
  ret double %n
}
; t2_asort_by(a, env, f, ga, gb) -> a new list of a's elements in the order
; f gives, compared as perl's sort compares (pp_sort.c, ported: t2_msort) --
; the same pairs in the same order, so a comparator's effects are perl's.
; $a, $b, the env and the comparator are as they were after.
define internal %Array* @t2_asort_by(%Array* %a, %Array* %env, %Slot ()* %f, %Slot* %ga, %Slot* %gb) {
entry:
  %oe = load %Array*, %Array** @t2_cmp_env
  %oa = load %Slot, %Slot* %ga
  %ob = load %Slot, %Slot* %gb
  %of = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %oga = load %Slot*, %Slot** @t2_cur_ga
  %ogb = load %Slot*, %Slot** @t2_cur_gb
  store %Array* %env, %Array** @t2_cmp_env
  store %Slot ()* %f, %Slot ()** @t2_cur_cmp
  store %Slot* %ga, %Slot** @t2_cur_ga
  store %Slot* %gb, %Slot** @t2_cur_gb
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  %ep = getelementptr %Array, %Array* %r, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %died = call i32 @t2_msort(%Slot* %els, i64 %n)
  store %Slot %oa, %Slot* %ga
  store %Slot %ob, %Slot* %gb
  store %Slot ()* %of, %Slot ()** @t2_cur_cmp
  store %Slot* %oga, %Slot** @t2_cur_ga
  store %Slot* %ogb, %Slot** @t2_cur_gb
  store %Array* %oe, %Array** @t2_cmp_env
  ret %Array* %r
}
; ---- perl's sort, ported to C (pp_sort.c's dynprep and merge) and compiled ----

%struct.off_runs = type { i64, i64 }
%struct.__jmp_buf_tag = type { [8 x i64], i32, %struct.__sigset_t }
%struct.__sigset_t = type { [16 x i64] }
%struct.Slot = type { i8, i64 }

@msort_jb = internal unnamed_addr global ptr null, align 8

; Function Attrs: noreturn nounwind uwtable
define dso_local void @t2_msort_abort() local_unnamed_addr #0 {
  %1 = load ptr, ptr @msort_jb, align 8
  tail call void @longjmp(ptr noundef %1, i32 noundef 1) #10
  unreachable
}

; Function Attrs: noreturn nounwind
declare void @longjmp(ptr noundef, i32 noundef) local_unnamed_addr #1

; Function Attrs: nounwind uwtable
define dso_local noundef i32 @t2_msort(ptr nocapture noundef %0, i64 noundef %1) local_unnamed_addr #2 {
  %3 = alloca [200 x ptr], align 16
  %4 = alloca [3 x ptr], align 16
  %5 = alloca [60 x %struct.off_runs], align 16
  %6 = alloca [1 x %struct.__jmp_buf_tag], align 16
  %7 = call i64 @llvm.umax.i64(i64 %1, i64 1)
  %8 = shl i64 %7, 3
  %9 = call noalias ptr @malloc(i64 noundef %8) #11
  %10 = shl i64 %7, 4
  %11 = call noalias ptr @malloc(i64 noundef %10) #11
  call void @llvm.lifetime.start.p0(i64 200, ptr nonnull %6) #12
  %12 = load ptr, ptr @msort_jb, align 8
  %13 = icmp sgt i64 %1, 0
  br i1 %13, label %14, label %16

14:                                               ; preds = %2
  %15 = shl nuw i64 %1, 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %11, ptr align 8 %0, i64 %15, i1 false)
  br label %19

16:                                               ; preds = %19, %2
  store ptr %6, ptr @msort_jb, align 8
  %17 = call i32 @_setjmp(ptr noundef nonnull %6) #13
  %18 = icmp eq i32 %17, 0
  br i1 %18, label %25, label %508

19:                                               ; preds = %14, %19
  %20 = phi i64 [ %23, %19 ], [ 0, %14 ]
  %21 = getelementptr inbounds %struct.Slot, ptr %11, i64 %20
  %22 = getelementptr inbounds ptr, ptr %9, i64 %20
  store ptr %21, ptr %22, align 8
  %23 = add nuw nsw i64 %20, 1
  %24 = icmp eq i64 %23, %1
  br i1 %24, label %16, label %19

25:                                               ; preds = %16
  %26 = ptrtoint ptr %9 to i64
  call void @llvm.lifetime.start.p0(i64 1600, ptr nonnull %3) #12
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.start.p0(i64 960, ptr nonnull %5) #12
  %27 = icmp ult i64 %1, 2
  br i1 %27, label %499, label %28

28:                                               ; preds = %25
  %29 = icmp ult i64 %1, 201
  br i1 %29, label %33, label %30

30:                                               ; preds = %28
  %31 = shl i64 %1, 3
  %32 = call noalias ptr @malloc(i64 noundef %31) #11
  br label %33

33:                                               ; preds = %30, %28
  %34 = phi ptr [ %32, %30 ], [ %3, %28 ]
  %35 = getelementptr inbounds ptr, ptr %9, i64 %1
  %36 = load ptr, ptr %9, align 8
  %37 = getelementptr inbounds ptr, ptr %9, i64 1
  %38 = load ptr, ptr %37, align 8
  %39 = call double @t2_sort_cmp_ab(ptr noundef %36, ptr noundef %38) #12
  %40 = icmp sgt i64 %1, 0
  br i1 %40, label %41, label %192

41:                                               ; preds = %33
  %42 = fcmp oge double %39, 9.200000e+18
  %43 = fcmp ugt double %39, -9.200000e+18
  %44 = fptosi double %39 to i64
  %45 = icmp sgt i64 %44, 0
  %46 = select i1 %43, i1 %45, i1 false
  %47 = select i1 %42, i1 true, i1 %46
  br label %48

48:                                               ; preds = %189, %41
  %49 = phi i1 [ %190, %189 ], [ %47, %41 ]
  %50 = phi ptr [ %187, %189 ], [ %9, %41 ]
  %51 = phi i64 [ %186, %189 ], [ 0, %41 ]
  %52 = phi ptr [ %177, %189 ], [ %34, %41 ]
  br label %53

53:                                               ; preds = %58, %48
  %54 = phi ptr [ %55, %58 ], [ %50, %48 ]
  %55 = getelementptr inbounds ptr, ptr %54, i64 2
  %56 = getelementptr inbounds ptr, ptr %54, i64 3
  %57 = icmp ult ptr %56, %35
  br i1 %57, label %58, label %69

58:                                               ; preds = %53
  %59 = load ptr, ptr %55, align 8
  %60 = load ptr, ptr %56, align 8
  %61 = call double @t2_sort_cmp_ab(ptr noundef %59, ptr noundef %60) #12
  %62 = fcmp ult double %61, 9.200000e+18
  %63 = fcmp ole double %61, -9.200000e+18
  %64 = fptosi double %61 to i64
  %65 = icmp slt i64 %64, 1
  %66 = select i1 %63, i1 true, i1 %65
  %67 = select i1 %62, i1 %66, i1 false
  %68 = xor i1 %49, %67
  br i1 %68, label %53, label %69

69:                                               ; preds = %58, %53
  %70 = icmp eq ptr %56, %35
  br label %71

71:                                               ; preds = %185, %69
  %72 = phi ptr [ %50, %69 ], [ %160, %185 ]
  %73 = phi ptr [ %52, %69 ], [ %177, %185 ]
  %74 = phi i64 [ %51, %69 ], [ %186, %185 ]
  %75 = phi ptr [ %50, %69 ], [ %187, %185 ]
  %76 = getelementptr inbounds ptr, ptr %75, i64 16
  %77 = icmp ult ptr %76, %55
  br i1 %77, label %78, label %113

78:                                               ; preds = %71, %91
  %79 = phi ptr [ %92, %91 ], [ %76, %71 ]
  %80 = getelementptr inbounds ptr, ptr %79, i64 -1
  %81 = load ptr, ptr %80, align 8
  %82 = load ptr, ptr %79, align 8
  %83 = call double @t2_sort_cmp_ab(ptr noundef %81, ptr noundef %82) #12
  %84 = fcmp ult double %83, 9.200000e+18
  %85 = fcmp ole double %83, -9.200000e+18
  %86 = fptosi double %83 to i64
  %87 = icmp slt i64 %86, 1
  %88 = select i1 %85, i1 true, i1 %87
  %89 = select i1 %84, i1 %88, i1 false
  %90 = xor i1 %49, %89
  br i1 %90, label %91, label %94

91:                                               ; preds = %78
  %92 = getelementptr inbounds ptr, ptr %79, i64 -2
  %93 = icmp ugt ptr %92, %72
  br i1 %93, label %78, label %94

94:                                               ; preds = %91, %78
  %95 = phi ptr [ %92, %91 ], [ %79, %78 ]
  %96 = icmp ugt ptr %95, %72
  br i1 %96, label %113, label %97

97:                                               ; preds = %94, %101
  %98 = phi ptr [ %99, %101 ], [ %76, %94 ]
  %99 = getelementptr inbounds ptr, ptr %98, i64 2
  %100 = icmp ult ptr %98, %54
  br i1 %100, label %101, label %113

101:                                              ; preds = %97
  %102 = getelementptr inbounds ptr, ptr %98, i64 1
  %103 = load ptr, ptr %102, align 8
  %104 = load ptr, ptr %99, align 8
  %105 = call double @t2_sort_cmp_ab(ptr noundef %103, ptr noundef %104) #12
  %106 = fcmp ult double %105, 9.200000e+18
  %107 = fcmp ole double %105, -9.200000e+18
  %108 = fptosi double %105 to i64
  %109 = icmp slt i64 %108, 1
  %110 = select i1 %107, i1 true, i1 %109
  %111 = select i1 %106, i1 %110, i1 false
  %112 = xor i1 %49, %111
  br i1 %112, label %97, label %113

113:                                              ; preds = %101, %97, %94, %71
  %114 = phi ptr [ %72, %94 ], [ %72, %71 ], [ %98, %97 ], [ %98, %101 ]
  %115 = phi ptr [ %95, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %116 = phi ptr [ %76, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %117 = icmp ugt ptr %114, %75
  br i1 %117, label %118, label %156

118:                                              ; preds = %113
  %119 = getelementptr inbounds ptr, ptr %114, i64 2
  %120 = icmp eq ptr %114, %54
  %121 = select i1 %120, i1 %70, i1 false
  br i1 %121, label %122, label %135

122:                                              ; preds = %118
  %123 = getelementptr inbounds ptr, ptr %114, i64 1
  %124 = load ptr, ptr %123, align 8
  %125 = load ptr, ptr %119, align 8
  %126 = call double @t2_sort_cmp_ab(ptr noundef %124, ptr noundef %125) #12
  %127 = fcmp ult double %126, 9.200000e+18
  %128 = fcmp ole double %126, -9.200000e+18
  %129 = fptosi double %126 to i64
  %130 = icmp slt i64 %129, 1
  %131 = select i1 %128, i1 true, i1 %130
  %132 = select i1 %127, i1 %131, i1 false
  %133 = xor i1 %49, %132
  br i1 %133, label %134, label %135

134:                                              ; preds = %122
  br label %135

135:                                              ; preds = %134, %122, %118
  %136 = phi ptr [ %35, %134 ], [ %119, %122 ], [ %119, %118 ]
  %137 = phi ptr [ %35, %134 ], [ %116, %122 ], [ %116, %118 ]
  %138 = phi ptr [ %35, %134 ], [ %115, %122 ], [ %115, %118 ]
  %139 = ptrtoint ptr %136 to i64
  %140 = ptrtoint ptr %75 to i64
  %141 = sub i64 %139, %140
  %142 = ashr exact i64 %141, 3
  %143 = getelementptr inbounds ptr, ptr %73, i64 %142
  store ptr %143, ptr %73, align 8
  %144 = add nsw i64 %74, 1
  %145 = getelementptr inbounds ptr, ptr %136, i64 -1
  %146 = icmp ult ptr %75, %145
  %147 = select i1 %49, i1 %146, i1 false
  br i1 %147, label %148, label %156

148:                                              ; preds = %135, %148
  %149 = phi ptr [ %154, %148 ], [ %145, %135 ]
  %150 = phi ptr [ %153, %148 ], [ %75, %135 ]
  %151 = load ptr, ptr %150, align 8
  %152 = load ptr, ptr %149, align 8
  %153 = getelementptr inbounds ptr, ptr %150, i64 1
  store ptr %152, ptr %150, align 8
  store ptr %151, ptr %149, align 8
  %154 = getelementptr inbounds ptr, ptr %149, i64 -1
  %155 = icmp ult ptr %153, %154
  br i1 %155, label %148, label %156

156:                                              ; preds = %148, %135, %113
  %157 = phi ptr [ %114, %113 ], [ %136, %135 ], [ %136, %148 ]
  %158 = phi ptr [ %73, %113 ], [ %143, %135 ], [ %143, %148 ]
  %159 = phi ptr [ %115, %113 ], [ %138, %135 ], [ %138, %148 ]
  %160 = phi ptr [ %116, %113 ], [ %137, %135 ], [ %137, %148 ]
  %161 = phi i64 [ %74, %113 ], [ %144, %135 ], [ %144, %148 ]
  %162 = icmp ult ptr %157, %159
  br i1 %162, label %163, label %176

163:                                              ; preds = %156, %173
  %164 = phi i64 [ %168, %173 ], [ %161, %156 ]
  %165 = phi ptr [ %167, %173 ], [ %158, %156 ]
  %166 = phi ptr [ %174, %173 ], [ %157, %156 ]
  %167 = getelementptr inbounds ptr, ptr %165, i64 2
  store ptr %167, ptr %165, align 8
  %168 = add nsw i64 %164, 1
  br i1 %49, label %169, label %173

169:                                              ; preds = %163
  %170 = getelementptr inbounds ptr, ptr %166, i64 1
  %171 = load ptr, ptr %166, align 8
  %172 = load ptr, ptr %170, align 8
  store ptr %172, ptr %166, align 8
  store ptr %171, ptr %170, align 8
  br label %173

173:                                              ; preds = %169, %163
  %174 = getelementptr inbounds ptr, ptr %166, i64 2
  %175 = icmp ult ptr %174, %159
  br i1 %175, label %163, label %176

176:                                              ; preds = %173, %156
  %177 = phi ptr [ %158, %156 ], [ %167, %173 ]
  %178 = phi i64 [ %161, %156 ], [ %168, %173 ]
  %179 = icmp eq ptr %159, %55
  %180 = select i1 %179, i1 %70, i1 false
  br i1 %180, label %181, label %185

181:                                              ; preds = %176
  %182 = getelementptr inbounds ptr, ptr %177, i64 1
  store ptr %182, ptr %177, align 8
  %183 = add nsw i64 %178, 1
  %184 = getelementptr inbounds ptr, ptr %159, i64 1
  br label %185

185:                                              ; preds = %181, %176
  %186 = phi i64 [ %183, %181 ], [ %178, %176 ]
  %187 = phi ptr [ %184, %181 ], [ %159, %176 ]
  %188 = icmp ult ptr %187, %55
  br i1 %188, label %71, label %189

189:                                              ; preds = %185
  %190 = xor i1 %49, true
  %191 = icmp ult ptr %187, %35
  br i1 %191, label %48, label %192

192:                                              ; preds = %189, %33
  %193 = phi i64 [ 0, %33 ], [ %186, %189 ]
  %194 = getelementptr inbounds %struct.off_runs, ptr %5, i64 0, i32 1
  store i64 %193, ptr %194, align 8
  store i64 0, ptr %5, align 16
  %195 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 2
  store ptr %9, ptr %195, align 16
  store ptr %9, ptr %4, align 16
  %196 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 1
  store ptr %34, ptr %196, align 8
  %197 = ptrtoint ptr %34 to i64
  %198 = xor i64 %26, -1
  %199 = sub i64 %26, %197
  %200 = add i64 %26, 8
  br label %201

201:                                              ; preds = %491, %192
  %202 = phi i64 [ 0, %192 ], [ %492, %491 ]
  %203 = phi i32 [ 0, %192 ], [ %493, %491 ]
  %204 = phi ptr [ %5, %192 ], [ %494, %491 ]
  %205 = getelementptr inbounds %struct.off_runs, ptr %204, i64 0, i32 1
  %206 = load i64, ptr %205, align 8
  %207 = icmp eq i64 %206, 0
  br i1 %207, label %208, label %422

208:                                              ; preds = %201
  %209 = and i32 %203, 1
  %210 = zext nneg i32 %209 to i64
  %211 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %210
  %212 = load ptr, ptr %211, align 8
  %213 = add nuw nsw i32 %209, 1
  %214 = zext nneg i32 %213 to i64
  %215 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %214
  %216 = load ptr, ptr %215, align 8
  br label %217

217:                                              ; preds = %412, %208
  %218 = phi i32 [ %203, %208 ], [ %403, %412 ]
  %219 = phi ptr [ %204, %208 ], [ %408, %412 ]
  %220 = phi ptr [ %212, %208 ], [ %410, %412 ]
  %221 = phi ptr [ %216, %208 ], [ %411, %412 ]
  %222 = load i64, ptr %219, align 8
  %223 = getelementptr inbounds ptr, ptr %220, i64 %222
  %224 = getelementptr inbounds ptr, ptr %221, i64 %222
  %225 = load ptr, ptr %224, align 8
  %226 = ptrtoint ptr %225 to i64
  %227 = ptrtoint ptr %221 to i64
  %228 = sub i64 %226, %227
  %229 = getelementptr inbounds i8, ptr %220, i64 %228
  %230 = load ptr, ptr %225, align 8
  %231 = ptrtoint ptr %230 to i64
  %232 = sub i64 %231, %227
  %233 = getelementptr inbounds i8, ptr %220, i64 %232
  %234 = icmp ult ptr %223, %229
  %235 = icmp slt i64 %228, %232
  %236 = select i1 %234, i1 %235, i1 false
  br i1 %236, label %237, label %377

237:                                              ; preds = %217, %366
  %238 = phi ptr [ %373, %366 ], [ %224, %217 ]
  %239 = phi ptr [ %370, %366 ], [ %229, %217 ]
  %240 = phi ptr [ %369, %366 ], [ %223, %217 ]
  %241 = load ptr, ptr %240, align 8
  %242 = load ptr, ptr %239, align 8
  %243 = call double @t2_sort_cmp_ab(ptr noundef %241, ptr noundef %242) #12
  %244 = fcmp ult double %243, 9.200000e+18
  %245 = fcmp ole double %243, -9.200000e+18
  %246 = fptosi double %243 to i64
  %247 = icmp slt i64 %246, 1
  %248 = select i1 %245, i1 true, i1 %247
  %249 = select i1 %244, i1 %248, i1 false
  %250 = sext i1 %249 to i32
  %251 = select i1 %249, ptr %229, ptr %233
  %252 = select i1 %249, ptr %240, ptr %239
  %253 = select i1 %249, ptr %239, ptr %240
  %254 = getelementptr inbounds ptr, ptr %252, i64 1
  %255 = icmp ult ptr %254, %251
  br i1 %255, label %256, label %270

256:                                              ; preds = %237
  %257 = load ptr, ptr %253, align 8
  %258 = load ptr, ptr %254, align 8
  %259 = call double @t2_sort_cmp_ab(ptr noundef %257, ptr noundef %258) #12
  %260 = fcmp ult double %259, 9.200000e+18
  %261 = fcmp ole double %259, -9.200000e+18
  %262 = fptosi double %259 to i64
  %263 = select i1 %261, i64 -1, i64 %262
  %264 = select i1 %260, i64 %263, i64 1
  %265 = icmp sgt i64 %264, -1
  %266 = icmp ne i64 %264, 0
  %267 = zext i1 %266 to i32
  %268 = icmp sgt i32 %267, %250
  %269 = and i1 %265, %268
  br i1 %269, label %304, label %313

270:                                              ; preds = %304, %237
  %271 = phi ptr [ %252, %237 ], [ %307, %304 ]
  %272 = getelementptr inbounds ptr, ptr %251, i64 -1
  %273 = icmp ugt ptr %272, %271
  br i1 %273, label %274, label %288

274:                                              ; preds = %270
  %275 = load ptr, ptr %253, align 8
  %276 = load ptr, ptr %272, align 8
  %277 = call double @t2_sort_cmp_ab(ptr noundef %275, ptr noundef %276) #12
  %278 = fcmp ult double %277, 9.200000e+18
  %279 = fcmp ole double %277, -9.200000e+18
  %280 = fptosi double %277 to i64
  %281 = select i1 %279, i64 -1, i64 %280
  %282 = select i1 %278, i64 %281, i64 1
  %283 = icmp sgt i64 %282, -1
  %284 = icmp ne i64 %282, 0
  %285 = zext i1 %284 to i32
  %286 = icmp sgt i32 %285, %250
  %287 = and i1 %283, %286
  br i1 %287, label %288, label %313

288:                                              ; preds = %274, %270
  br label %313

289:                                              ; preds = %304
  %290 = add nuw nsw i64 %305, 1
  %291 = load ptr, ptr %253, align 8
  %292 = load ptr, ptr %311, align 8
  %293 = call double @t2_sort_cmp_ab(ptr noundef %291, ptr noundef %292) #12
  %294 = fcmp ult double %293, 9.200000e+18
  %295 = fcmp ole double %293, -9.200000e+18
  %296 = fptosi double %293 to i64
  %297 = select i1 %295, i64 -1, i64 %296
  %298 = select i1 %294, i64 %297, i64 1
  %299 = icmp sgt i64 %298, -1
  %300 = icmp ne i64 %298, 0
  %301 = zext i1 %300 to i32
  %302 = icmp sgt i32 %301, %250
  %303 = and i1 %299, %302
  br i1 %303, label %304, label %313

304:                                              ; preds = %256, %289
  %305 = phi i64 [ %290, %289 ], [ 0, %256 ]
  %306 = phi i64 [ %310, %289 ], [ 1, %256 ]
  %307 = phi ptr [ %311, %289 ], [ %254, %256 ]
  %308 = icmp ugt i64 %305, 4
  %309 = zext i1 %308 to i64
  %310 = shl nsw i64 %306, %309
  %311 = getelementptr inbounds ptr, ptr %307, i64 %310
  %312 = icmp ult ptr %311, %251
  br i1 %312, label %289, label %270

313:                                              ; preds = %289, %256, %288, %274
  %314 = phi ptr [ %251, %288 ], [ %272, %274 ], [ %254, %256 ], [ %311, %289 ]
  %315 = phi ptr [ %272, %288 ], [ %271, %274 ], [ %252, %256 ], [ %307, %289 ]
  %316 = getelementptr inbounds ptr, ptr %315, i64 1
  %317 = icmp ult ptr %316, %314
  br i1 %317, label %318, label %345

318:                                              ; preds = %313, %318
  %319 = phi ptr [ %343, %318 ], [ %316, %313 ]
  %320 = phi ptr [ %342, %318 ], [ %314, %313 ]
  %321 = ptrtoint ptr %320 to i64
  %322 = ptrtoint ptr %319 to i64
  %323 = sub i64 %321, %322
  %324 = ashr exact i64 %323, 3
  %325 = add nsw i64 %324, -1
  %326 = sdiv i64 %325, 2
  %327 = getelementptr inbounds ptr, ptr %319, i64 %326
  %328 = load ptr, ptr %253, align 8
  %329 = load ptr, ptr %327, align 8
  %330 = call double @t2_sort_cmp_ab(ptr noundef %328, ptr noundef %329) #12
  %331 = fcmp ult double %330, 9.200000e+18
  %332 = fcmp ole double %330, -9.200000e+18
  %333 = fptosi double %330 to i64
  %334 = select i1 %332, i64 -1, i64 %333
  %335 = select i1 %331, i64 %334, i64 1
  %336 = icmp sgt i64 %335, -1
  %337 = icmp ne i64 %335, 0
  %338 = zext i1 %337 to i32
  %339 = icmp sgt i32 %338, %250
  %340 = and i1 %336, %339
  %341 = getelementptr inbounds ptr, ptr %327, i64 1
  %342 = select i1 %340, ptr %320, ptr %327
  %343 = select i1 %340, ptr %341, ptr %319
  %344 = icmp ult ptr %343, %342
  br i1 %344, label %318, label %345

345:                                              ; preds = %318, %313
  %346 = phi ptr [ %314, %313 ], [ %342, %318 ]
  %347 = icmp eq ptr %253, %240
  br i1 %347, label %348, label %357

348:                                              ; preds = %345, %348
  %349 = phi ptr [ %351, %348 ], [ %239, %345 ]
  %350 = phi ptr [ %353, %348 ], [ %238, %345 ]
  %351 = getelementptr inbounds ptr, ptr %349, i64 1
  %352 = load ptr, ptr %349, align 8
  %353 = getelementptr inbounds ptr, ptr %350, i64 1
  store ptr %352, ptr %350, align 8
  %354 = icmp ult ptr %351, %346
  br i1 %354, label %348, label %355

355:                                              ; preds = %348
  %356 = getelementptr inbounds ptr, ptr %240, i64 1
  br label %366

357:                                              ; preds = %345, %357
  %358 = phi ptr [ %360, %357 ], [ %240, %345 ]
  %359 = phi ptr [ %362, %357 ], [ %238, %345 ]
  %360 = getelementptr inbounds ptr, ptr %358, i64 1
  %361 = load ptr, ptr %358, align 8
  %362 = getelementptr inbounds ptr, ptr %359, i64 1
  store ptr %361, ptr %359, align 8
  %363 = icmp ult ptr %360, %346
  br i1 %363, label %357, label %364

364:                                              ; preds = %357
  %365 = getelementptr inbounds ptr, ptr %239, i64 1
  br label %366

366:                                              ; preds = %364, %355
  %367 = phi ptr [ %239, %364 ], [ %240, %355 ]
  %368 = phi ptr [ %362, %364 ], [ %353, %355 ]
  %369 = phi ptr [ %360, %364 ], [ %356, %355 ]
  %370 = phi ptr [ %365, %364 ], [ %351, %355 ]
  %371 = phi ptr [ %359, %364 ], [ %350, %355 ]
  %372 = load ptr, ptr %367, align 8
  store ptr %372, ptr %368, align 8
  %373 = getelementptr inbounds ptr, ptr %371, i64 2
  %374 = icmp ult ptr %369, %229
  %375 = icmp ult ptr %370, %233
  %376 = select i1 %374, i1 %375, i1 false
  br i1 %376, label %237, label %377

377:                                              ; preds = %366, %217
  %378 = phi ptr [ %223, %217 ], [ %369, %366 ]
  %379 = phi ptr [ %229, %217 ], [ %370, %366 ]
  %380 = phi ptr [ %224, %217 ], [ %373, %366 ]
  %381 = phi i1 [ %235, %217 ], [ %375, %366 ]
  %382 = icmp eq ptr %378, %229
  br i1 %382, label %383, label %391

383:                                              ; preds = %377
  br i1 %381, label %384, label %398

384:                                              ; preds = %383, %384
  %385 = phi ptr [ %387, %384 ], [ %379, %383 ]
  %386 = phi ptr [ %389, %384 ], [ %380, %383 ]
  %387 = getelementptr inbounds ptr, ptr %385, i64 1
  %388 = load ptr, ptr %385, align 8
  %389 = getelementptr inbounds ptr, ptr %386, i64 1
  store ptr %388, ptr %386, align 8
  %390 = icmp ult ptr %387, %233
  br i1 %390, label %384, label %398

391:                                              ; preds = %377, %391
  %392 = phi ptr [ %394, %391 ], [ %378, %377 ]
  %393 = phi ptr [ %396, %391 ], [ %380, %377 ]
  %394 = getelementptr inbounds ptr, ptr %392, i64 1
  %395 = load ptr, ptr %392, align 8
  %396 = getelementptr inbounds ptr, ptr %393, i64 1
  store ptr %395, ptr %393, align 8
  %397 = icmp ult ptr %394, %229
  br i1 %397, label %391, label %398

398:                                              ; preds = %391, %384, %383
  %399 = phi ptr [ %380, %383 ], [ %389, %384 ], [ %396, %391 ]
  %400 = ptrtoint ptr %399 to i64
  %401 = sub i64 %400, %227
  %402 = getelementptr inbounds i8, ptr %220, i64 %401
  store ptr %402, ptr %223, align 8
  %403 = add nsw i32 %218, -1
  %404 = icmp eq i32 %403, 0
  br i1 %404, label %407, label %405

405:                                              ; preds = %398
  %406 = getelementptr inbounds %struct.off_runs, ptr %219, i64 -1
  br label %407

407:                                              ; preds = %405, %398
  %408 = phi ptr [ %406, %405 ], [ %219, %398 ]
  %409 = phi i32 [ 0, %405 ], [ 20, %398 ]
  %410 = phi ptr [ %221, %405 ], [ %220, %398 ]
  %411 = phi ptr [ %220, %405 ], [ %221, %398 ]
  br i1 %404, label %416, label %412

412:                                              ; preds = %407
  %413 = getelementptr inbounds %struct.off_runs, ptr %408, i64 0, i32 1
  %414 = load i64, ptr %413, align 8
  %415 = icmp eq i64 %414, 0
  br i1 %415, label %217, label %416

416:                                              ; preds = %412, %407
  %417 = phi i32 [ %403, %412 ], [ 0, %407 ]
  %418 = phi i32 [ 0, %412 ], [ %409, %407 ]
  %419 = phi i64 [ %414, %412 ], [ 0, %407 ]
  %420 = ashr exact i64 %232, 3
  %421 = icmp eq i32 %418, 0
  br i1 %421, label %422, label %491

422:                                              ; preds = %416, %201
  %423 = phi i64 [ %420, %416 ], [ %202, %201 ]
  %424 = phi i32 [ %417, %416 ], [ %203, %201 ]
  %425 = phi ptr [ %408, %416 ], [ %204, %201 ]
  %426 = phi i64 [ %419, %416 ], [ %206, %201 ]
  %427 = getelementptr inbounds %struct.off_runs, ptr %425, i64 0, i32 1
  store i64 0, ptr %427, align 8
  %428 = icmp sgt i64 %426, 2
  br i1 %428, label %429, label %439

429:                                              ; preds = %422, %429
  %430 = phi i64 [ %437, %429 ], [ %426, %422 ]
  %431 = phi ptr [ %434, %429 ], [ %425, %422 ]
  %432 = phi i32 [ %433, %429 ], [ %424, %422 ]
  %433 = add nsw i32 %432, 1
  %434 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1
  store i64 %423, ptr %434, align 8
  %435 = lshr i64 %430, 1
  %436 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1, i32 1
  store i64 %435, ptr %436, align 8
  %437 = sub nsw i64 %430, %435
  %438 = icmp sgt i64 %437, 2
  br i1 %438, label %429, label %439

439:                                              ; preds = %429, %422
  %440 = phi i32 [ %424, %422 ], [ %433, %429 ]
  %441 = phi ptr [ %425, %422 ], [ %434, %429 ]
  %442 = phi i64 [ %426, %422 ], [ %437, %429 ]
  %443 = and i32 %440, 1
  %444 = icmp eq i64 %442, 1
  br i1 %444, label %445, label %466

445:                                              ; preds = %439
  %446 = icmp eq i32 %443, 0
  br i1 %446, label %463, label %447

447:                                              ; preds = %445
  %448 = getelementptr ptr, ptr %9, i64 %423
  %449 = getelementptr inbounds ptr, ptr %34, i64 %423
  %450 = load ptr, ptr %449, align 8
  %451 = ptrtoint ptr %450 to i64
  %452 = add i64 %199, %451
  %453 = shl nsw i64 %423, 3
  %454 = add i64 %453, %200
  %455 = call i64 @llvm.umax.i64(i64 %452, i64 %454)
  %456 = sub i64 %198, %453
  %457 = add i64 %456, %455
  %458 = and i64 %457, -8
  %459 = add i64 %458, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %449, ptr align 8 %448, i64 %459, i1 false)
  %460 = sub i64 %451, %197
  %461 = ashr exact i64 %460, 3
  %462 = getelementptr inbounds i8, ptr %9, i64 %460
  store ptr %462, ptr %448, align 8
  br label %491

463:                                              ; preds = %445
  %464 = icmp eq i32 %440, 0
  %465 = select i1 %464, i32 20, i32 0
  br label %491

466:                                              ; preds = %439
  %467 = add nsw i32 %440, 1
  %468 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1
  store i64 %423, ptr %468, align 8
  %469 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1, i32 1
  store i64 0, ptr %469, align 8
  %470 = icmp eq i32 %443, 0
  br i1 %470, label %471, label %491

471:                                              ; preds = %466
  %472 = getelementptr ptr, ptr %9, i64 %423
  %473 = getelementptr inbounds ptr, ptr %34, i64 %423
  %474 = load ptr, ptr %473, align 8
  %475 = load ptr, ptr %474, align 8
  %476 = ptrtoint ptr %475 to i64
  %477 = add i64 %199, %476
  %478 = shl nsw i64 %423, 3
  %479 = add i64 %478, %200
  %480 = call i64 @llvm.umax.i64(i64 %477, i64 %479)
  %481 = sub i64 %198, %478
  %482 = add i64 %481, %480
  %483 = and i64 %482, -8
  %484 = add i64 %483, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %473, ptr align 8 %472, i64 %484, i1 false)
  %485 = sub i64 %476, %197
  %486 = ptrtoint ptr %474 to i64
  %487 = sub i64 %486, %197
  %488 = ashr exact i64 %487, 3
  %489 = getelementptr inbounds i8, ptr %9, i64 %487
  %490 = getelementptr inbounds i8, ptr %9, i64 %485
  store ptr %489, ptr %472, align 8
  store ptr %490, ptr %489, align 8
  br label %491

491:                                              ; preds = %471, %466, %463, %447, %416
  %492 = phi i64 [ %420, %416 ], [ %461, %447 ], [ %423, %466 ], [ %488, %471 ], [ %423, %463 ]
  %493 = phi i32 [ %417, %416 ], [ %440, %447 ], [ %467, %466 ], [ %467, %471 ], [ %440, %463 ]
  %494 = phi ptr [ %408, %416 ], [ %441, %447 ], [ %468, %466 ], [ %468, %471 ], [ %441, %463 ]
  %495 = phi i32 [ %418, %416 ], [ 0, %447 ], [ 0, %466 ], [ 0, %471 ], [ %465, %463 ]
  switch i32 %495, label %499 [
    i32 0, label %201
    i32 20, label %496
  ]

496:                                              ; preds = %491
  %497 = icmp eq ptr %34, %3
  br i1 %497, label %499, label %498

498:                                              ; preds = %496
  call void @free(ptr noundef %34) #12
  br label %499

499:                                              ; preds = %491, %25, %496, %498
  call void @llvm.lifetime.end.p0(i64 960, ptr nonnull %5) #12
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.end.p0(i64 1600, ptr nonnull %3) #12
  %500 = icmp sgt i64 %1, 0
  br i1 %500, label %501, label %508

501:                                              ; preds = %499, %501
  %502 = phi i64 [ %506, %501 ], [ 0, %499 ]
  %503 = getelementptr inbounds %struct.Slot, ptr %0, i64 %502
  %504 = getelementptr inbounds ptr, ptr %9, i64 %502
  %505 = load ptr, ptr %504, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %503, ptr noundef nonnull align 8 dereferenceable(16) %505, i64 16, i1 false)
  %506 = add nuw nsw i64 %502, 1
  %507 = icmp eq i64 %506, %1
  br i1 %507, label %508, label %501

508:                                              ; preds = %501, %499, %16
  %509 = phi i32 [ 1, %16 ], [ 0, %499 ], [ 0, %501 ]
  store ptr %12, ptr @msort_jb, align 8
  call void @free(ptr noundef %9) #12
  call void @free(ptr noundef %11) #12
  call void @llvm.lifetime.end.p0(i64 200, ptr nonnull %6) #12
  ret i32 %509
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #5

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: nounwind returns_twice
declare i32 @_setjmp(ptr noundef) local_unnamed_addr #6

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr nocapture noundef) local_unnamed_addr #7


; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #9

attributes #0 = { noreturn nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { noreturn nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #3 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #5 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #6 = { nounwind returns_twice "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #7 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #8 = { "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #9 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #10 = { noreturn nounwind }
attributes #11 = { nounwind allocsize(0) }
attributes #12 = { nounwind }
attributes #13 = { nounwind returns_twice }


; t2_ghash(g) / t2_garray(g): the file's hash or array a global holds, made
; the first time any function reaches it.
define internal %Slot @t2_ghash(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 5
  br i1 %has, label %done, label %make
make:
  %h = call %Slot @t2_hnew()
  store %Slot %h, %Slot* %g
  ret %Slot %h
done:
  ret %Slot %v
}
define internal %Array* @t2_garray(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 6
  br i1 %has, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  store %Slot %s, %Slot* %g
  ret %Array* %a
done:
  %p = extractvalue %Slot %v, 1
  %r = inttoptr i64 %p to %Array*
  ret %Array* %r
}
; t2_arev(a) -> a new list of a's elements, last first.
define internal %Array* @t2_arev(%Array* %a) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %im)
  call void @t2_apush(%Array* %r, %Slot %v)
  br label %loop
done:
  ret %Array* %r
}
; WHOLE ASSIGN IN PLACE (`@a = LIST`, `%h = LIST` on the container a tie or a
; reference names): the list copied first -- it may read the aggregate --
; then, for a tied one, perl's calls; for any other, cleared and refilled.
@lit_tm_extend = private unnamed_addr constant [7 x i8] c"EXTEND\00"
define internal void @t2_aassign(%Array* %a, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %n = call i64 @t2_alen(%Array* %c)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %plain, label %tied
plain:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 0, i64* %lp
  call void @t2_aappend(%Array* %a, %Array* %c)
  ret void
tied:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ca = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %ca, %Slot %o)
  %cm = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %cr = call %Slot @t2_tie_call(%Array* %ca, %Str %cm)
  %xa = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %xa, %Slot %o)
  %ns = call %Slot @t2_box_i64(i64 %n)
  call void @t2_apush(%Array* %xa, %Slot %ns)
  %xm = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_extend, i64 0, i64 0), i64 6)
  %xr = call %Slot @t2_tie_call(%Array* %xa, %Str %xm)
  br label %loop
loop:
  %i = phi i64 [ 0, %tied ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %c, i64 %i)
  call void @t2_aset(%Array* %a, i64 %i, %Slot %v, i8* null, i64 0)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
define internal void @t2_hassign(%Slot %h, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %a = call %Array* @t2_harr(%Slot %h)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %plain, label %tied
plain:
  ; (element 0 is the hash's class: kept)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 1, i64* %lp
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
tied:
  ; (a tie's hfroma is CLEAR, then STORE each pair)
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
}
; t2_mresolve(invocant, method, " at FILE line N.\n", start, mode) -> the method's code,
; looked up from (mode 0) the invocant's class, (1) start, a qualified name's
; package, or (2) start's @ISA, a SUPER:: call's; where perl dies (no class,
; no method), a die naming that class, and t2_nomethod's code.
define internal i8* @t2_mresolve(%Slot %inv, %Str %m, %Str %at, %Str %start, i8 %mode) {
entry:
  store %Str %at, %Str* @t2_call_at
  %t = extractvalue %Slot %inv, 0
  switch i8 %t, label %named [ i8 0, label %undef i8 5, label %ref i8 6, label %ref i8 7, label %unbl i8 8, label %ref i8 9, label %ref ]
undef:
  %u0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %u1 = call %Str @t2_concat(%Str %u0, %Str %m)
  %u2 = call %Str @t2_str(i8* getelementptr ([24 x i8], [24 x i8]* @lit_undefv, i64 0, i64 0), i64 23)
  %u3 = call %Str @t2_concat(%Str %u1, %Str %u2)
  br label %die
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %ct = extractvalue %Slot %cl, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %unbl
obj:
  %cn = call %Str @t2_slot_str(%Slot %cl)
  br label %look
unbl:
  %b0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %b1 = call %Str @t2_concat(%Str %b0, %Str %m)
  %b2 = call %Str @t2_str(i8* getelementptr ([25 x i8], [25 x i8]* @lit_unbl, i64 0, i64 0), i64 24)
  %b3 = call %Str @t2_concat(%Str %b1, %Str %b2)
  br label %die
named:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  %nl = extractvalue %Str %nn, 1
  %empty = icmp eq i64 %nl, 0
  br i1 %empty, label %nopkg, label %look
nopkg:
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %m)
  %p2 = call %Str @t2_str(i8* getelementptr ([40 x i8], [40 x i8]* @lit_nopkg, i64 0, i64 0), i64 39)
  %p3 = call %Str @t2_concat(%Str %p1, %Str %p2)
  br label %die
look:
  %own = phi %Str [ %cn, %obj ], [ %nn, %named ]
  %fromown = icmp eq i8 %mode, 0
  %c = select i1 %fromown, %Str %own, %Str %start
  %super = icmp eq i8 %mode, 2
  %r = call i8* @t2_mfind_u(%Str %c, %Str %m, i1 %super)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %miss
ok:
  ret i8* %r
miss:
  %l0 = call %Str @t2_str(i8* getelementptr ([29 x i8], [29 x i8]* @lit_lom, i64 0, i64 0), i64 28)
  %l1 = call %Str @t2_concat(%Str %l0, %Str %m)
  %l2 = call %Str @t2_str(i8* getelementptr ([16 x i8], [16 x i8]* @lit_via, i64 0, i64 0), i64 15)
  %l3 = call %Str @t2_concat(%Str %l1, %Str %l2)
  %l4 = call %Str @t2_concat(%Str %l3, %Str %c)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %quote, label %forgot
quote:
  %k0 = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_q, i64 0, i64 0), i64 1)
  %k1 = call %Str @t2_concat(%Str %l4, %Str %k0)
  br label %die
forgot:
  %f0 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_forgot, i64 0, i64 0), i64 31)
  %f1 = call %Str @t2_concat(%Str %l4, %Str %f0)
  %f2 = call %Str @t2_concat(%Str %f1, %Str %c)
  %f3 = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_qp, i64 0, i64 0), i64 3)
  %f4 = call %Str @t2_concat(%Str %f2, %Str %f3)
  br label %die
die:
  %msg = phi %Str [ %u3, %undef ], [ %b3, %unbl ], [ %p3, %nopkg ], [ %k1, %quote ], [ %f4, %forgot ]
  %full = call %Str @t2_concat(%Str %msg, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret i8* bitcast (%Slot (%Array*)* @t2_nomethod to i8*)
}
; t2_nomethod(@_) -> undef: called where no method was found, a die already set.
define internal %Slot @t2_nomethod(%Array* %args) {
entry:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_hget_d(%Slot %h, %Str %k) {
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
define internal i1 @t2_hexists_d(%Slot %h, %Str %k) {
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %e = icmp sge i64 %i, 0
  ret i1 %e
}
; t2_hdelete(h, k) -> k's value (undef if none), its pair taken out.
define internal %Slot @t2_hdelete_d(%Slot %h, %Str %k) {
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
define internal void @t2_hfroma_d(%Slot %h, %Array* %l) {
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
define internal i64 @t2_hcount_d(%Slot %h) {
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
define internal %Array* @t2_hpairs_d(%Slot %h) {
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
define internal %Array* @t2_hkeys_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 1)
  ret %Array* %r
}
define internal %Array* @t2_hvalues_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 2)
  ret %Array* %r
}
define internal void @t2_hset_d(%Slot %h, %Str %k, %Slot %v) {
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
