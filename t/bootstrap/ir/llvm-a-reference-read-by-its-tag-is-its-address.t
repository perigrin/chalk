# ABOUTME: a reference held in a tagged slot reads as perl reads it: KIND(0x...) (with
# ABOUTME: Class= when blessed) as a string, its address as a number -- not "" and 0.
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

# A reference's tag had no reading but undef: two references were one hash
# key (""), and equal as numbers (0).
for my $c (
    [ q{my @r = ([1], [2]); my %s; $s{$_}++ for @r; print scalar(keys %s), "\n";} ],
    [ q{my @r = ([1], [2]); print $r[0] == $r[1] ? "same" : "differ", $r[0] == $r[0] ? " self\n" : " not\n";} ],
    [ q{my @r = ([1, 2], 3); print join(",", @r) =~ /^ARRAY\(0x[0-9a-f]+\),3$/ ? "ok\n" : "no\n";} ],
    [ q{my @r; push @r, { a => 1 }; my $s = "$r[0]"; print $s =~ /^HASH\(0x[0-9a-f]+\)$/ ? "ok\n" : "no\n";} ],
    [ q{my @o = (bless({}, 'Foo'), 1); print "$o[0]" =~ /^Foo=HASH\(0x[0-9a-f]+\)$/ ? "ok\n" : "no\n";} ],
    [ q{my $x = 1; my @r = (\$x, 2); print "$r[0]" =~ /^SCALAR\(0x/ ? "ok" : "no", $r[0] + 0 > 0 ? " num\n" : " zero\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "perl's answer for $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
