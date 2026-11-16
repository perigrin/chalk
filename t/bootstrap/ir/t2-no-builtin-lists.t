#!/usr/bin/env perl
# ABOUTME: Guard: the targets keep no list or table of builtin names. Perl's facts about a
# ABOUTME: builtin are the IR's (Call methods over BuiltinTable/TypeLibrary); T2 asks them.

use 5.42.0;
use utf8;
use Test::More;
use File::Find;
use Pod::Functions ();
use lib "lib";
use Chalk::Grammar::Perl::BuiltinTable;

# A BUILTIN-NAME ALTERNATION: a call's name (->name, or a $name taken from
# one) matched against /\A(?:a|b|...)\z/. Such a set says something about the
# builtins it names -- that is a Perl fact, and lives on T1's side
# (Chalk::Grammar::Perl::BuiltinTable, read through Chalk::IR::Node::Call).
my $NAME_ALT = qr{
    (?: ->name \s* (?: // \s* (?: '' | q\{\} ) \s* \) )?   # a call's name, ( $c->name // '' )
      | \$name\b )                                        # or a $name taken from one
    \s* =~ \s* / \\A \( \? : [a-z_]+ \|                   # matched against an alternation of names
}x;

# A TABLE KEYED BY BUILTIN NAMES: a hash whose keys are perl's builtins
# (`our %T = ( join => {...}, map { ( $_ => ... ) } qw(shift pop) )`). What it
# holds of each is a fact of perl's about that builtin, or a choice of the
# target's made by name -- the first is T1's (BuiltinTable), the second is to
# be keyed by a T1 category or an IR node class, never by a name. Two or more
# of perlfunc's names among a hash literal's keys is such a table.
my %BUILTIN = map { ( $_ => 1 ) } grep { /\A[a-z_]+\z/ } keys %Pod::Functions::Type;
my $HASH_LIT = qr{ (?: my | our ) \s+ % (\w+) \s* = \s* ( \( (?: [^()]++ | (?-1) )* \) ) }x;

# builtin_keys($perl_source) -> ([ $hash_name, @builtin_keys ], ...) for each
# hash literal keyed by two or more builtin names.
sub builtin_keys ($src) {
    my @t;
    while ( $src =~ /$HASH_LIT/g ) {
        my ( $h, $body ) = ( $1, $2 );
        my %k;
        $k{$1} = 1 while $body =~ / (?<! [\$\@%\w] ) ([a-z_]+) \s* => /xg;   # a bareword key
        while ( $body =~ / qw \s* [(\[{\/] ( [^)\]}\/]* ) /xg ) { $k{$_} = 1 for split ' ', $1 }   # keys made from a qw()
        my @b = sort grep { $BUILTIN{$_} } keys %k;
        push @t, [ $h, @b ] if @b >= 2;
    }
    return @t;
}

# A BUILTIN NAME COMPARED: a call's name (->name, or a $name taken from one)
# compared with eq or ne to one of perl's builtins -- perlfunc's, or one
# B::SoN names a builtin by (ftdir, sselect, reftype_of_ref ...: those
# BuiltinTable holds facts of). What the comparison decides is a fact of
# perl's about that builtin (its arity, context, side effect, what it
# returns, its family: T1's, read through a Call method) or which emitter
# lowers it (to be chosen by such a fact, or by the IR node's class). Either
# way the target names no builtin.
$BUILTIN{$_} = 1 for Chalk::Grammar::Perl::BuiltinTable::names();
my $NAME_EQ = qr{
    (?: ->name \b (?: \s* // \s* (?: '' | q\{\} ) \s* \) )?   # a call's name, ( $c->name // '' )
      | \$name\b )                                          # or a $name taken from one
    \s* (?: eq | ne ) \s* (['"]) ([a-z_]+) \1               # compared to a string
}x;

# builtin_compared($line) -> the builtin names it compares a call's name to.
sub builtin_compared ($l) {
    my @b;
    while ( $l =~ /$NAME_EQ/g ) { push @b, $2 if $BUILTIN{$2} }
    return @b;
}

my ( @alts, @tables, @eqs );
find( { no_chdir => 1, wanted => sub {
    return unless /\.pm\z/;
    my $file = $_;
    open my $fh, '<:utf8', $file or die "$file: $!";
    my $src = do { local $/; <$fh> };
    my $n = 0;
    for my $l ( split /\n/, $src ) {
        $n++;
        next unless $file =~ m{\Alib/Chalk/Target/LLVM/};
        my $at = "$file:$n: " . ( $l =~ s/^\s+//r =~ s/\s+\z//r );
        push @alts, $at if $l =~ $NAME_ALT;
        push @eqs, $at if builtin_compared($l);
    }
    push @tables, map { "$file: %$_->[0] keyed by " . join ' ', $_->@[ 1 .. $_->$#* ] } builtin_keys($src);
} }, 'lib/Chalk/Target' );

is( scalar @alts, 0, 'no builtin-name alternation in lib/Chalk/Target/LLVM' )
    or diag join "\n", @alts;
is( scalar @eqs, 0, 'no call name compared to a builtin\'s in lib/Chalk/Target/LLVM' )
    or diag join "\n", scalar(@eqs) . ' comparisons:', @eqs;
is( scalar @tables, 0, 'no table keyed by builtin names in lib/Chalk/Target' )
    or diag join "\n", @tables;

# The guard sees what it is for (a pattern that matched nothing would pass anything).
like( q{( $u->name // '' ) =~ /\A(?:push|unshift|join)\z/}, $NAME_ALT, 'the guard sees a name alternation' );
like( q{$name =~ /\A(?:open|close)\z/}, $NAME_ALT, 'and one over a $name' );
unlike( q{$f =~ /\A(?:sitofp|zext|fptosi)\z/}, $NAME_ALT, 'an LLVM opcode set is not a builtin list' );
unlike( q{( $u->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/}, $NAME_ALT, 'nor a dispatch kind' );

is_deeply( [ builtin_compared(q~if ($op eq 'Call' && ( $v->dispatch_kind // '' ) eq 'builtin' && ( $v->name // '' ) eq 'caller') {~) ],
    ['caller'], 'the guard sees a call name compared to a builtin\'s' );
is_deeply( [ builtin_compared(q~if ($name eq 'shift' || $n->name ne 'pop') {~) ], [qw(shift pop)], 'eq and ne, a $name and a bare ->name' );
is_deeply( [ builtin_compared(q~my $op = $v->name eq 'ftdir' ? 'FtDir' : 'Chdir';~) ], ['ftdir'], 'and a name B::SoN gives a builtin' );
is_deeply( [ builtin_compared(q~elsif ($op eq 'Call' && ( $s->name // '' ) eq 'set_arylen') {~) ], ['set_arylen'], 'set_arylen (`$#a = N`) too' );
is_deeply( [ builtin_compared(q~if ( ( $c->name // '' ) eq 'new' && $k eq 'method' ) {~) ], [], 'a method\'s name is not one' );
is_deeply( [ builtin_compared(q~return 0 if ( $c->can('want') ? $c->want // '' : '' ) eq 'scalar';~) ], [], 'a context named like a builtin is not one' );
is_deeply( [ builtin_compared(q~$_->operation eq 'Constant' && ( $_->const_type // '' ) eq 'undef'~) ], [], 'nor a constant\'s type' );
is_deeply( [ builtin_compared(q~return undef if $fam eq 'scalar';~) ], [], 'nor a family' );
is_deeply( [ builtin_compared(q~$_->operation eq 'LocalAlias' && ( $_->name // '' ) eq '_'~) ], [], 'nor a variable\'s name' );

is_deeply( [ builtin_keys(q{our %T = ( ( map { ( $_ => { type => 1 } ) } qw(shift pop) ), join => { x => 1 } );}) ],
    [ [ 'T', qw(join pop shift) ] ], 'the guard sees a table keyed by builtin names, qw() keys too' );
is_deeply( [ builtin_keys(q{my %mode = (uc => 0, lc => 1, ucfirst => 2, lcfirst => 3);}) ],
    [ [ 'mode', qw(lc lcfirst uc ucfirst) ] ], 'and a small one, a my' );
is_deeply( [ builtin_keys(q{my %ARITH = (Add => 'add', Subtract => 'sub', Multiply => 'mul');}) ],
    [], 'a table keyed by IR node classes is not one' );
is_deeply( [ builtin_keys(q{my %F = (number => 'number_value', path => 'path_value');}) ],
    [], 'nor one keyed by T1 categories' );
is_deeply( [ builtin_keys(q{my %V = (a => 'join', b => 'shift');}) ],
    [], 'nor one whose values (not keys) are names' );

done_testing;
