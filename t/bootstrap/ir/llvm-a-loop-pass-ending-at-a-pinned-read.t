# ABOUTME: a read B::SoN pins where it stands, ending an if's arm that leaves for the loop's next
# ABOUTME: pass (`$c = $c->{next}; next`): perl's answer through the whole pipeline, or refused by name.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# through_llvm($src) -> its stdout through B::SoN, chalk's pipeline (T2, or
# the Context lowering where T2 refuses) and lli; dies with why it did not.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); my $ret = $g->returns->[0] or return (); ([ 'main::__PROGRAM__', $ret ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll}; close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# T2 refuses these (a reference to a constant, `\1`); the Context lowering
# ran the arm's pinned read where the pass did not ("found stop end" exited
# 255, pvm c138): refused by name now.
for my $src (
    q{use v5.42; sub find ($n) { my $cur = $n; while (defined $cur) { if (ref $cur eq 'ARRAY') { return $cur->[0] eq 'x' ? 'found' : 'other' } if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; } return 'stop'; } return 'end'; } print find({ next => { next => ['x'] } }), " ", find({ next => \1 }), " ", find({ next => undef }), "\n";},
    q{use v5.36; sub find ($cur) { while (defined $cur) { if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; } else { return 'stop' } } return 'end'; } print find({ next => { next => ['x'] } }), " ", find({ next => undef }), find({ next => \1 }), "\n";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1); print $fh $src; close $fh;
    my $want = qx($^X $pl);
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || ( $@ // '' ) =~ /GAP: a read pinned where it stands that ends a loop's pass/,
       "perl's answer or refused by name: " . substr($src, 0, 60)) or diag "got: " . ( $got // 'undef' ) . " $@";
}
# (one ending the loop body's own straight line is lowered: perl's answer)
{   my $src = q{use v5.36; sub f ($r) { my $s = ""; for my $k (sort keys %$r) { $s .= $r->{$k} } return $s } my $q = \1; print f({a => 1, b => 2}), ref($q), "\n";};
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1); print $fh $src; close $fh;
    my $got = eval { through_llvm($src) };
    is($got, scalar qx($^X $pl), "a loop body's last read through a reference: perl's answer") or diag $@;
}
done_testing;
