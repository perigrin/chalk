# ABOUTME: a qr// value through T2: an object of class Regexp holding perl's string
# ABOUTME: of its pattern and its matcher (the pattern's graph) as a code value.
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

for my $c (
    [ 'a qr// matched where it is made', 'my $q = qr/b\d/; print $s =~ $q ? "y" : "n", "\n";' ],
    [ 'its string',                       'my $q = qr/b\d/; print "$q\n";' ],
    [ 'its string with flags',            'my $q = qr/b/i; my $r = qr/x y/xs; print "$q $r\n";' ],
    [ 'its ref',                          'my $q = qr/b/; print ref($q), "\n";' ],
    [ 'passed to a sub and matched there', 'sub t { my ($x, $re) = @_; return $x =~ $re ? 1 : 0 } print t($s, qr/b\d/), t($s, qr/^z/), "\n";' ],
    [ 'captures through a passed qr',     'sub c { my ($x, $re) = @_; return $x =~ $re ? "<$1>" : "none" } print c($s, qr/(\d+)/), c($s, qr/(z)/), "\n";' ],
    [ 'not matched',                      'sub t { my ($x, $re) = @_; return $x !~ $re ? 1 : 0 } print t($s, qr/q/), "\n";' ],
) {
    my ( $name, $body ) = @$c;
    for my $pre ( '', "use v5.36;\n" ) {
        my $r = tap("${pre}my \$s = \$ENV{S} // 'ab12';\n$body\n");
        is $r->{verdict}, 'SAME', "$name" . ( $pre ? ' (use v5.36)' : '' ) or diag $r->{why} // explain $r;
    }
}

# INTERPOLATED, A VALUE KNOWN AT COMPILE TIME (B::SoN folds `my $p = "b"`
# into the match) is the pattern: its own graph, as a literal one.
for my $body ( 'my $p = "b"; my $m = $s =~ /$p/; print "$m\n";', 'my $p = "a.c"; print $s =~ /^$p$/ ? "y" : "n", "\n";',
               'my $p = "(\\d)"; print "<$1>\n" if $s =~ /$p/;' ) {
    my $r = tap("my \$s = \$ENV{S} // 'abc1';\n$body\n");
    is $r->{verdict}, 'SAME', "a constant interpolated: $body" or diag $r->{why} // explain $r;
}

# A PATTERN BUILT AT RUN TIME (a string where a qr// would be) has no graph:
# stopped where it is matched, never matched as something else.
my $r = tap(qq{sub t { my (\$x, \$re) = \@_; return \$x =~ \$re ? 1 : 0 }\nmy \$p = \$ENV{P} // "b";\nprint t("ab", \$p), "\\n";\n});
is $r->{llvm}{exit}, 255, 'a string as a pattern at run time: stopped' or diag explain $r;
like $r->{llvm}{err}, qr/built at run time/, '... saying why';

# KNOWN HERE TO BE A STRING (B::SoN stamps it Str): refused before it runs.
$r = tap(qq{my \$p = \$ENV{P} // "b";\nmy \$s = \$ENV{S} // "ab";\nprint \$s =~ /\$p/ ? 1 : 0, "\\n";\n});
is $r->{verdict}, 'REFUSED', 'a string pattern from input: refused' or diag explain $r;
like $r->{why}, qr/built at run time/, '... saying why';

done_testing;
