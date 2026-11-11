# ABOUTME: B backend for script/regex-census.pl: every regex op perl compiled in
# ABOUTME: the program file (main, subs, closures), one tab-separated row each.
package B::RegexCensus;
use v5.36;
use B qw(main_root main_cv svref_2object class);

# A row: FILE  LINE  OP  FLAGS  FEATURES(;)  PATTERN
my ( $FILE, $LINE, %seen_cv );
my %OP = ( match => 'match', qr => 'qr', subst => 'subst', split => 'split', trans => 'trans', transr => 'trans' );
my @FLAG = ( [ g => B::PMf_GLOBAL() ], [ c => B::PMf_CONTINUE() ], [ r => B::PMf_NONDESTRUCT() ], [ e => B::PMf_EVAL() ],
             [ i => B::PMf_FOLD() ], [ m => B::PMf_MULTILINE() ], [ s => B::PMf_SINGLELINE() ], [ x => B::PMf_EXTENDED() ] );

sub compile (@) {
    return sub {
        $FILE = $0;
        walk_cv( main_cv, main_root );
        walk_stash( 'main::', {} );
    };
}

# Every named sub (and method) whose body is in this file.
sub walk_stash ( $stash, $done ) {
    return if $done->{$stash}++;
    no strict 'refs';
    for my $name ( sort keys %$stash ) {
        if ( $name =~ /::\z/ ) { walk_stash( $stash eq 'main::' ? $name : "$stash$name", $done ) unless $name eq 'main::'; next }
        # (by full name: a stash entry may be the sub itself, not a glob)
        my $full = "$stash$name";
        next unless $name =~ /\A\w+\z/ && defined &{$full};
        my $cv = svref_2object( \&{$full} );
        next unless ( $cv->FILE // '' ) eq $FILE && !$cv->XSUB && ${ $cv->ROOT };
        walk_cv( $cv, $cv->ROOT );
    }
}

sub walk_cv ( $cv, $root ) {
    return if $seen_cv{$$cv}++ || !$$root;
    walk_op( $root, $cv );
}

sub walk_op ( $op, $cv ) {
    my $name = $op->name;
    $LINE = $op->line if $name eq 'nextstate' || $name eq 'dbstate';
    # A CLOSURE (sub {...}): its CV is in its enclosing sub's pad.
    if ( $name eq 'anoncode' || $name eq 'anonconst' ) {
        my $sub = ( $cv->PADLIST->ARRAY )[1]->ARRAYelt( $op->targ );
        walk_cv( $sub, $sub->ROOT ) if class($sub) eq 'CV';
    }
    row( $op, $name ) if $OP{$name};
    if ( $op->flags & B::OPf_KIDS ) {
        for ( my $k = $op->first; $$k; $k = $k->sibling ) { walk_op( $k, $cv ) }
    }
    # s///e: the replacement is code
    if ( $name eq 'subst' && ${ $op->pmreplroot } && class( $op->pmreplroot ) ne 'NULL' ) { walk_op( $op->pmreplroot, $cv ) }
}

sub row ( $op, $name ) {
    my ( @flags, %feat, $pat );
    if ( $name =~ /\Atrans/ ) { %feat = ( 'tr' => 1 ); $pat = '' }
    else {
        my $pf = $op->pmflags;
        @flags = map { $_->[0] } grep { $pf & $_->[1] } @FLAG;
        my @rt = grep { $_->name eq 'regcomp' } kids($op);
        if (@rt) {
            $feat{'built at run time'} = 1;
            $feat{'\\Q of a variable'} = 1 if grep { $_->name eq 'quotemeta' } descendants( $rt[0] );
            # A VARIABLE INTERPOLATED (not inside a quotemeta): its value is
            # the pattern's -- folded where B::SoN knows it, a qr value, or
            # built at run time.
            $feat{'interpolates a variable'} = 1 if _interpolates( $rt[0] );
            $pat = '';
        }
        else {
            $pat = $op->precomp // '';
            %feat = features($pat);
        }
    }
    $pat =~ s/\t/\\t/g; $pat =~ s/\n/\\n/g;
    print join( "\t", $FILE, $LINE // 0, $OP{$name}, join( ' ', @flags ), join( ';', sort keys %feat ), $pat ), "\n";
}

sub kids ($op) {
    my @k;
    return @k unless $op->flags & B::OPf_KIDS;
    for ( my $k = $op->first; $$k; $k = $k->sibling ) { push @k, $k }
    return @k;
}
sub descendants ($op) { return map { ( $_, descendants($_) ) } kids($op) }

# _interpolates($op) -> a variable read under it, not under a quotemeta
sub _interpolates ($op) {
    return 0 if $op->name eq 'quotemeta';
    return 1 if $op->name =~ /\A(?:padsv|gvsv|rv2sv|aelem|helem|aelemfast|aelemfast_lex|entersub|padsv_store)\z/;
    return scalar grep { _interpolates($_) } kids($op);
}

# features(PATTERN) -> the features a compiled pattern uses (escapes,
# classes and groups read as perl reads them: a | in a class is a byte).
sub features ($p) {
    my %f;
    my @c = split //, $p;
    for ( my $i = 0; $i < @c; $i++ ) {
        my $ch = $c[$i];
        if ( $ch eq '\\' ) {
            my $e = $c[ ++$i ] // '';
            $f{ esc($e) } = 1 if esc($e);
            next;
        }
        if ( $ch eq '[' ) {
            $f{'class [ ]'} = 1;
            $i++;
            $i++ if ( $c[$i] // '' ) eq '^';
            $i++ if ( $c[$i] // '' ) eq ']';    # a ] first is a byte
            for ( ; $i < @c && $c[$i] ne ']'; $i++ ) {
                if ( $c[$i] eq '\\' ) { my $e = $c[ ++$i ] // ''; $f{'\\d \\w \\s'} = 1 if $e =~ /[dDwWsS]/; $f{'\\h \\v \\R \\X \\K'} = 1 if $e =~ /[hHvV]/; $f{'\\p{..} \\N'} = 1 if $e =~ /[pP]/; next }
                if ( $c[$i] eq '[' && ( $c[ $i + 1 ] // '' ) =~ /[:.=]/ ) {
                    $f{'posix [:alpha:]'} = 1;
                    $i++ while $i < @c && !( $c[$i] eq ']' && $c[ $i - 1 ] =~ /[:.=]/ );
                }
            }
            next;
        }
        if ( $ch eq '(' ) {
            if ( ( $c[ $i + 1 ] // '' ) ne '?' ) { $f{'group ( )'} = 1; next }
            my $rest = join '', @c[ $i + 2 .. ( $i + 5 < $#c ? $i + 5 : $#c ) ];
            $f{ $rest =~ /\A:/            ? 'non-capture'
              : $rest =~ /\A[=!]/         ? 'lookahead'
              : $rest =~ /\A<[=!]/        ? 'lookbehind'
              : $rest =~ /\A(?:<\w|P<|')/ ? 'named capture'
              : $rest =~ /\A\??\{/        ? 'code block'
              : $rest =~ /\A#/            ? 'comment (?#'
              : $rest =~ /\A\|/           ? 'branch reset (?|'
              : $rest =~ /\A>/            ? 'atomic (?>'
              : $rest =~ /\A(?:R|\d|&|P>|[+-]\d)/ ? 'recursion'
              :                             'inline mods (?i)' } = 1;
            $i++;
            next;
        }
        if ( $ch eq ')' ) {
            $f{'quantified group'} = 1 if ( $c[ $i + 1 ] // '' ) =~ /[*+?]/ || ( join '', @c[ $i + 1 .. $#c ] ) =~ /\A\{\d*,?\d*\}/;
            next;
        }
        if ( $ch eq '|' ) { $f{alternation} = 1; next }
        if ( $ch eq '.' ) { $f{'. any'} = 1; next }
        if ( $ch eq '^' ) { $f{'^ anchor'} = 1; next }
        if ( $ch eq '$' ) { $f{'$ anchor'} = 1; next }
        my $q;
        if ( $ch =~ /[*+?]/ ) { $f{'quant * + ?'} = 1; $q = 1 }
        elsif ( $ch eq '{' && ( join '', @c[ $i .. $#c ] ) =~ /\A\{(\d*,?\d*)\}/ && length $1 && $1 ne ',' ) {
            $f{'counted {n,m}'} = 1;
            $i += length($1) + 1;
            $q = 1;
        }
        if ($q) {
            my $n = $c[ $i + 1 ] // '';
            if    ( $n eq '?' ) { $f{lazy} = 1; $i++ }
            elsif ( $n eq '+' ) { $f{possessive} = 1; $i++ }
        }
    }
    return %f;
}

sub esc ($e) {
    return $e =~ /[bB]/ ? '\\b \\B'
         : $e =~ /[AzZ]/ ? '\\A \\z \\Z'
         : $e eq 'G' ? '\\G'
         : $e =~ /[dDwWsS]/ ? '\\d \\w \\s'
         : $e =~ /[hHvVRXK]/ ? '\\h \\v \\R \\X \\K'
         : $e =~ /[pPN]/ ? '\\p{..} \\N'
         : $e =~ /[1-9gk]/ ? 'backreference'
         : undef;
}

1;
