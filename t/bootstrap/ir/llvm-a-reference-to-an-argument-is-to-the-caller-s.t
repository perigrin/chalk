# ABOUTME: `\$_[N]` in an inlined sub is a reference to the caller's argument -- its
# ABOUTME: variable or element -- or refused by name: B::SoN -> chalk -> lli == perl.
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

# $_[N] is bound to a copy of the argument; a reference to it reached @_
# itself, which has no value here: refused (pvm 203).
for my $c (
    [ q{sub k { return \$_[0] } my $x = 1; my $r = k($x); $$r = 5; print "$x\n";} ],
    [ q{sub k { \$_[1] } my ($x, $y) = (1, 2); ${ k($x, $y) } = 7; print "$x $y\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A reference to an argument that is no variable kept in memory (an element,
# a constant, an expression): perl's answer, or refused by name -- resolved in
# the callee's frame, a write through it was lost.
for my $src (
    q{sub k { \$_[0] } my @a = (1, 2, 3); my $r = k($a[1]); $$r = 9; print "@a\n";},
    q{sub k { \$_[0] } my $r = k(3); print $$r, "\n";},
    q{sub k { \$_[0] } my $x = 2; my $r = k($x + 1); print $$r, " $x\n";},
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
