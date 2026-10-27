# ABOUTME: s///g replaces every match, left to right, and yields how many it replaced
# ABOUTME: ("" for none): B::SoN -> chalk -> lli == perl.
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


# /g was refused, and s///'s count (RegexSubstCount) had no lowering (pvm 376).
for my $c (
    [ q{my $s = "aaa"; my $n = ($s =~ s/a/b/g); print "mid $s\n"; print "end $n\n";} ],
    [ q{my $s = "a-b-c"; (my $t = $s) =~ s/-/+/g; my $u = "xyz"; my $k = ($u =~ s/q/r/g); print "$t [$k] $u\n";} ],
    [ q{my $s = "aaaa"; my $n = ($s =~ s/aa/b/g); my $t = "abab"; my $m = ($t =~ s/b/c/); print "$s $n $t $m\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A PATTERN THAT CAN MATCH NOTHING, or one anchored at the start, is refused:
# perl's /g steps over an empty match by its own rules.
for my $src (q{my $s = "abc"; $s =~ s/x*/-/g; print "$s\n";}, q{my $s = "aab"; $s =~ s/^a/x/g; print "$s\n";},
        # ...AND CAPTURES IN THE REPLACEMENT, which B::SoN computes once, not per match
        q{my $s = "a1b2c3"; my $n = ($s =~ s/(\w)(\d)/$2$1/g); print "$s $n\n";},
        # ...AND /ge, WHOSE REPLACEMENT B::SoN SENDS AS A GRAPH OF ITS OWN (it
        # printed "abc" for perl's "a10b20c", pvm 111)
        q{my $s = "a1b2c"; $s =~ s/(\d)/$1*10/ge; print "$s\n";}) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
