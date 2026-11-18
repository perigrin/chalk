# ABOUTME: How a sub reads its arguments -- `shift @_`, `$_[N]`, `my (...) = @_`, a signature, @_ as a
# ABOUTME: list or written -- for T2's call builder to bind a call's; a shape it cannot bind dies by name.
package Chalk::Target::LLVM::Builder::Args;
use 5.42.0;
use utf8;


# Builder/Calls.pm asks, for a sub it calls:
#
#   my $an = bless {}, 'Chalk::Target::LLVM::Builder::Args';
#   my @reads = eval { $an->_collect_positional_arg_reads($graph, $name) };
#
# and reads what the walk found off $an: _args_read_as_a_list,
# _args_list_after_shifts, _args_written, _args_signature, _args_slurpy.
# (Moved whole from the fallback backend, where it was written for its
# inliner; T2 had read it from there since its calls were its own.)

# store the global $_? A store to it (EntryWrite, Assign), an s///, tr///
# or chomp of it, or a call whose callee is not a direct one known here
# (a method, a code reference) counts.
sub _may_write_topic {
    my ($graph, $seen) = @_;
    $seen //= {};
    return 0 if $seen->{ refaddr($graph) }++;
    my $is_topic = sub ($n) {
        blessed($n) && $n->operation eq 'EntryDef' && ( $n->symbol // '' ) eq '_'
            && ( $n->sigil // '$' ) eq '$' && ( $n->package // 'main' ) eq 'main'
    };
    for my $n ($graph->component) {
        next unless blessed($n);
        my $op = $n->operation;
        return 1 if $op =~ /\A(?:EntryWrite|Assign|RegexSubst|Transliterate|Chomp|ChompValue)\z/
            && grep { $is_topic->($_) } $n->inputs->@*;
        next unless $op eq 'Call';
        my $kind = $n->dispatch_kind // '';
        next if $kind eq 'builtin';
        return 1 unless $kind eq 'direct';
        my $t = $n->can('target') ? $n->target : undef;
        my $g = blessed($t) && $t->can('graph') ? $t->graph : undef;
        return 1 unless $g;
        return 1 if _may_write_topic($g, $seen);
    }
    return 0;
}

# _is_args_array($node) -> bool
#
# Is this EntryDef the ARGUMENT ARRAY `@_`, as opposed to the scalar `$_`?
#
# `@_` has its OWN NODE KIND now, so this is one operation check. It was a
# name test (`var_name eq '_'`), which could not tell `@_` from the scalar `$_`
# -- a `$_` node walked into the @_ handling and was reported as "a list
# assignment `my (...) = @_`" on a source containing none: a correct refusal
# with a wrong diagnosis. A sigil check fixed that; a separate node kind means
# the two cannot be confused even in principle.
sub _is_args_array {
    my ($node) = @_;
    return $node->operation eq 'ArgsSource';
}

# _collect_positional_arg_reads($graph, $name) -> @shift_nodes
#
# Find the callee graph's positional argument reads: Call(builtin, shift) nodes
# whose operand is EntryDef(*, _) (i.e. `shift @_`). Returns them in graph
# order. Dies (loud GAP) on any OTHER access to @_ that inlining cannot bind:
# a `pop @_`, a list assignment `my (...) = @_`, or a `$_[N]` subscript — those
# shapes do not carry the positional binding the caller's args need.
sub _collect_positional_arg_reads {
    my ($self, $graph, $name) = @_;

    my @shifts;
    my @list_assigns; # `my (...) = @_`
    my %subscripts;   # index => the $_[index] Subscript node
    my %params;       # index => the Parameter node (a DECLARED signature)
    my $args_array;   # @_ itself, when the callee reads it as a list
    $self->{_args_read_as_a_list} = undef;
    $self->{_args_list_after_shifts} = undef;
    my (%written, $written_src);   # `$_[N] = ...`: N => 1, and @_
    $self->{_args_written} = undef;
    $self->{_args_signature} = 0;
    $self->{_args_slurpy}    = undef;
    for my $n ($graph->component) {
        next unless blessed($n);
        my $op = $n->operation;

        # A DECLARED PARAMETER. Its index IS its position, so this needs no
        # recovery at all -- which is the point. `shift @_` and `$_[N]` both
        # cap at ONE argument here, for reasons that do not apply: multiple
        # shifts hash-cons to a single node and lose their order, and the
        # subscript path was written for the single-arg case. A Parameter
        # carries its own index, so N of them order themselves.
        if ($op eq 'Parameter') {
            $params{ $n->index } = $n;
            next;
        }

        # `shift @_` / `pop @_`: the arg-read we can bind (shift only).
        if ($op eq 'Call' && ( $n->builtin_family // '' ) eq 'array') {
            my ($operand) = grep { blessed($_) } $n->inputs->@*;
            next unless defined $operand && _is_args_array($operand);
            die "GAP: direct call to '$name': callee reads \@_ via `pop` — only "
              . "positional `shift \@_` argument binding is inlined (`pop \@_` "
              . "reads from the end, which inlining does not model)."
                if $n->builtin_kind eq 'takes_last';
            push @shifts, $n;
        }
        # `my (...) = @_`: an Assign whose last input is @_ and whose others
        # are its targets, in order -- each target IS its argument's position.
        elsif ($op eq 'Assign' && $n->inputs->@* >= 2
                && blessed($n->inputs->[-1]) && _is_args_array($n->inputs->[-1])) {
            # `my @p = @_` is a copy of the list, not a position.
            my @t = $n->inputs->@[ 0 .. $n->inputs->$#* - 1 ];
            next if @t == 1 && blessed($t[0]) && $t[0]->operation eq 'PadAccess'
                && ( $t[0]->sigil // '' ) eq '@';
            push @list_assigns, $n;
        }
        # `$_[N]`: a positional subscript on @_, i.e. Subscript(ArgsSource,
        # Constant(N), Mem). Bindable: the caller's Nth argument substitutes for
        # the whole Subscript node during inlining (keyed by refaddr, like a
        # `shift @_`). Collected by index so a single `$_[0]` reader binds arg 0.
        #
        # The container used to be a string Constant("_") -- the array spelled
        # as its own NAME, which is why this test read a literal.
        elsif ($op eq 'Subscript') {
            my @in = grep { blessed($_) } $n->inputs->@*;
            my ($container, $index) = @in;
            next unless defined $container
                && $container->operation eq 'ArgsSource';
            next unless defined $index && $index->operation eq 'Constant'
                && $index->can('value') && defined $index->value
                && $index->value =~ /^\d+$/;
            $subscripts{ $index->value } = $n;
        }
        # `my (...) = @_`: @_ accessed as an aggregate. The producer does not
        # connect the list-assign to the caller's args in the graph, so inlining
        # cannot bind it — GAP loudly rather than miscompile.
        elsif ($op eq 'ArgsSource') {
            # Two consumers ARE bindable and are handled above: a `shift @_`
            # Call, and a `$_[N]` Subscript. Anything else (a list-assign, a
            # deref) is an @_ shape inlining cannot bind.
            #
            # The Subscript exemption is new with the ArgsSource node: `$_[0]`
            # used to reach @_ through a string Constant("_") container, so it
            # never arrived here at all. Now that every spelling of @_ names the
            # same node, this guard sees them all -- and must not refuse the one
            # the arg binder already knows how to handle.
            my @other = grep {
                blessed($_)
                    && !( $_->operation eq 'Call'
                        && ( $_->builtin_kind // '' ) eq 'takes_first' )
                    && $_->operation ne 'Subscript'
                    && !( $_->operation eq 'Assign'
                          && refaddr($_->inputs->[-1] // 0) == refaddr($n) )
            } $n->consumers->@*;
            # READ AS A LIST -- counted, walked, joined, copied -- @_ is an
            # array of the call's arguments, built at the call (see
            # the call builder, Builder/Calls.pm). Only reads: a copy cannot carry a write
            # back to the caller's variable, nor a shift out of the list.
            if (@other) {
                for my $c (@other) {
                    my $cop = $c->operation;
                    # Counted, tested, or copied into a hash: reads.
                    next if $cop =~ /\A(?:Count|Exists|HashLiteral)\z/;
                    # Read as a number or a truth: its count.
                    next if $cop eq 'Coerce' && ( $c->to_repr // '' ) =~ /\A(?:Int|Num|Str|Boolean)\z/;
                    next if $cop eq 'Call' && $c->reads_its_list;
                    next if $cop eq 'Assign' && blessed($c->inputs->[0])
                        && refaddr($c->inputs->[-1]) == refaddr($n)
                        && $c->inputs->[0]->operation eq 'PadAccess'
                        && ( $c->inputs->[0]->sigil // '' ) eq '@';
                    die "GAP: direct call to '$name': callee hands \@_ to a $cop"
                      . ( $cop eq 'Call' ? ' ' . ( $c->name // '?' ) : '' )
                      . " -- inlining reads \@_ as a list of the arguments, and "
                      . "that may write it.\n";
                }
                $args_array = $n;
            }
            # A WRITE THROUGH AN ELEMENT reaches the caller's variable, which
            # a copy cannot: `$_[0] = 9` is refused whatever else reads @_. So
            # is one through a reference to it -- the alias a foreach takes of
            # an iterator it hands to a call -- found by following the
            # reference through what passes it on to a store's target.
            for my $sub (grep { blessed($_) && $_->operation eq 'Subscript' } $n->consumers->@*) {
                my @q = ($sub);
                my %seen;
                while (defined(my $v = shift @q)) {
                    next if $seen{ refaddr($v) }++;
                    for my $u (($v->consumers // [])->@*) {
                        next unless blessed($u);
                        my $uop = $u->operation;
                        # A STORE TO `$_[N]` ITSELF, N a constant, is written back
                        # to the caller's argument after the inline (copy-out,
                        # the call builder, Builder/Calls.pm). One through a reference is not.
                        if ($uop eq 'Assign' && refaddr($v) == refaddr($sub)
                                && refaddr($u->inputs->[0] // 0) == refaddr($v)) {
                            my $ix = $sub->inputs->[1];
                            if (blessed($ix) && $ix->operation eq 'Constant'
                                    && ($ix->value // '') =~ /\A\d+\z/) {
                                $written{ $ix->value } = 1;
                                $written_src = $n;
                                next;
                            }
                        }
                        # `for (@_)` / `map {...} @_` ALIAS $_ to each element:
                        # a write only where something may store $_ meanwhile.
                        die "GAP: direct call to '$name': callee writes \$_[N] -- an "
                          . "alias of the caller's argument, which inlining does not "
                          . "write back.\n"
                            if ( $uop eq 'Assign' && refaddr($u->inputs->[0] // 0) == refaddr($v) )
                            || ( $uop eq 'LocalAlias' && _may_write_topic($graph) );
                        push @q, $u if $uop =~ /\A(?:Ref|TernaryExpr|PostfixDeref)\z/;
                    }
                }
            }
        }
    }

    # @_ WRITTEN is read as the array it is: every `$_[N]` reads the array the
    # call builds, which the callee's stores change, and the call copies the
    # written elements back. A positional binding would read the value from
    # before the store.
    if (%written) {
        die "GAP: direct call to '$name': callee writes \@_ and binds it by "
          . "`shift` or `my (...) = \@_` -- only `\$_[N]` reads see its stores.\n"
            if @shifts || @list_assigns || %params;
        $self->{_args_written} = [ sort { $a <=> $b } keys %written ];
        $self->{_args_read_as_a_list} = $written_src;
        return ();
    }

    if ($args_array) {
        # SHIFTS FIRST, THEN THE LIST: `shift; bless {@_}` reads the arguments
        # past the shifted ones -- when every reader of the list comes after
        # every shift in control order. A reader with no control position
        # (or one before a shift) has no such order.
        if (@shifts) {
            my %is_shift = map { refaddr($_) => 1 } @shifts;
            for my $c (grep { blessed($_) && !$is_shift{ refaddr($_) } } $args_array->consumers->@*) {
                # Before it in control order, or in memory order (`join("-",
                # @_)` takes the shift as its memory).
                my %before;
                for (my $k = $c->can('control_in') ? $c->control_in : undef; blessed($k);
                     $k = $k->can('control_in') ? $k->control_in : undef) {
                    last if $before{ refaddr($k) }++;
                }
                my $mem = sub ($n) { $n->can('memory_input') && $n->memory_input ? $n->inputs->[-1] : undef };
                for (my $k = $mem->($c); blessed($k); $k = $mem->($k)) {
                    last if $before{ refaddr($k) }++;
                }
                die "GAP: direct call to '$name': callee shifts \@_ and reads it as a "
                  . "list -- the list after a shift is not the call's arguments.\n"
                    if grep { !$before{ refaddr($_) } } @shifts;
            }
            $self->{_args_list_after_shifts} = scalar @shifts;
        }
        $self->{_args_read_as_a_list} = $args_array;
    }

    # A DECLARED SIGNATURE WINS, and it is not capped at one argument. The
    # parameters are returned in index order, so the caller's positional
    # binding (arg_reads[$i] <- arg_refs[$i]) lines up by construction.
    $self->{_args_signature} = %params ? 1 : 0;
    if (%params) {
        die "GAP: direct call to '$name': callee mixes declared signature "
          . "parameters with `shift \@_` / `\$_[N]` positional reads."
            if @shifts || %subscripts;

        # BY INDEX, holes and all: a hole is a parameter the body never
        # reads (`($, $phi)`), and each read one keeps its own position.
        my ($max) = sort { $b <=> $a } keys %params;
        # A SLURPY LAST (`@rest`, `%opts`) takes every argument past the
        # scalars, and is no one position: bound by the call to an array (a
        # hash) of them (_args_slurpy).
        if (( $params{$max}->sigil // '$' ) =~ /\A[\@%]\z/) {
            $self->{_args_slurpy} = delete $params{$max};
            $max--;
        }
        return map { $params{$_} } 0 .. $max;
    }

    # ONE POSITIONAL STYLE PER CALLEE: shifts, `$_[N]`, or one `my (...) =
    # @_`. Mixed, which read takes which argument depends on order the graph
    # does not carry, so it is refused rather than guessed.
    die "GAP: direct call to '$name': callee mixes `shift \@_`, `\$_[N]` and "
      . "`my (...) = \@_` positional reads -- inlining binds one style per callee."
        if (@shifts ? 1 : 0) + (%subscripts ? 1 : 0) + (@list_assigns ? 1 : 0) > 1;

    # `my ($a, $b) = @_`: the targets, in order, are the arguments. A slurpy
    # target (`@rest`, `%args`) takes all that remain and is no one position.
    if (@list_assigns) {
        die "GAP: direct call to '$name': callee assigns \@_ to a list "
          . scalar(@list_assigns) . " times -- inlining binds one."
            if @list_assigns > 1;
        my @inputs  = $list_assigns[0]->inputs->@*;
        my @targets = @inputs[ 0 .. $#inputs - 1 ];
        # A SLURPY ARRAY LAST takes every argument after the scalars: bound by
        # the call to an array of them (Builder/Calls.pm, _args_slurpy).
        # ...or A SLURPY HASH, its pairs.
        if (@targets && blessed($targets[-1]) && $targets[-1]->operation eq 'PadAccess'
                && ( $targets[-1]->sigil // '' ) =~ /\A[\@%]\z/) {
            $self->{_args_slurpy} = pop @targets;
        }
        for my $t (@targets) {
            die "GAP: direct call to '$name': callee's `my (...) = \@_` has a "
              . "slurpy target -- an array or hash takes every remaining "
              . "argument, which inlining does not bind."
                unless blessed($t) && $t->operation eq 'PadAccess'
                    && ( $t->can('sigil') ? ($t->sigil // '$') : '$' ) eq '$';
        }
        return @targets;
    }

    # `$_[N]`: bound by index, which must run from 0 with no hole -- a
    # positional binding past a hole would shift every later argument.
    if (%subscripts) {
        # BY INDEX, holes and all: a method reads `$_[1]` and never its
        # invocant. A hole is a position nothing reads (undef here).
        my ($max) = sort { $b <=> $a } keys %subscripts;
        return map { $subscripts{$_} } 0 .. $max;
    }

    # SHIFTS ARE ORDERED BY THEIR MEMORY. Each `shift @_` takes the shift
    # before it as its memory input -- that chain IS their order, so several
    # bind as surely as one. (They were said to hash-cons and lose it; they do
    # not.) A chain that does not cover every shift -- one under a branch --
    # has no single order and is refused.
    return @shifts if @shifts <= 1;
    my %is_shift = map { refaddr($_) => $_ } @shifts;
    my ($first) = grep {
        my $m = $_->inputs->[1];
        !( blessed($m) && $is_shift{ refaddr($m) } )
    } @shifts;
    my @ordered;
    my %next = map {
        my $m = $_->inputs->[1];
        ( blessed($m) && $is_shift{ refaddr($m) } ) ? ( refaddr($m) => $_ ) : ()
    } @shifts;
    for (my $c = $first; defined $c; $c = $next{ refaddr($c) }) {
        push @ordered, $c;
        last if @ordered > @shifts;
    }
    die "GAP: direct call to '$name': callee's " . scalar(@shifts)
      . " `shift \@_` reads do not form one memory chain -- their order is not "
      . "in the graph (a shift under a branch?)."
        unless @ordered == @shifts
            && scalar(grep { !blessed($_->inputs->[1]) || !$is_shift{ refaddr($_->inputs->[1]) } } @shifts) == 1;
    return @ordered;
}

1;
