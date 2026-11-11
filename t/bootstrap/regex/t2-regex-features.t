# ABOUTME: the regex features chalk's lib/ and t/ use, each through T2 as its
# ABOUTME: own graph (a state machine), answering as perl; the rest refused by name.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}
sub _q ($s) { $s =~ s/([\\'])/\\$1/g; $s =~ s/\n/' . "\\n" . '/g; return "'$s'" }

# Each pattern (with flags) against subjects: y or n, and the groups it took.
sub same ( $name, $re, @subj ) {
    my $src = join '', map { "my \$s$_ = \$ENV{S$_} // " . _q( $subj[$_] ) . ";\n" } 0 .. $#subj;
    $src .= join '', map { "print \$s$_ =~ $re ? 'y' : 'n';\n" } 0 .. $#subj;
    $src .= "print qq{\\n};\n";
    my $r = tap($src);
    is $r->{verdict}, 'SAME', "$name: $re as perl through T2" or diag $r->{why} // explain $r;
}

# ALTERNATION, tried in order; (?:...) groups it; a group quantified.
same alternation => '/cat|dog|bird/', qw(cat dogs abird cow);
same 'alternation in a group' => '/^(?:ab|a)c$/', qw(abc ac abbc);
same 'quantified group' => '/^(?:ab)+$/', qw(ab abab aba abba), '';
same 'quantified alternation' => '/^(?:a|bc)*d$/', qw(d abcad bcbcd abd);
same 'counted group' => '/^(?:x,){2,3}y$/', qw(x,y x,x,y x,x,x,y x,x,x,x,y);
same 'backtracking into a group' => '/^(a+|b)+ab$/', qw(aab bab aaab abab);
same 'empty-matching loop' => '/^(?:a*)*b/', qw(b aab c);

# \b \B
same 'word boundary' => '/\bfoo\b/', ( 'foo', 'a foo b', 'food', 'xfoo', 'foo.' );
same 'not a boundary' => '/\Boo\B/', qw(fool oo foo);

# FLAGS /i /m /s /x
same '/i' => '/hello/i', qw(HeLLo xHELLOx help);
same '/i class' => '/^[a-c]+$/i', qw(AbC abd ABC);
same '/m' => '/^b$/m', ( "a\nb\nc", "a\nbc", 'b' );
same '/s' => '/a.b/s', ( "a\nb", 'axb', 'ab' );
same 'no /s' => '/a.b/', ( "a\nb", 'axb' );
same '/x' => '/ a \d+ # digits
               b /x', qw(a12b a b);

# POSIX CLASSES (ASCII's)
same 'posix' => '/^[[:alpha:]][[:digit:]]+$/', qw(a12 12 ab1);
same 'posix ascii' => '/^[[:ascii:]]+$/', ( 'ab c', "a\tb" );

# LAZY
same 'lazy star' => '/^a.*?b/', qw(axbxb ab a);
same 'lazy counted' => '/^x{2,4}?y/', qw(xxy xxxxy xy);

# LOOKAROUND
same lookahead => '/foo(?=bar)/', qw(foobar foobaz);
same 'negative lookahead' => '/foo(?!bar)/', qw(foobar foobaz foo);
same lookbehind => '/(?<=\$)\d+/', qw($12 12 x$3);
same 'negative lookbehind' => '/(?<!x)y/', qw(xy ay y);

# CAPTURES through groups, alternation, quantifiers
for my $c (
    [ '"key = value"', 'print "<$1><$2>\n" if $s =~ /^(\w+)\s*=\s*(\w+)$/;' ],
    [ '"aXbXc"',       'print "<$1>\n" if $s =~ /^(?:(\w)X)+c$/;' ],
    [ '"dog"',         'print defined $1 ? "<$1>" : "u", defined $2 ? "<$2>" : "u", "\n" if $s =~ /^(?:(cat)|(dog))$/;' ],
    [ '"aaa"',         'print "<$1>\n" if $s =~ /^(a*?)a$/;' ],
) {
    my ( $subj, $body ) = @$c;
    my $r = tap("my \$s = \$ENV{S} // $subj;\n$body\n");
    is $r->{verdict}, 'SAME', "captures: $body" or diag $r->{why} // explain $r;
}

# REFUSED BY NAME: what chalk uses nowhere (the census).
for my $c ( [ '/(a)\1/' => 'backreference' ], [ '/(?<n>a)/' => 'named capture' ], [ '/a++/' => 'possessive' ],
            [ '/(?>a)/' => 'atomic' ], [ '/\p{L}/' => 'escape' ] ) {
    my ( $re, $why ) = @$c;
    my $r = tap("my \$s = \$ENV{S} // 'aa';\nprint \$s =~ $re ? 'y' : 'n', qq{\\n};\n");
    is $r->{verdict}, 'REFUSED', "$re: refused";
    like $r->{why}, qr/$why/, '... by name';
}

done_testing;
