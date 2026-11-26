# ABOUTME: A call through a code ref B::SoN resolved to its anonymous sub inlines that
# ABOUTME: sub, found by its graph: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

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

# AN ANONYMOUS SUB HAS A GRAPH AND NO SUB RECORD. B::SoN resolves
# `$triple->(14)` to a direct Call naming the anon body's graph
# (`main::__PROGRAM__::__ANON__:1:2`), but records only named subs in the
# class channel -- and the pkg/name split cannot parse that name anyway. The
# Call names its callee graph exactly, so the graph is the metaobject's
# source (pvm subroutines.md, refused as "has no resolved callee").
for my $case (
    [ q{my $triple = sub { $_[0] * 3 }; print $triple->(14), "\n";}, "42\n", 'one argument' ],
    [ q{my $code = sub { return "c[@_]" }; print $code->(1, 2), "\n"; print $code->(), "\n";}, "c[1 2]\nc[]\n", '@_ as a list, twice' ],
    [ q{sub c { return "c[@_]" } sub n { return scalar(@_) } print c(), n(), c(4), "\n";}, "c[]0c[4]\n", 'a named sub called with nothing: @_ is empty' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# LOWERED SINCE B::SoN'S PLACES-EVERYWHERE (was refused: "a direct call of a
# closure made elsewhere"): `my ($a, $b) = @_` is each argument read at its
# version, which T2 takes from the closure's @_ -- perl's answer.
{
    my $src = q{my $add = sub { my ($a, $b) = @_; $a + $b }; print $add->(2, 3), "\n";};
    my $got = eval { through_llvm($src) };
    is($got, "5\n", "perl's answer: $src") or diag $@;
}

done_testing;
