# ABOUTME: Mode-1 whole-file TAP oracle runner (I4): run a synthetic .t through B::SoN
# ABOUTME: and compare full multi-line lli stdout (epilogue-stripped) against real perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::Mode1Runner;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# Acceptance 1: a synthetic literal-only top-level-print .t runs PASS, with the
# FULL multi-line lli stdout (after the compiler epilogue is stripped) equal to
# real perl's TAP output. This is the first real Mode-1 acceptance: NO stock
# t/base file passes under I1+I2+I3 alone, so we author the minimal case.
# ---------------------------------------------------------------------------
{
    my ($fh, $tpath) = tempfile(SUFFIX => '.t', UNLINK => 1);
    print $fh qq{print "1..3\\n"; print "ok 1\\n"; print "ok 2\\n"; print "ok 3\\n";\n};
    close $fh;

    my $result = Chalk::CodeGen::Harness::Mode1Runner->run_file($tpath);

    is($result->{verdict}, 'PASS',
        'synthetic 3-print .t: Mode-1 verdict is PASS');

    my $expected = "1..3\nok 1\nok 2\nok 3\n";
    is($result->{lli_stdout}, $expected,
        'synthetic .t: epilogue-stripped lli stdout is the full multi-line TAP');
    is($result->{perl_stdout}, $expected,
        'synthetic .t: perl oracle stdout is the full multi-line TAP');
    is($result->{lli_stdout}, $result->{perl_stdout},
        'synthetic .t: lli stdout == perl stdout (behavior contract)');
}

# ---------------------------------------------------------------------------
# Acceptance 2: a miniperl-exceeding stock file (t/base/lex.t) does not lower.
# The runner MUST produce a LOUD COUNTED skip naming the first unsupported
# construct — never a silent pass.
# ---------------------------------------------------------------------------
{
    my $lex = "$ENV{HOME}/dev/perl5/t/base/lex.t";
  SKIP: {
        skip "perl5 blead t/base/lex.t not found at $lex", 3 unless -f $lex;

        my $result = Chalk::CodeGen::Harness::Mode1Runner->run_file($lex);

        is($result->{verdict}, 'SKIP',
            'lex.t: Mode-1 verdict is SKIP (does not lower), not a silent PASS');
        ok(defined $result->{skip_reason} && length $result->{skip_reason},
            'lex.t: skip is LOUD - carries a named reason');
        like($result->{skip_reason}, qr/GAP|unsupported|no .*method|lower|from_json|lli/i,
            "lex.t: skip_reason names the first unsupported construct: $result->{skip_reason}");
    }
}

# ---------------------------------------------------------------------------
# Acceptance 3: the skip histogram (reason -> count) is a first-class output.
# ---------------------------------------------------------------------------
{
    my $r1 = Chalk::CodeGen::Harness::Mode1Runner->run_file_into_histogram(\my %hist,
        do {
            my ($fh, $p) = tempfile(SUFFIX => '.t', UNLINK => 1);
            print $fh qq{print "1..1\\n"; print "ok 1\\n";\n};
            close $fh;
            $p;
        });

    my $lex = "$ENV{HOME}/dev/perl5/t/base/lex.t";
    if (-f $lex) {
        Chalk::CodeGen::Harness::Mode1Runner->run_file_into_histogram(\%hist, $lex);
    }

    ok(%hist ? 1 : 0, 'skip histogram is populated (a first-class reason->count map)');
    my $total = 0; $total += $_ for values %hist;
    ok($total >= 1, 'histogram counts at least one skipped file')
        if -f $lex;
    diag("skip histogram:");
    diag(sprintf("  %-60s %d", $_, $hist{$_})) for sort keys %hist;
}

done_testing();
