# ABOUTME: Phase-5 self-hosting coverage: measures how much real chalk lib/ code
# ABOUTME: lowers through B::SoN -> from_json -> LLVM, so progress is measured not guessed.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::Phase5LibCoverage;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# The measured sample. Running B::SoN over ALL ~160 lib/ files is minutes of
# subprocess time (each -MO=SoN compiles the whole producer + deps), so this
# gate measures a representative SAMPLE spanning the layers: IR nodes, the MOP,
# the grammar, the schedule passes, and the two plain-package files. To measure
# the whole tree, set PHASE5_ALL=1 (slow) and it globs every lib/**/*.pm.
# ---------------------------------------------------------------------------
my @files;
if ($ENV{PHASE5_ALL}) {
    require File::Find;
    no warnings 'once';   # $File::Find::name is set by find() at runtime
    File::Find::find(sub { push @files, $File::Find::name if /\.pm$/ }, 'lib');
    @files = sort @files;
}
else {
    @files = qw(
        lib/Chalk/IR/Node/Constant.pm
        lib/Chalk/IR/Node/Add.pm
        lib/Chalk/IR/Stamp.pm
        lib/Chalk/Grammar/Symbol.pm
        lib/Chalk/Grammar/Rule.pm
        lib/Chalk/MOP/Method.pm
        lib/Chalk/MOP/Class.pm
        lib/Chalk/IR/Schedule/Dominators.pm
        lib/Chalk/Bootstrap/IR/Optimizer.pm
    );
    @files = grep { -f $_ } @files;
}

plan skip_all => "no lib files to measure" unless @files;

my @results;
for my $file (@files) {
    my $r = Chalk::CodeGen::Harness::Phase5LibCoverage->measure_file(
        $file, { perl => $PERL, son => $SON });
    push @results, $r;
    # Each file is a soft measurement, not a pass/fail: report its stage + score.
    my $detail = $r->{stage} eq 'OK'
        ? "own=$r->{own} lowered=$r->{lowered}"
              . ($r->{top_gap} ? " top_gap=[$r->{top_gap}]" : '')
        : $r->{stage} . ($r->{err} ? " ($r->{err})" : '');
    ok(1, "$file: $detail");
}

# ---------------------------------------------------------------------------
# The trend number. This is the Phase-5 capstone metric: sum(lowered)/sum(own)
# of real lib/ code. It is the honest measure the corpus gate-green count does
# NOT give (that counts toy idioms). Today it is ~0 -- the gate asserts only
# that it is well-defined and non-negative, and prints it so a run shows the
# number moving as producer/backend GAPs close. Raise the floor as coverage
# lands (mirroring the corpus gate-green floor discipline).
# ---------------------------------------------------------------------------
my $sum = Chalk::CodeGen::Harness::Phase5LibCoverage->aggregate(\@results);

diag('');
diag('=== Phase-5 lib/ self-hosting coverage (B::SoN -> from_json -> LLVM) ===');
diag(sprintf('  files measured: %d', $sum->{files}));
for my $st (sort keys $sum->{by_stage}->%*) {
    diag(sprintf('    stage %-10s %d', $st, $sum->{by_stage}{$st}));
}
diag(sprintf('  OWN units: %d   LOWERED: %d   coverage: %.2f%%',
    $sum->{own}, $sum->{lowered}, $sum->{lower_pct}));
if (%{ $sum->{gap_hist} }) {
    diag('  top lowering-GAP buckets:');
    for my $g (sort { $sum->{gap_hist}{$b} <=> $sum->{gap_hist}{$a} } keys $sum->{gap_hist}->%*) {
        diag(sprintf('    %2d x %s', $sum->{gap_hist}{$g}, $g));
    }
}
diag('');
diag('  DIAGNOSIS (2026-07-13): coverage is ~0 not merely because methods hit the');
diag('  NO-REPR GAP, but because B::SoN invoked as `perl -MO=SoN <module.pm>` walks');
diag('  the loaded producer + deps, and a deeply-namespaced feature-class module');
diag('  (Chalk::IR::Node::Constant) contributes ZERO own units (stage NO_OWN) --');
diag('  package= empties the output rather than scoping it. Getting a real chalk');
diag('  class module to emit its OWN methods is the first Phase-5 blocker.');

cmp_ok($sum->{lowered}, '>=', 0,
    'Phase-5 lib/ coverage is well-defined (trend number; raise the floor as it lands)');

done_testing();
