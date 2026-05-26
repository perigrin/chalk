# ABOUTME: Phase 7d Commit 1 instrument — runs corpus through Target::C and reports repair fires.
# ABOUTME: Always passes; the diag output drives Commit 2's repair-deletion decisions.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);
use Chalk::Bootstrap::Perl::Target::C;

# Corpus selection note (per Phase 7d execution finding on 2026-05-26):
# The instrumented repairs target Earley-specific patterns
# (pred_entry destructuring, wref_sv / sweep_sv list-unpacking,
# while-shift chart re-read, stale-merge detection). The simple
# semiring/grammar classes below do not exercise these paths —
# running them produces zero fires regardless of whether the
# repairs are live or dead.
#
# Earley.pm IS the canonical fire-site source, but probing it is
# impractical: parsing takes ~400s and the legacy pre-migration
# _collect_var_decls hits a "Deep recursion" warning and stalls
# during _generate_c_files. Until that pre-existing issue is
# resolved, this test cannot produce evidence for the live-vs-dead
# question for the Earley-specific repairs.
#
# This test still has value: (a) it documents the repair instrumentation
# is in place; (b) any future change that makes a smaller class trigger
# a repair will surface via diag; (c) if the Earley.pm pre-existing
# issue is resolved, adding it to the corpus is a one-line change.
#
# Set CHALK_REPAIR_COVERAGE_INCLUDE_EARLEY=1 to attempt the Earley
# probe (slow and may not complete).
my @CORPUS = (
    'lib/Chalk/Bootstrap/Semiring/Boolean.pm',
    'lib/Chalk/Bootstrap/Semiring/Structural.pm',
    'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm',
);
push @CORPUS, 'lib/Chalk/Bootstrap/Earley.pm'
    if $ENV{CHALK_REPAIR_COVERAGE_INCLUDE_EARLEY};

my %total_counters;

for my $src_path (@CORPUS) {
    SKIP: {
        skip "Source file not present: $src_path", 1 unless -e $src_path;

        open my $fh, '<:utf8', $src_path or skip "Cannot read $src_path: $!", 1;
        local $/;
        my $source = <$fh>;
        close $fh;

        my $mop = Chalk::MOP->new;
        Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
        my ($ir, $sa, $ctx) = parse_perl_source($source);

        skip "Parse failed for $src_path", 1 unless defined $ctx;

        my $mop_class;
        for my $cls ($mop->classes) {
            next if $cls->name eq 'main';
            $mop_class = $cls;
            last;
        }
        skip "No class in $src_path", 1 unless defined $mop_class;

        my $module_name = $mop_class->name;
        my $target = Chalk::Bootstrap::Perl::Target::C->new(
            module_name => $module_name,
        );
        $target->reset_repair_counters;

        my $result = eval {
            $target->_generate_c_files($ir, $sa, $ctx)
        };
        ok(defined $result, "Generated C for $src_path") or do {
            diag "Error generating $src_path: $@";
        };

        my $counters = $target->repair_counters;
        for my $name (sort keys $counters->%*) {
            $total_counters{$name} += $counters->{$name};
            diag(sprintf "  %-40s  %4d fires (in %s)",
                 $name, $counters->{$name}, $module_name);
        }
    }
}

diag('');
diag('=== Repair counter totals across corpus ===');
if (%total_counters) {
    for my $name (sort keys %total_counters) {
        diag(sprintf "  %-40s  %4d fires", $name, $total_counters{$name});
    }
} else {
    diag('  (no repairs fired on any corpus file)');
}
diag('');
diag('Zero fires on this corpus does NOT imply the repair is dead - see corpus note above.');
diag('Earley-specific repairs require CHALK_REPAIR_COVERAGE_INCLUDE_EARLEY=1 to probe.');

done_testing();
