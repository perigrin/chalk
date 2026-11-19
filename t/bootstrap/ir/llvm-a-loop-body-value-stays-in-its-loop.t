# ABOUTME: A value made inside a loop body is not served after the loop: the body need not
# ABOUTME: run, so it does not dominate the exit: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

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

# `for my $k (1 .. 2) { $out .= length($s) } $out .= $s`: $s's
# stringification was lowered inside the inner loop and served to the read
# after it, which it does not dominate -- lli rejected the module (pvm 130).
for my $case (
    [ q{my @p = ("ab", "c"); my $out = ""; for my $s (@p) { for my $k (1 .. 2) { $out .= length($s) } $out .= $s } print "$out\n";}, "22ab11c\n", 'a read after an inner loop' ],
    [ q{my $n = 3; my $t = 0; for my $i (1 .. $n) { $t += $n * 2 } print $n * 2, " $t\n";}, "6 18\n", 'a value made in the body, again after it' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A PASS'S ELEMENT IS READ WHERE THE PASS BEGINS. Lowered at its first use,
# `$x` was read after a call in the body that changed the array. And a
# RE-READ of it after such a call is refused: perl's `$x` aliases the
# element, which a shift in the call moves out from under the index (pvm
# 185 printed "bb;dd;" for perl's "aa;cc;" once a reference could be stored
# in a shared lexical). The re-read is now through the element's own cell.
{
    # (an alias is now its element's own cell, which the shift does not move)
    my $re = eval { through_llvm(q{sub g { shift @{$_[0]} } sub f { my $l = [qw(a b c d)]; my $s = ""; for my $x (@$l) { $s .= $x; g($l); $s .= $x . ";" } "$s|@$l" } print f(), "\n";}) };
    is($re, "aa;cc;|c d\n", 'a re-read after a call that changes the array: perl\'s answer') or diag $@;
    my $got = eval { through_llvm(q{sub h { 1 } my @a = (1, 2); my $s = ""; for my $x (@a) { $s .= $x; h(); $s .= "-" } print "$s\n";}) };
    is($got, "1-2-\n", 'an element read before a call: perl\'s answer') or diag $@;
    # a push moves no element: the loop sees what it adds (pvm 132)
    $got = eval { through_llvm(q{sub f { my @p = (1); my $add = sub { push @p, $_[0] + 1 if $_[0] < 4 }; my $out = ""; for my $x (@p) { $add->($x); $out .= $x } return $out } print f(), "\n";}) };
    is($got, "1234\n", 'a call that only pushes onto the array: perl\'s answer') or diag $@;
}

done_testing;
