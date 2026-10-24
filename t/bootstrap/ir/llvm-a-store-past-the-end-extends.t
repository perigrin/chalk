# ABOUTME: A store past an array's end extends it, the gap undef; a negative index counts
# ABOUTME: from the end -- B::SoN -> chalk -> lli == perl (backlog 4d7c2e19).
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

# A STORE PAST THE END EXTENDS THE ARRAY. The element store wrote slot N of
# whatever buffer the array had: `my @a; $a[1] = 1` wrote past an empty one,
# and a later malloc found the heap corrupted ("corrupted size vs.
# prev_size", pvm chalk-found-gaps.md). A negative index wrote slot -1.
for my $case (
    [ q{my @a; $a[1] = 1; print scalar(@a), defined $a[0] ? "d" : "u", "$a[1]\n";}, "2u1\n", 'past the end of an empty array' ],
    [ q{my @a = (1, 2, 3); $a[-1] = 9; $a[6] = 7; print scalar(@a), " $a[0] $a[1] $a[2] ", defined $a[4] ? "d" : "u", " $a[6]\n";}, "7 1 2 9 u 7\n", 'from the end, and past it' ],
    [ q{my @a; $a[2] = "z"; push @a, "p"; print scalar(@a), $a[3], $a[2], defined $a[1] ? "d" : "u", "\n"}, "4pzu\n", 'grown by a store, then pushed' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
