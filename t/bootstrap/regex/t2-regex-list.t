# ABOUTME: a match in list context through T2: its groups (or 1), or with /g every
# ABOUTME: match's -- the pattern's own graph (the list or all flavor) returns them.
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
    'my ($x, $y) = $s =~ /(\w)(\d)/; print "$x|$y\n";',
    'my ($z) = $s =~ /(q)/; print defined $z ? "d" : "u", "\n";',
    'my @one = $s =~ /b/; print scalar(@one), "[@one]\n";',
    'my @none = $s =~ /q/; print scalar(@none), "\n";',
    'my @all = $s =~ /(\d+)/g; print "@all\n";',
    'my @w = $s =~ /\d/g; print "@w\n";',
    'my @p = $s =~ /(\w)(\d)/g; print "@p\n";',
    'my $n = () = $s =~ /\d/g; print "$n\n";',
    'my @e = $s =~ /x*/g; print scalar(@e), "\n";',
    'my @o = $s =~ /(a)|(b)/g; print join(",", map { defined $_ ? $_ : "u" } @o), "\n";',
    # PRINT AND A SUB'S ARGUMENTS ARE LIST CONTEXT (B::SoN stamps the match Boolean)
    'print $s =~ /(b)(\d+)/; print "\n";',
    'print "x" . ($s =~ /b/) . "\n";',
    'sub f { return scalar(@_) } print f($s =~ /(b)(\d)/), "\n";',
    'print join(",", $s =~ /(\d)/g), "\n";',
) {
    my $r = tap("my \$s = \$ENV{S} // 'a1b22c333';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
}

# RETURNED, a match's context is its caller's: refused, not guessed.
my $r = tap(qq{sub g { return \$_[0] =~ /(a)/ } my \$one = g('ab'); print "\$one\\n";\n});
is $r->{verdict}, 'REFUSED', 'a match returned: refused';
like $r->{why}, qr/returned/, '... saying why';

done_testing;
