# ABOUTME: `$s // []` (and `{}`) where $s is read by its tag: the reference it holds, or
# ABOUTME: the default -- B::SoN -> chalk -> lli == perl.
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

# The left side read by its tag was coerced to the reference type through
# the number and string readings, which have no reference: refused (pvm 217,
# and an older `($s->{c} // {})->%*`).
for my $c (
    [ q{my $r = { f => [1, 2] }; my $f = $r->{f} // []; print scalar(@$f), "\n";} ],
    [ q{my $r = { g => 1 }; my $f = $r->{f} // []; print scalar(@$f), "\n";} ],
    [ q{my $r = { c => { a => 1 } }; my $t = { ($r->{c} // {})->%*, n => 1 }; print join(",", sort keys %$t), "\n";} ],
    [ q{my $r = {}; my $t = { ($r->{c} // {})->%*, n => 1 }; print join(",", sort keys %$t), "\n";} ],
    # A DEFINED VALUE THAT IS NO REFERENCE is the value, where it is not used
    # as one.
    [ q{my $r = { f => "s" }; my $f = $r->{f} // []; print "$f\n";} ],
    [ q{my $r = { f => "s" }; my $f = $r->{f} // []; print ref($f) ? "ref\n" : "plain $f\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
