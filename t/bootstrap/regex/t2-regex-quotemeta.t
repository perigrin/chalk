# ABOUTME: \Q$x\E through T2: a literal known only at run time, matched as one (a
# ABOUTME: substr compare in the pattern's graph) -- no regex built at run time.
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
for my $body (
    'print $s =~ /a\Q$v\Ec$/ ? "y" : "n", "\n";',
    'print $s =~ /^\Q$v\E/ ? "y" : "n", "\n";',
    'print $s =~ /(\w)\Q$v\E(\w)/ ? "<$1$2>" : "n", "\n";',
    'my $e = ""; print $s =~ /a\Q$e\E\./ ? "y" : "n", "\n";',
    'my $n = () = $s =~ /\Q$v\E|c/g; print "$n\n";',
) {
    my $r = tap("my \$s = \$ENV{S} // 'a.b+c';\nmy \$v = \$ENV{V} // '.b+';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
}

# split BY AN INTERPOLATED PATTERN: B::SoN's own GAP today (T2 takes it when
# the producer gives it) -- refused, never a wrong answer.
my $r = tap("my \$s = \$ENV{S} // 'a.b+c';\nmy \$v = \$ENV{V} // '.b+';\nmy \@f = split /\\Q\$v\\E/, \$s; print join('|', \@f), qq{\\n};\n");
isnt $r->{verdict}, 'DIFFERS', 'split /\\Q$v\\E/: never a wrong answer' or diag explain $r;

done_testing;
