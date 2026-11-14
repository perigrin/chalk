# ABOUTME: The LLVM builder's regexes, each a graph of its own: matches, split, s///, tr,
# ABOUTME: pos(), qr//, and the in-place string writes (methods of Chalk::Target::LLVM::Builder).
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Builder;

use Scalar::Util qw(blessed refaddr);

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

1;
