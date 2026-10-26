# ABOUTME: !, ?: and && on a sub's my ($k) = @_ variable test the caller's value by
# ABOUTME: perl's truth: B::SoN -> chalk -> lli == perl.
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

# A `my ($k) = @_` is stamped Unknown; inlined, it holds the caller's value,
# which _repr_of knows. Not, the ternary and && read the stamp and refused
# ("_ensure_i1 cannot convert repr=Unknown", pvm 071 152 199).
for my $c (
    [ q{sub t { my ($k) = @_; return "none" unless $k; "some" } print t("v"), t(0), "\n";} ],
    [ q{sub u { my ($k) = @_; return $k ? "y" : "n" } print u(1), u(""), "\n";} ],
    [ q{sub w { my ($a, $b) = @_; return ($a && $b) ? "both" : "not" } print w(1, 2), w(1, 0), "\n";} ],
    # Typed by THIS call's arguments: the second call's are not the first's.
    [ q{sub w { my ($a, $b) = @_; return $a && $b } print w(1, 2), "|", w("x", "y"), "|", w(1.5, 2.5), "|", w("", "z"), "\n";} ],
    # The element read through $x is guarded by $on: not made ahead of it.
    [ q{my %h = (a => { v => 5 }); sub f { my ($k, $on) = @_; my $r = "none"; if ($on && (my $x = $h{$k})) { $r = $x->{v} } return $r } print f("a", 0), f("a", 1), f("b", 1), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
