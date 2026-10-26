# ABOUTME: `my ($a, $b) = ($r->[0], $r->[1])` reads elements into scalars; it stores no
# ABOUTME: element, so a later element read is not refused: B::SoN -> chalk -> lli == perl.
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

# _is_element_store took any Subscript INPUT for a store -- the values a list
# assignment reads -- so the graph read as holding an off-chain element store
# and every element read refused ("needs a memory-Phi", pvm 166).
for my $c (
    [ q{sub f { my $r = [[1, 2]]; my ($lv, $val) = ($r->[0][0], $r->[0][1]); $r->[0][0] = 9; return "$lv $val $r->[0][0]" } print f(), "\n";} ],
    [ q{my @a = (3, 4); my ($x, $y) = ($a[1], $a[0]); $a[0] = 5; print "$x $y $a[0]\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
