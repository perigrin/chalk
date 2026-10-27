# ABOUTME: ** (a number), x (a string repeated) and << >> (on numbers, unsigned):
# ABOUTME: B::SoN -> chalk -> lli == perl, or refused by name.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# None was lowered (pvm 038 041 039 264 048 266).
for my $c (
    [ q{my $a = $ARGV[0] // 12; my $b = $ARGV[1] // 5; print $a ** $b, " ", 2 ** 0.5, " ", 2 ** -1, " ", (-2) ** 3, "\n";} ],
    [ q{my $a = $ARGV[0] // 2; my $b = $ARGV[1] // 3; my $c = $ARGV[2] // 2; print $a ** $b ** $c, " ", ($a ** $b) ** $c, " ", 2 ** 64, "\n";} ],
    [ q{my $a = $ARGV[0] // "ab"; print $a x 3, "|", $a x 0, "|", $a x -1, "|", "-" x 2.7, "\n";} ],
    [ q{my $t = $ENV{X} // "ab"; $t x= 2; print "$t\n";} ],
    [ q{my $a = $ENV{X} // 1; my $b = $ENV{Y} // 16; print $a << 3, " ", $b >> 2, " ", 1 << 62, " ", 5 >> 70, "\n";} ],
    [ q{my $d = $ENV{Y} // 1; my $e = $ENV{Z} // 16; $d <<= 3; $e >>= 2; print "$d $e\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A LIST REPEATED, and a shift perl does unsigned past an i64: perl's answer,
# refused by name, or stopped -- never another value.
for my $src (
    q{my @l = (1, 2) x 2; print "@l\n";},
    q{my $n = -1; print $n << 1, "\n";},
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:|LLVM backend:|lli exited 255/, "refused or stopped: $src") }
}

done_testing;
