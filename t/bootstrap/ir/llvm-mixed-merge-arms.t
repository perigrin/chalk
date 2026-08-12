# ABOUTME: A merge whose arms have different reprs coerces each arm to the join.
# ABOUTME: TernaryExpr, &&/|| and the Region Phi all merge operands, not booleans.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::ProgramRunner;

# A merge in perl yields ONE OF ITS OPERANDS, so its arms genuinely differ in
# type: `$c ? 42 : "hi"` is an Int on one path and a Str on the other, and
# `$a && $b` returns $a or $b, not a boolean. Measured in perl:
#
#     my $a=5; my $b="hi";  $a && $b   ->  "hi"
#     my $a=0; my $b="hi";  $a && $b   ->  0
#
# The backend's merge is one `select`/`phi` instruction, which needs ONE machine
# type. The node already carries the JOIN of its arms (the loader computes it),
# so the rule is the operator rule: the merge states its type and a
# non-conforming ARM is bridged by a coercion. Not a wider representation on the
# node — the arms are what disagree.
my @PROBES = (
    # Bilateral on WHICH ARM is taken: a fix that coerces only the true arm
    # passes the first and fails the second.
    ['ternary Int/Str, true arm'  => <<'SRC', "42\n"],
use 5.42.0;
my @a = (1);
my $c = scalar(@a);
my $v = $c ? 42 : "hi";
say($v);
SRC
    ['ternary Int/Str, false arm' => <<'SRC', "hi\n"],
use 5.42.0;
my @a = ();
my $c = scalar(@a);
my $v = $c ? 42 : "hi";
say($v);
SRC
    # Num vs Int on the numeric chain: the join is Num, so the Int arm widens.
    ['ternary Int/Num, true arm'  => <<'SRC', "1.5\n"],
use 5.42.0;
my @a = (1);
my $c = scalar(@a);
my $v = $c ? 1.5 : 42;
say($v);
SRC
    ['ternary Int/Num, false arm' => <<'SRC', "42\n"],
use 5.42.0;
my @a = ();
my $c = scalar(@a);
my $v = $c ? 1.5 : 42;
say($v);
SRC
    # && returns an OPERAND. Both polarities, because the short-circuit path
    # and the evaluated path produce different arms.
    ['&& mixed, rhs taken'  => <<'SRC', "hi\n"],
use 5.42.0;
my @a = (1);
my $c = scalar(@a);
my $v = $c && "hi";
say($v);
SRC
    ['&& mixed, lhs taken'  => <<'SRC', "0\n"],
use 5.42.0;
my @a = ();
my $c = scalar(@a);
my $v = $c && "hi";
say($v);
SRC
);

for my $p (@PROBES) {
    my ($name, $src, $want) = @$p;
    my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $src;
    close $fh;

    my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);

    subtest $name => sub {
        is($r->{perl_stdout}, $want, 'perl oracle says what this test claims');
        if (($r->{verdict} // '') eq 'SKIP') {
            fail('chalk could not lower it: ' . ($r->{skip_reason} // '?'));
            return;
        }
        is($r->{lli_stdout}, $want,           'chalk stdout matches');
        is($r->{lli_exit},   $r->{perl_exit}, 'chalk exit status matches');
    };
}

done_testing;
