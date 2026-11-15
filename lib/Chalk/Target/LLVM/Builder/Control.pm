# ABOUTME: The LLVM builder's control flow: the walk of a control chain, eval frames,
# ABOUTME: if/else and its joins, loops and their exits (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

use Scalar::Util qw(blessed refaddr);

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
        $b->{at}{ refaddr($s) } = [ ++$b->{seq}, refaddr( $b->{cur} // 0 ), $b->{depth} // 0 ];
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
            # (to a handle in memory, its scalar appended to; with no handle, in a
            # program that selects one, to the one selected)
            my $to;
            if ( $s->can('has_filehandle') && $s->has_filehandle ) {
                my $fh = shift @args;
                my $name = blessed($fh) && $fh->operation eq 'Constant' && ( $fh->stamp // '' ) eq 'Glob' ? $fh->value // '' : '';
                if ( blessed($fh) && $fh->operation eq 'PadAccess' ) {
                    # (to a handle never opened perl dies -- a stop here, which an eval would not catch)
                    out('a print to a `my $fh` in a program with an eval') if $b->{has_eval};
                    $b->reads_before($_) for $b->{passed}->@*;
                    $to = $b->fh_handle($fh);
                }
                # A HANDLE THE PROGRAM OPENS NOWHERE (`print __CLASS__;` is a
                # print to one): perl prints nothing to it. Its value (false) unread.
                elsif ( length $name && $name !~ /\A(?:main)?::(?:STDOUT|STDERR)\z|\A(?:STDOUT|STDERR|STDIN|DATA)\z/
                        && !grep { $_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'glob' && ( $_->value // '' ) eq $name
                                   && grep { blessed($_) && $_->operation ne 'Print' } ( $_->consumers // [] )->@* } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) ) {
                    out('a print to a handle opened nowhere, its value read') if $b->_value_read($s);
                    $ctl = $s;
                    next;
                }
                else {
                    $fd = { STDOUT => 1, STDERR => 2 }->{ $name =~ s/\A(?:main)?:://r }
                        // out('a print to a filehandle other than STDOUT or STDERR');
                }
            }
            elsif ( $b->selects ) { $b->reads_before($_) for $b->{passed}->@*; $fd = 'sel' }
            # (ITS VALUE, to a handle, is 1 where it was open for writing, else
            # undef: the last part's -- each says the same; to STDOUT or STDERR, 1)
            my $ok;
            my $put = sub ($str) {
                return $ok = $b->emit(op => 'FhPrint', type => 'i1', inputs => [ $to, $str ]) if $to;
                return $ok = $b->emit(op => 'PrintSel', type => 'i1', inputs => [$str]) if $fd eq 'sel';
                return $b->emit(op => 'Print', type => 'void', inputs => [$str], attr => { fd => $fd });
            };
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
                    } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
                    my $none = $b->const_str('');
                    $put->( $b->emit(op => 'Join', type => '%Str', inputs => [ $none, $b->array_of($x) ]) );
                    next;
                }
                $put->( $b->as($b->value($x), '%Str') );
            }
            # ITS VALUE is 1 (perl's print returns true): a block's last
            # statement, a try's catch.
            out('a print of nothing to a handle, its value read') if ( $to || $fd eq 'sel' ) && !$ok && $b->_value_read($s);
            # (perl's print to a handle not open for writing is undef)
            $b->{memo}{ refaddr($s) } = $ok
                ? $b->emit(op => 'Select', type => '%Slot', inputs => [ $ok, $b->as( $b->emit(op => 'Const', type => 'i64', attr => { value => 1 }), '%Slot' ), $b->emit(op => 'Undef', type => '%Slot') ])
                : $b->emit(op => 'Const', type => 'i64', attr => { value => 1 });
            $ctl = $s;
        }
        elsif ($op eq 'Loop') { $ctl = $b->loop($s) }
        # (undef: both arms left -- the loop, or for a merge on in it: a
        # continue block both a `next` and the body's end reach)
        elsif ($op eq 'If')   { $ctl = $b->if_stmt($s) // $b->full_jump // return undef }
        # A READ OF A TIED AGGREGATE PINNED where it runs (B::SoN): a FETCH,
        # FETCHSIZE or EXISTS call, made here, in order.
        elsif ($op eq 'RegexSubst' || $op eq 'Transliterate') { $b->regex_subst_stmt($s); push $b->{passed}->@*, $s; $ctl = $s }
        elsif ($op =~ /\A(?:Subscript|Count|Exists|PostfixDeref|FieldAccess|RegexMatch|Match|BitAnd|BitOr|BitXor|Complement|LeftShift|RightShift)\z/
               || $op eq 'Call' && ( t2_builtin( $s, 'in_place' ) // '' ) eq 'passed') {
            # (A WHOLE ARRAY THROUGH AN ELEMENT, COUNTED, read where B::SoN pinned
            # it -- `scalar @{ $h->{l} }`: one that is no array there stops, see
            # array_of. Read as a list it stays refused there.)
            local $b->{whole_stop} = $op eq 'PostfixDeref' && $s->is_array_deref
                && blessed( $s->inputs->[0] ) && $s->inputs->[0]->operation eq 'Subscript' && _only_counted($s);
            # (one of an element B::SoN knows is not there -- a missing key --
            # would only stop: perl's count is undef, or its die)
            out('a count of @{} over an element known undef')
                if $b->{whole_stop} && ( $s->inputs->[0]->stamp // '' ) eq 'Undef';   # static type
            # (A WHOLE AGGREGATE THROUGH A REFERENCE B::SoN pinned only to order
            # it, whose value nothing takes -- `my %p = %$h` reads B::SoN's copy
            # beside it -- is not made: its place is passed, what reads at it
            # reads there. See _stood_already.)
            if ( $op eq 'PostfixDeref' && ( $s->sigil // '' ) =~ /\A[\@%]\z/ && !$b->_value_read($s) ) { $b->{stood}{ refaddr($s) } = 1 }
            else { $b->value($s) }
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # A HANDLE'S open, close, readline, eof, select, where it stands. (A
        # format's formline, a tie OR untie -- every later access of the
        # container is the new metaobject's -- and a bless: %T2_BUILTIN's in_place.)
        elsif ($op eq 'Call' && $s->does_handle_io) {
            $b->value($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
        # A CHANGE TO AN ARRAY (push, unshift, shift, pop; a splice is not T2's).
        elsif ($op eq 'Call' && $s->mutates_array) {
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
        # A REFERENCE TO AN ELEMENT, taken where it stands (B::SoN orders it on
        # the array's memory: Ref's taken_where_it_stands): made here, in order
        # -- the element at its index now, made if it is not there.
        elsif ($op eq 'Ref' && $s->taken_where_it_stands) {
            out('a reference to a hash element') if blessed( $s->inputs->[0] ) && $s->inputs->[0]->operation eq 'Subscript' && ( $s->inputs->[0]->can('kind') ? $s->inputs->[0]->kind // '' : '' ) eq 'hash';
            out('a reference to what is no array element') unless $s->is_element_ref;
            $s->each ? $b->array_of($s) : $b->value($s);
            push $b->{passed}->@*, $s;
            $ctl = $s;
        }
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
                # (its __DIE__ handler first, where the program has %SIG: the
                # runtime's die and unwind ask it themselves)
                $full = $b->emit(op => 'DieHook', type => '%Str', inputs => [$full])
                    if $b->special_containers->{'%SIG'};
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
        # WHERE THE PROGRAM READS $_ (a sub called in the body), the global $_
        # is the element: a copy, stored here each pass -- sound only where
        # nothing writes $_ (perl's alias would write the element) -- and what
        # it held before put back when the loop ends (alias_saves).
        elsif ($op eq 'LocalAlias' && ( $s->can('name') ? $s->name // '' : '' ) eq '_') {
            if ($b->reads_topic) {
                out('a $_ aliased where the program reads $_, outside a loop T2 restores it after') unless $b->{alias_restore};
                my $src = $s->inputs->[0];
                # (B::SoN's guarded reference to the element: the element)
                # (B::SoN's reference to the element, guarded or not: the element)
                $src = $src->inputs->[1] if blessed($src) && $src->operation eq 'TernaryExpr' && blessed( $src->inputs->[1] ) && $src->inputs->[1]->operation eq 'Ref';
                $src = $src->inputs->[0] if blessed($src) && $src->operation eq 'Ref';
                $b->emit(op => 'GStore', type => 'void', inputs => [ $b->as( $b->value($src), '%Slot' ) ], attr => { global => $b->global_named('main::_') });
            }
            $ctl = $s;
        }
        # A `local` ON AN ELEMENT ENDS: what it held put back (local_elem).
        elsif ($op eq 'ElemRestore' && ( $s->kind // '' ) eq 'hash') { $b->elem_restore($s); push $b->{passed}->@*, $s; $ctl = $s }
        # `package X;` names the package code after it is in: nothing T2 reads.
        elsif ($op eq 'PackageMark') { $ctl = $s }
        # A CHOICE PINNED WHERE IT RUNS (B::SoN pins one that reads memory, `$n
        # > 1 ? ... : ...` of a package scalar): its value made here, in order.
        # (A FOREACH ALIAS'S GUARDED REFERENCE is never made: its deref is the element.)
        elsif ($op eq 'TernaryExpr') { $b->value($s) unless $s->is_alias_guard; push $b->{passed}->@*, $s; $ctl = $s }
        # (and its bare one, over the foreach's own list: likewise)
        elsif ($op eq 'Ref' && $s->is_alias_ref) { push $b->{passed}->@*, $s; $ctl = $s }
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
                for my $r ( grep { blessed($_) && $_->operation eq 'Ref' } _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret}) ) {
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
        elsif ($op eq 'Call' && ( t2_builtin( $s, 'in_place' ) // '' ) eq 'value') { $b->value($s); $ctl = $s }
        # A lock is a no-op without threads (its operand the variable, not a value).
        elsif ($op eq 'Call' && ( $s->dispatch_kind // '' ) eq 'builtin' && ( $s->name // '' ) eq 'lock') { $ctl = $s }
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
        local $b->{stood} = { ( $b->{stood} // {} )->%* };   # (as its memo: see _stood_already)
        @cv = map { $b->as($b->value( $_->[0]->inputs->[-1] ), $_->[1]) } @in;
        $c = $b->{cur};
        $c->{term} = [ 'br', $join ];
        push @from, $c;
    }
    # NO WAY TO ITS END (its body exits, and nothing in it can die): what
    # follows never runs -- a block of its own, no way into it.
    unless (@from) {
        $join->{dead} = 1;
        $b->{cur} = $join;
        $b->{memo}{ refaddr( $_->[0] ) } = $b->emit(op => 'Undef', type => '%Slot') for grep { $_->[1] eq '%Slot' } @in;
        out('an eval of no way to its end whose value is read') if grep { $_->[1] ne '%Slot' } @in;
        push $b->{passed}->@*, $r, $r->memory_phis;
        return $r;
    }
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
        local $b->{stood} = { ( $b->{stood} // {} )->%* };   # (as its memo: see _stood_already)
        # (AND ITS MEMORY VERSIONS: a read at one is made in the arm or not at
        # all -- made after the join it ran where the arm did not, `defined $r
        # && @$r` counting through an undef $r)
        local $b->{passed} = [ $b->{passed}->@* ];
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $if->inputs->[1], $i );
        $end{$i} = $b->walk($proj{$i});
        # The arm's memo is kept: its phi inputs are read from it (a call made
        # in the arm is that value, not made again).
        $vals{$i} = { block => $b->{cur}, ctl => $end{$i}, memo => $b->{memo}, passed => $b->{passed} };
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
                $b->{passed} = $vals{$go}{passed};
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
        # AN ARM THAT DIED (`die` in a catch) meets nothing: the if goes on
        # from the other.
        if ( my ($died) = grep { $vals{$_}{block}{dead} && !$far{$_}->@* } 0, 1 ) {
            my $go = 1 - $died;
            out('an if both of whose arms die') if $vals{$go}{block}{dead};
            $b->{cur}  = $vals{$go}{block};
            $b->{memo} = $vals{$go}{memo};
            $b->{passed} = $vals{$go}{passed};
            return $end{$go};
        }
        my ($jump) = grep { my $i = $_; $far{$i}->@* == 1 && $far{$i}[0]->reached_by($end{ 1 - $i }) } 0, 1;
        out('an if whose arms do not meet') unless defined $jump;
        my $r = $far{$jump}[0];
        push $b->{jumps}{ refaddr($r) }->@*, { $vals{$jump}->%*, end => $end{$jump} };
        my $go = 1 - $jump;
        $b->{cur}  = $vals{$go}{block};
        $b->{memo} = $vals{$go}{memo};
        $b->{passed} = $vals{$go}{passed};
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
            push @in, [ $b->phi_input( $p, $p->inputs->[$k], $ty ), $arm ];
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
            push @in, [ $b->phi_input( $p, $p->inputs->[$k], $ty ), $pr ];
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

# full_jump() -> the merge the walk goes on from, or undef: when control ran
# out (both arms of an if left), a merge every way into which an arm jumped to
# (a loop's continue block, both its `next` and the body's end reaching it) is
# made, each phi's input in its way's block.
sub full_jump {
    my ($b) = @_;
    for my $k (sort keys $b->{jumps}->%*) {
        my @preds = $b->{jumps}{$k}->@*;
        my ($r) = grep { $_->operation eq 'Region' && refaddr($_) == $k } ( $preds[0]{end}->consumers // [] )->@*;
        next unless $r;
        my @ways = grep { blessed($_) } $r->inputs->@*;
        next if grep { my $in = $_; !grep { refaddr( $_->{end} ) == refaddr($in) } @preds } @ways;
        delete $b->{jumps}{$k};
        my @live = grep { !$_->{block}{dead} } @preds;
        next unless @live;
        ( $b->{cur}, $b->{memo} ) = $b->merge_at( $r, 'join', $b->{memo}, @live );
        push $b->{passed}->@*, $r->memory_phis;
        return $r;
    }
    return undef;
}

# loop($Loop) -> the control node the program continues from: a header of
# phis (each its initial value, then the body's) and the condition, a body
# walked forward back to the header, and an exit.
#
# ITS BODY MAY LEAVE OR GO ROUND FROM INSIDE (`last if C` or `next if C`
# mid-body, B::SoN's If whose arm reaches the exit Region or the latch): its
# ifs see the loop's edges (loopx, see loop_breaks); the ways round merge at
# the latch, and the ways out -- the header's, then each `last` -- at the
# Region the exit Proj feeds, whose phis are made there.
# _head_aggregates($cond) -> the `my @a` / `my %h` lists (ArrayLiteral,
# HashLiteral, not pinned, not yet made) a loop's condition reads, through
# anything but a phi -- none of them the loop's own (made in its body).
sub _head_aggregates {
    my ($b, $cond) = @_;
    my (%seen, @out);
    my @q = ($cond);
    while (defined( my $n = shift @q )) {
        next unless blessed($n) && $n->can('operation') && !$seen{ refaddr($n) }++;
        next if $n->operation eq 'Phi' || $n->is_memory_version;
        if ( $n->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && ( $n->stamp // '' ) =~ /\A(?:Array|Hash)\z/   # static type
                && !$n->is_pinned && !$b->{memo}{ refaddr($n) } && !$b->_needs_unmade_phi($n, {}) ) {
            push @out, $n;
            next;
        }
        push @q, $n->inputs->@*;
    }
    return @out;
}

sub loop {
    my ($b, $L) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } $L->successors_by_input;
    my ($bodyp, $exitp) = @proj{0, 1};
    return $b->loop_breaks($L) if !$bodyp && !$exitp && $b->loop_exit($L);
    out('a loop without a body and an exit') unless $bodyp && $exitp;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($L)
                      && !$_->is_memory } ( $L->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @cond = grep { $_->operation !~ /\A(?:Phi|Proj)\z/ } $L->successors;
    out('a loop condition that is not one value') unless @cond == 1;
    out('a loop phi with other than two ways in') if grep { scalar( $_->inputs->@* ) != 2 } @phis;

    $b->reads_before($_) for $b->{passed}->@*;   # see if_stmt
    # A FOREACH ALIASING $_ where the program reads it: what $_ held saved here,
    # put back at the exit.
    my $save = $b->alias_saves($L);
    local $b->{alias_restore} = $save ? 1 : $b->{alias_restore};
    # A LIST THE LOOP WALKS (map's and grep's over a slice or a range: its
    # count each pass, its elements by index) is made once, before it, as
    # perl makes the list before it walks it.
    $b->value($_) for grep { blessed($_) && $_->operation =~ /\A(?:Slice|Range)\z/ }
        map { $_->inputs->[0] } grep { blessed($_) && $_->operation eq 'Count' } $cond[0]->inputs->@*;
    # A `my` ARRAY OR HASH ITS CONDITION READS (`my @s = ($x); while (@s) {
    # ... pop @s ... }`) was made before the loop, once: made first in the
    # header, it was made again each pass, the pops undone ("runs away").
    $b->value($_) for $b->_head_aggregates($cond[0]);
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
    my ($region) = grep { $_->operation eq 'Region' } ( $exitp->consumers // [] )->@*;
    my $lx = { exit => $region // $exitp, exits => [], latches => [], outer => $b->{loopx}, restores => $save ? 1 : 0 };
    my $head_memo = { $b->{memo}->%* };
    {
        # A value made in the body is the body's: not seen after the loop.
        local $b->{memo} = { $b->{memo}->%* };
        local $b->{stood} = { ( $b->{stood} // {} )->%* };   # (as its memo: see _stood_already)
        local $b->{depth} = ( $b->{depth} // 0 ) + 1;
        local $b->{rx_ok} = _rx_arm( $b->{rx_ok}, $cond[0], 0 );   # (a body runs where its condition held)
        local $b->{loopx} = $lx;
        my $e = $b->walk($bodyp);
        $b->loop_edge( $lx, $e, { block => $b->{cur}, memo => $b->{memo} } )
            || out('a loop body that ends neither going round nor leaving') if defined $e;
    }
    $b->go_round( $lx, $head, $head_memo, \@phis, \@t2 );
    my $exit = $b->new_block('exit');
    $head_end->{term} = [ 'condbr', $cond, $body, $exit ];
    # THE WAYS OUT: the header's (its condition false), and each `last`.
    my @out = grep { !$_->{block}{dead} } $lx->{exits}->@*;
    if (@out) {
        # (each way's value made at its end, in the body: its depth)
        ( $b->{cur}, $b->{memo} ) = do { local $b->{depth} = ( $b->{depth} // 0 ) + 1; $b->merge_at( $region, 'exit', $b->{memo},
            { block => $exit, memo => $b->{memo}, end => $exitp }, @out ) };
    }
    # (what $_ held put back where every way out has met)
    $b->emit(op => 'GStore', type => 'void', inputs => [$save], attr => { global => $b->global_named('main::_') }) if $save;
    # THE EXIT'S MEMORY is a version too: a read at it, before a store after.
    push $b->{passed}->@*, $region->memory_phis if $region;
    return $region // $exitp;
}

# _only_counted($n) -> true where every value use of $n is a Count's (its
# memory and control uses aside: a later read's version, a loop's way in).
sub _only_counted {
    my ($n) = @_;
    for my $u (grep { blessed($_) } ( $n->consumers // [] )->@*) {
        next if $u->operation =~ /\A(?:Loop|Region|If|Proj)\z/ || $u->operation eq 'Phi' && $u->is_memory;
        my @pos = grep { blessed( $u->inputs->[$_] ) && refaddr( $u->inputs->[$_] ) == refaddr($n) } 0 .. $u->inputs->$#*;
        my $mem = $u->memory_operand;
        pop @pos if @pos && blessed($mem) && refaddr($mem) == refaddr($n);
        return 0 if @pos && $u->operation ne 'Count';
    }
    return 1;
}

# reads_topic -> the program reads the global $_ (a sub reading it, called
# in a foreach's body). Refused where anything writes it: perl's $_ is the
# element itself, and a write through it changes the list.
sub reads_topic {
    my ($b) = @_;
    return $b->{reads_topic} //= do {
        my @all = _all_nodes($b->{mop}, $b->{root_ret} // $b->{ret});
        my @top = grep { $_->is_package_scalar && ( $_->symbol // '' ) eq '_' } @all;
        my $reads = grep { my $t = $_; grep { blessed($_) && $_->operation ne 'EntryWrite' } ( $t->consumers // [] )->@* } @top;
        out('a $_ aliased where the program writes $_ (perl writes the element)')
            if $reads && ( grep { $_->operation eq 'EntryWrite' && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->symbol // '' ) eq '_' && $_->inputs->[0]->is_package_scalar } @all
                           or grep { $_->operation =~ /\A(?:RegexSubst|Transliterate|Chomp)\z/ && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->can('symbol') ? $_->inputs->[0]->symbol // '' : '' ) eq '_' } @all );
        out('a $_ aliased where the program reads $_, in a program with an eval') if $reads && $b->{has_eval};
        $reads ? 1 : 0;
    };
}

# alias_saves($Loop) -> what $_ held before the loop (a GLoad), where the
# loop's body aliases $_ and the program reads it; else undef.
sub alias_saves {
    my ($b, $L) = @_;
    my $mine = sub ($a) {
        my @todo = ( $a->inputs->@* );
        for (1 .. 8) {
            my @next;
            for my $x (grep { blessed($_) } @todo) {
                return 1 if $x->operation eq 'Phi' && blessed( $x->region ) && refaddr( $x->region ) == refaddr($L);
                push @next, $x->inputs->@* unless $x->operation eq 'Phi';
            }
            @todo = @next;
        }
        return 0;
    };
    return undef unless grep { $_->operation eq 'LocalAlias' && ( $_->name // '' ) eq '_' && $mine->($_) } +($b->{own_nodes} // [])->@*;
    return undef unless $b->reads_topic;
    return $b->emit(op => 'GLoad', type => '%Slot', attr => { global => $b->global_named('main::_') });
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
    my $lx = { exit => $R, exits => [], latches => [], outer => $b->{loopx} };
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
    $b->go_round( $lx, $head, $head_memo, \@phis, \@t2 );
    # THE EXIT: the ways out merged, with the exit Region's phis.
    my @out = grep { !$_->{block}{dead} } $lx->{exits}->@*;
    out('a loop that never leaves') unless @out;
    ( $b->{cur}, $b->{memo} ) = do { local $b->{depth} = ( $b->{depth} // 0 ) + 1; $b->merge_at( $R, 'exit', $outer_memo, @out ) };
    push $b->{passed}->@*, $R->memory_phis;
    return $R;
}

# go_round($lx, $head, $head_memo, \@phis, \@t2): THE LATCH of the loop $lx
# walked -- the ways round merged (one: that arm itself); its values are the
# head phis' back edges, and it goes back to the head.
sub go_round {
    my ($b, $lx, $head, $head_memo, $phis, $t2) = @_;
    # (what is made here is the body's: in it, each pass -- a `\$x` or a cell
    # made for a back edge is refused there as in the body)
    local $b->{depth} = ( $b->{depth} // 0 ) + 1;
    my @lat = grep { !$_->{block}{dead} } $lx->{latches}->@*;
    out('a loop that never goes round') unless @lat;
    # A WAY ROUND THROUGH A REGION THAT FEEDS THE LATCH (a `redo` in a nested
    # arm): that Region merged first, its merge one way into the next.
    while (1) {
        my %by = map { ( refaddr($_->{region}) => $_->{region} ) } grep { $_->{region} } @lat;
        # (innermost first: a Region no other way round still comes into)
        my %fed = map { ( refaddr($_) => 1 ) } map { $_->out_regions } values %by;
        my ($inner) = grep { my $r = $_; my @o = $r->out_regions; @o == 1 && !$fed{ refaddr($r) } } values %by;
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
        @back = map { $b->as($b->value($phis->[$_]->inputs->[1]), $t2->[$_]->type) } 0 .. $#$phis;
        $lblk = $b->{cur};
    }
    $lblk->{term} = [ 'br', $head ];
    for my $i (0 .. $#$t2) {
        push $t2->[$i]->inputs->@*, $back[$i];
        push $t2->[$i]->attr->{from}->@*, $lblk;
    }
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
# way on, or feeds only a Region that has none: the latch). A LOOP IT IS IN
# (`next OUTER`, `last OUTER` from an inner loop's body) is the one whose
# exit it feeds, or whose latch: the innermost the latch is not after.
sub loop_edge {
    my ($b, $lx, $e, $arm) = @_;
    return 0 unless blessed($e);
    my @r = grep { $_->operation eq 'Region' } ( $e->consumers // [] )->@*;
    for ( my $x = $lx; $x; $x = $x->{outer} ) {
        if ( @r == 1 && refaddr( $r[0] ) == refaddr( $x->{exit} ) ) { $b->leaves_restore($lx, $x); push $x->{exits}->@*, { %$arm, end => $e }; return 1 }
    }
    return 0 if $e->successors;
    if ( !@r ) { push $lx->{latches}->@*, { %$arm, end => $e }; return 1 }
    if ( @r == 1 && !$r[0]->goes_on ) {
        my $x = $lx;
        $x = $x->{outer} while $x->{outer} && $r[0]->reached_by( $x->{exit} );
        $b->leaves_restore($lx, $x);
        push $x->{latches}->@*, { %$arm, end => $e, region => $r[0] };
        return 1;
    }
    return 0;
}

# leaves_restore($lx, $x): an edge from the loop $lx to the loop $x it is in
# (`next OUTER`, `last OUTER`) skips the exit of every loop between: one that
# puts $_ back there (a foreach aliasing it) is refused.
sub leaves_restore {
    my ($b, $lx, $x) = @_;
    for ( my $y = $lx; $y && refaddr($y) != refaddr($x); $y = $y->{outer} ) {
        out('a jump out of a foreach aliasing $_ past its restore') if $y->{restores};
    }
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
            push @in, [ $b->phi_input( $p, $p->inputs->[$k], $ty ), $pr ];
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

1;
