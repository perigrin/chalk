# ABOUTME: T2 slice 4 -- a my array is an %Array of %Slot in T2: literals, push/shift/pop,
# ABOUTME: element reads and stores, scalar(@a), "@a", foreach over it. Perl's answer.
our $LAST_LL;
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

sub through_llvm ($src, $env) {
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
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

for my $case (
    [ q{my @a = (1, 2, 3); print scalar(@a), " ", $a[1], " ", $a[-1], "\n";}, 'a literal, its count and elements' ],
    [ q{my @a = (1); push @a, 2, 3; print "$a[2] ", scalar(@a), "\n";}, 'push' ],
    [ q{my @a = (5, 6, 7); my $x = shift @a; my $y = pop @a; print "$x $y ", scalar(@a), "\n";}, 'shift and pop' ],
    [ q{my @a = (1, 2, 3); my $t = 0; for my $v (@a) { $t = $t + $v } print "$t\n";}, 'foreach over an array' ],
    [ q{my @a = (1, 2); $a[1] = 9; $a[3] = 4; print "$a[1] ", scalar(@a), defined $a[2] ? "d" : "u", "\n";}, 'element stores, the array growing' ],
    [ q{my @a = ("x", 1.5, 2); print "@a\n";}, 'interpolated' ],
    [ q{my @a = (1, 2); for my $v (@a) { $v = $v * 10 } my $s = $a[0]; $a[0] = 6; print "$s $a[0]\n";}, 'a read after a loop, then a store' ],
    [ q{for my $i (1 .. 2) { my @o; push @o, $i; print scalar(@o), "\n" }}, 'a bare my @o in a loop body, fresh each pass' ],
    [ q{for my $i (1 .. 2) { my @o = (7); push @o, $i; print scalar(@o), " $o[-1]\n" }}, 'a my @o = (...) in a loop body, fresh each pass' ],
    [ q{my $t = 0; for my $i (1 .. 3) { if ($i > 1) { my @o = ($i); push @o, 1; $t = $t + scalar(@o) } } print "$t\n";}, 'a my @o in an arm' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# A STORE BEFORE THE START dies as perl does: its message, where, its status.
{
    my $src = q{my @a = (1); $a[-3] = 5; print "no\n";};
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1); print $fh $src; close $fh;
    my $want = qx($^X $pl 2>&1); my $want_rc = $? >> 8;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my ($units) = Chalk::CodeGen::Pipeline->new->run_detail($json, sub ($g, $m) { ([ 'main::__PROGRAM__', $g->{'main::__PROGRAM__'}->returns->[0] ]) }, program_mode => 1);
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1); print $lf $units->[0]{ll}; close $lf;
    my $got = qx(timeout 20 $LLI $ll 2>&1);
    # shortcut: B::SoN gives a store no site yet, so the " at FILE line N." tail
    # is not checked -- give Assign a site in the producer, then compare whole.
    my ($head) = $want =~ /\A(.*?subscript -3)/;
    like($got, qr/\A\Q$head\E/, "a store before the start: perl's message");
    is($? >> 8, $want_rc, "a store before the start: perl's status");
    like($units->[0]{ll}, qr/^; chalk T2/m, 'a store before the start: lowered through T2');
}

done_testing;
