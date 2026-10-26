# ABOUTME: a block eval (or try/catch) inside a loop body is a branch there: a die in it --
# ABOUTME: from an inlined call too -- goes to that eval's end: B::SoN -> chalk -> lli == perl.
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

# The loop body was lowered statement by statement through lower_value, not
# process_control_node, so an eval in it was never opened as a branch: "a
# call in a block eval that is not lowered as a branch" (pvm 171-173).
for my $c (
    [ q{sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { my $c = eval { g($s) }; push @o, $c // "x" } print "@o\n";} ],
    [ q{sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { my $c; eval { $c = g($s); 1 } or $c = "x"; push @o, $c } print "@o\n";} ],
    [ q{use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { my $c; try { $c = g($s) } catch ($e) { $c = "x" } push @o, $c } print "@o\n";} ],
    [ q{my $n = 0; my $i = 0; while ($i < 4) { $i++; eval { die "d\n" if $i == 2; $n += $i }; } print "$n\n";} ],
    # A value the try body made, read after it on the no-error path: it has
    # no merge at the eval's join unless one is made (invalid IR, also
    # outside any loop).
    [ q{use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my $c; try { $c = g(2) } catch ($e) { $c = "x" } my $d; try { $d = g(3) } catch ($e) { $d = "x" } print "$c $d\n";} ],
) {
    my ($src) = @$c;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1); print $fh $src; close $fh;
    my $want = qx($^X $pl);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A VARIABLE THE BODY STORED, read after the eval: on a die perl keeps its
# old value, and the graph carries no merge of the two -- the read went
# straight to the body's value (invalid IR). perl's answer, or refused.
for my $src (q{sub g { die "no\n" if $_[0] == 2; "v$_[0]" } my $c = "init"; eval { $c = g(2) }; print "$c\n";},
             q{sub g { die "no\n" if $_[0] == 2; $_[0] } my $c = 0; eval { $c = g(1) + 1 }; print "$c\n";}) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: " . ( $got // 'undef' ) . " $@";
}

done_testing;
