# ABOUTME: grep keeps the elements its block finds true, by perl's truth, whatever
# ABOUTME: the block yields: through B::SoN -> chalk -> lli == perl.
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

# A GREP WHOSE BLOCK IS NOT A COMPARISON -- `grep { $_ }` -- yields the
# element itself as its predicate. The append took a third input for a gate
# only when it was stamped Boolean, so the element was appended twice and
# nothing was filtered: x x y y z z for x y z (pre-existing at e1a15d3a).
# The producer says which collector it is; a grep's last input is its test.
for my $case (
    [ q{my @a = (0, 1, 2); my @b = grep { $_ } @a; print "@b|", scalar(@b), "\n";}, "1 2|2\n", 'Int elements' ],
    [ q{my @a = qw(x y z); my $n = grep { $_ } @a; print "$n\n";}, "3\n", 'counted' ],
    [ q{my @a = ("a", "", "0", "b"); my @b = grep { $_ } @a; print "@b\n";}, "a b\n", "Str elements, perl's false ones dropped" ],
    [ q{my @a = (1, 2, 3); my @b = grep { $_ > 1 } @a; print "@b\n";}, "2 3\n", 'a comparison still' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
