# ABOUTME: A foreach over @_ reads each element through an alias -- B::SoN's
# ABOUTME: ${ \ $_[i] }: the deref of a reference to an element is that element.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    q{sub d { my @r; foreach my $e (@_) { my $x = $e; push @r, "<$x>" } return join(",", @r) } print d(1, 2), "\n";},
    q{sub d { my $s = 0; foreach my $e (@_) { $s = $s + $e } return $s } print d(1, 2, 3), "\n";},
    q{sub d { my @r; foreach my $e (@_) { push @r, defined $e ? $e : "u" } return join(",", @r) } print d(1, undef, 3), "\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

# A WRITE THROUGH THE ALIAS stores into the caller's variable: not this.
my $r = tap(qq{sub d { foreach my \$e (\@_) { \$e = 9 } } my \$v = 1; d(\$v); print "\$v\\n";\n});
isnt $r->{verdict}, 'DIFFERS', 'a write through the alias: no wrong answer';

done_testing;
