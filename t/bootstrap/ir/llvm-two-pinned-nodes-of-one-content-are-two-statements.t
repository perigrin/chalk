# ABOUTME: two nodes of the same content pinned at different points of an arm are two
# ABOUTME: statements, not one interned node: the JSON loader keeps them apart: perl == lli.
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

# A foreach over @_ reads `$x` as `exists $_[$i] ? $$alias : $_[$i]` at each
# use; two such reads have one content id and differ only in control_in.
# The loader interned them to ONE node and the second pin overwrote the
# first, so the arm's chain looped through its own If and the loop body --
# the if, the push -- was silently dropped: "" for
# perl's "a,c" (wrong since chalk 43ba40ea; refused before it).
for my $c (
    [ q{sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, $x } return join ",", @o } print f(qw(a b c)), "\n";} ],
    [ q{sub f { my @o; for my $x (@_) { if ($x eq "b") { push @o, "B"; next } push @o, $x } return join ",", @o } print f(qw(a b c)), "\n";} ],
    [ q{sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, $x } return scalar(@o) } print f(qw(a b c)), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
