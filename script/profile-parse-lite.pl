# ABOUTME: Lightweight Earley profiler — counts only, no per-call timing.
# ABOUTME: Measures real parse time + operation counts without timing overhead.
use 5.42.0;
use utf8;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Desugar;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Earley;

my $target_file = $ARGV[0] // 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
die "File not found: $target_file\n" unless -f $target_file;

# === Build grammar ===
my $t0 = time();
my $raw_ir = TestPipeline::perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ProfLite/g;
eval "$generated; 1" or die "Grammar eval: $@";
no strict 'refs';
my $gen_grammar = "Chalk::Grammar::Perl::ProfLite::grammar"->();
use strict 'refs';

my @ordered;
my @rest;
for my $rule (@$gen_grammar) {
    if ($rule->name() eq 'Program') { unshift @ordered, $rule }
    else { push @rest, $rule }
}
push @ordered, @rest;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);
printf "Grammar: %d rules, %.1fs\n", scalar @$desugared, time() - $t0;

my $fc = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [
        Chalk::Bootstrap::Semiring::Boolean->new(),
        Chalk::Bootstrap::Semiring::Precedence->new(
            lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
        ),
        Chalk::Bootstrap::Semiring::TypeInference->new(
            keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
            builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
        ),
        Chalk::Bootstrap::Semiring::Structural->new(),
        Chalk::Bootstrap::Semiring::SemanticAction->new(
            actions => Chalk::Bootstrap::Perl::Actions->new(),
        ),
    ],
);

# Count-only wrappers (no time() calls — just increment counters)
my %counts;
my $max_origin_span = 0;
my @span_buckets;  # count of chart_set calls per log2(span) bucket
my %origins_per_pos;  # pos => count of distinct origins
{
    no warnings 'redefine';
    my $orig_chart_has = \&Chalk::Bootstrap::Earley::_chart_has;
    my $orig_chart_set = \&Chalk::Bootstrap::Earley::_chart_set;

    *Chalk::Bootstrap::Earley::_chart_has = sub {
        $counts{chart_has}++;
        return $orig_chart_has->(@_);
    };
    *Chalk::Bootstrap::Earley::_chart_set = sub {
        $counts{chart_set}++;
        # $_[1]=chart, $_[2]=pos, $_[3]=core_id, $_[4]=origin
        my $span = $_[2] - $_[4];
        $max_origin_span = $span if $span > $max_origin_span;
        # Bucket by span range
        my $bucket = $span == 0 ? 0 : int(log($span) / log(2));
        $span_buckets[$bucket]++;
        # Track distinct origins per position
        $origins_per_pos{$_[2]}++;
        return $orig_chart_set->(@_);
    };
}

my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $desugared,
    semiring => $fc,
);

open my $sfh, '<:utf8', $target_file or die "Cannot read: $!";
my $source = do { local $/; <$sfh> };
close $sfh;
my $lines = () = $source =~ /\n/g;
my $chars = length($source);
printf "Input: %s (%d lines, %d chars)\n\n", $target_file, $lines, $chars;

$t0 = time();
my $result = $parser->parse($source);
my $elapsed = time() - $t0;

printf "Result: %s in %.1fs (%.1f lines/sec)\n\n",
    (defined $result ? 'PARSE_OK' : 'PARSE_FAIL'), $elapsed, $lines / $elapsed;

printf "chart_has: %d calls\n", $counts{chart_has};
printf "chart_set: %d calls\n", $counts{chart_set};
printf "max origin span: %d chars (bitmap width needed)\n", $max_origin_span;
printf "bitmap bytes at max width: %d\n", int($max_origin_span / 8) + 1;

print "\nOrigin span distribution (chart_set calls):\n";
for my $b (0 .. $#span_buckets) {
    next unless defined $span_buckets[$b];
    my $lo = $b == 0 ? 0 : 2**$b;
    my $hi = 2**($b+1) - 1;
    printf "  span %5d-%5d: %8d calls (%4.1f%%)\n",
        $lo, $hi, $span_buckets[$b], 100 * $span_buckets[$b] / $counts{chart_set};
}

# Origins per position stats
my @origin_counts = sort { $a <=> $b } values %origins_per_pos;
my $n = scalar @origin_counts;
if ($n > 0) {
    printf "\nDistinct origins per position (chart_set calls):\n";
    printf "  min: %d  median: %d  p95: %d  max: %d  positions: %d\n",
        $origin_counts[0],
        $origin_counts[int($n * 0.5)],
        $origin_counts[int($n * 0.95)],
        $origin_counts[-1],
        $n;
}
