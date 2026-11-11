# ABOUTME: a constant regex through T2 is its own graph -- a matcher sub of byte
# ABOUTME: compares, loops and phis -- called where the match is; answers as perl.
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

# Each pattern against several subjects (from %ENV, so nothing is folded):
# a y where it matches, an n where it does not.
my @cases = (
    [ 'abc',        qw(abc xabcx ab abd) ],
    [ 'a.c',        qw(abc a-c ac), "a\nc" ],
    [ '[b-d]x',     qw(bx dx ex ax cxx) ],
    [ '[^a]b',      qw(ab bb b) ],
    [ '\d\d',       qw(a12 1 x9y9 99) ],
    [ '\w+\s\w',    ( 'ab c', 'ab  c', '_ x', '!! x' ) ],
    [ '^ab',        qw(abc cab ab) ],
    [ 'ab$',        ( 'cab', "cab\n", 'abc', "ab\n\n" ) ],
    [ '\Aab\z',     ( 'ab', "ab\n", 'xab' ) ],
    [ '\Aab\Z',     ( 'ab', "ab\n", "ab\n\n" ) ],
    [ 'ab*c',       qw(ac abc abbbc abd) ],
    [ 'ab+c',       qw(ac abc abbbc xabbcx) ],
    [ 'ab?c',       qw(ac abc abbc) ],
    [ 'ab{2,3}c',   qw(abc abbc abbbc abbbbc) ],
    [ 'ab{2}c',     qw(abbc abbbc) ],
    [ 'ab{2,}c',    qw(abc abbc abbbbbc) ],
    [ 'a.*b',       qw(ab axxb axxbxb ba) ],
    [ 'a\d+5',      qw(a15 a5 a1235 a12) ],
);
for my $c (@cases) {
    my ( $re, @subj ) = @$c;
    my $src = join '', map { "my \$s$_ = \$ENV{S$_} // " . _q( $subj[$_] ) . ";\n" } 0 .. $#subj;
    $src .= join '', map { "print \$s$_ =~ /$re/ ? 'y' : 'n';\n" } 0 .. $#subj;
    $src .= "print qq{\\n};\n";
    my $r = tap($src);
    is $r->{verdict}, 'SAME', "/$re/ as perl through T2" or diag $r->{why} // explain $r;
}

# CAPTURES: $1.. and $& read the match that set them.
for my $c (
    [ '(\d+)-(\d+)', '"x12-345y"', 'print "$1|$2\n" if $s =~ /(\d+)-(\d+)/;' ],
    [ '(\d)x?',     '"7"',        'print $s =~ /(\d)x?/ ? "<$1>" : "no", "\n";' ],
    [ 'unless',      '"ab"',       'print "[$1]\n" unless $s !~ /(b)/;' ],
    [ 'a(b*)c',      '"xac"',      'print "[$1]\n" if $s =~ /a(b*)c/;' ],
    [ '(x)?dog',     '"dog"',      'print defined $1 ? "<$1>" : "u", "\n" if $s =~ /^(x)?dog$/;' ],
    [ '(a)|none',    '"zzz"',      'print $s =~ /(a)b/ ? "y" : "n", "\n";' ],
) {
    my ( $re, $subj, $body ) = @$c;
    my $r = tap("my \$s = \$ENV{S} // $subj;\n$body\n");
    is $r->{verdict}, 'SAME', "captures of /$re/ as perl through T2" or diag $r->{why} // explain $r;
}

# A CAPTURE WHERE ITS MATCH MAY HAVE FAILED: perl reads the last match that
# succeeded there. Refused by name, never read as this match's.
my $r = tap(qq{my \$s = \$ENV{S} // "ab";\n\$s =~ /(a)/;\n\$s =~ /(z)/;\nprint defined \$1 ? "d" : "u", "\\n";\n});
is $r->{verdict}, 'REFUSED', 'a capture after a match that may have failed: refused';
like $r->{why}, qr/may have failed/, '... saying why';
# $& AND ITS KIN: B::SoN reads them as package variables, not of a match.
for my $v ( '$&', '$`', q{$'}, '$+' ) {
    $r = tap(qq{my \$s = \$ENV{S} // "ab";\nprint "[$v]\\n" if \$s =~ /(a)/;\n});
    is $r->{verdict}, 'REFUSED', "$v: refused";
    like $r->{why}, qr/the match variable/, '... by name';
}

# UNDER /u (use v5.12 and later): ASCII subjects match as perl. \d \w \s are
# ASCII here; perl's Unicode rules for a character past ASCII are not, so a
# subject with one STOPS the program (exit 255, a message) -- never a wrong match.
$r = tap(qq{use v5.36;\nmy \$s = \$ENV{S} // "ab 12";\nprint \$s =~ /\\w+\\s\\d+\$/ ? "y" : "n", "\\n";\n});
is $r->{verdict}, 'SAME', '/u with an ASCII subject: as perl' or diag $r->{why} // explain $r;
# (the subject from the environment: a constant past ASCII is refused by T2 itself)
{
    local $ENV{S} = "caf\xe9";
    $r = tap(qq{use v5.36;\nmy \$s = \$ENV{S} // "cafe";\nprint \$s =~ /\\w\$/ ? "y" : "n", "\\n";\n});
    is $r->{llvm}{exit}, 255, '\\w against a character past ASCII: stopped' or diag explain $r;
    like $r->{llvm}{err}, qr/past ASCII/, '... saying why';
    $r = tap(qq{use v5.36;\nmy \$s = \$ENV{S} // "cafe";\nprint \$s =~ /f.\$/ ? "y" : "n", "\\n";\n});
    is $r->{verdict}, 'SAME', '. against it: as perl' or diag $r->{why} // explain $r;
}

sub _q ($s) { $s =~ s/([\\'])/\\$1/g; $s =~ s/\n/' . "\\n" . '/g; return "'$s'" }

done_testing;
