# ABOUTME: An array literal of Ints and Nums is read as Num, so its Ints are stored
# ABOUTME: as Nums: through B::SoN -> chalk -> lli == perl.
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

# THE LITERAL'S READING IS THE JOIN OF ITS ELEMENTS, and a read stamped Num
# takes the payload as a double. `(1.5, 2)` stored the 2 as an i64, read
# back as 9.88131291682493e-324 (pre-existing at e1a15d3a).
for my $case (
    [ q{my @a = (1.5, 2); print $a[1] + 0, "\n";}, "2\n", 'an Int element of a Num list' ],
    [ q{my @a = (3, 0.5); print $a[0] * 2, " ", $a[1] * 2, "\n";}, "6 1\n", 'either order' ],
    # Int with Str joins to Str: the 1 was read as a string pointer, and lli
    # crashed.
    [ q{my @a = (1, "x"); print "$a[0]$a[1]\n";}, "1x\n", 'an Int element of a Str list' ],
    [ q{my @a = (1, "x"); my $s; for my $x (@a) { $s = $x } print "$s\n";}, "x\n", 'walked by a loop' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
