# ABOUTME: an element read at a loop's memory is this pass's value even when its use comes
# ABOUTME: after the pass's store (in an arm): B::SoN -> chalk -> lli == perl.
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

# Reads at the loop's memory were lowered where they were used; used in an
# arm after the pass stored the element, they read the store (older: perl's
# "x y" printed "z z"; pvm 233 once stores through a reference lowered).
for my $c (
    [ q{my %v = (a => "x", b => "y"); my @l; for my $k (sort keys %v) { my $s = $v{$k}; $v{$k} = "z"; if ($k) { push @l, $s } } print "@l\n";} ],
    [ q{my @a = (1, 2, 3); my @l; for my $i (0 .. 2) { my $s = $a[$i]; $a[$i] = 0; push @l, $s if $s > 1 } print "@l | @a\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A READ THROUGH A REFERENCE LEFT TO ITS USE, and a store through another
# (an argument the callee writes through): it may be the same aggregate.
# Perl's answer, or refused by name -- it read the store ("z=1" for "x=1").
{
    my $src = q{my %v = (a => {n => "x"}, b => {n => "y"}); sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] } my @l; for my $k (sort keys %v) { my $info = $v{$k}; my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : undef); push @l, "$s=$e" if defined $e } print "@l\n";};
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
