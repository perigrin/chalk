# ABOUTME: Profiles Earley parse by counting operations and measuring time per phase.
# ABOUTME: Wraps the semiring to count multiply/add/is_zero/on_scan/on_complete calls.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Profile/g;
eval "$generated; 1" or die "Grammar eval: $@";
no strict 'refs';
my $gen_grammar = "Chalk::Grammar::Perl::Profile::grammar"->();
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

# === Count semiring operations via wrapper ===
my %counts;
my %times;

# Wrap FilterComposite to count operations
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

# Monkey-patch FilterComposite to count operations
{
    no warnings 'redefine';
    my $orig_multiply = \&Chalk::Bootstrap::Semiring::FilterComposite::multiply;
    my $orig_add = \&Chalk::Bootstrap::Semiring::FilterComposite::add;
    my $orig_is_zero = \&Chalk::Bootstrap::Semiring::FilterComposite::is_zero;
    my $orig_on_scan = \&Chalk::Bootstrap::Semiring::FilterComposite::on_scan;
    my $orig_on_complete = \&Chalk::Bootstrap::Semiring::FilterComposite::on_complete;
    my $orig_should_scan = \&Chalk::Bootstrap::Semiring::FilterComposite::should_scan;
    my $orig_one = \&Chalk::Bootstrap::Semiring::FilterComposite::one;

    *Chalk::Bootstrap::Semiring::FilterComposite::multiply = sub {
        $counts{multiply}++;
        my $t = time();
        my $r = $orig_multiply->(@_);
        $times{multiply} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::add = sub {
        $counts{add}++;
        my $t = time();
        my $r = $orig_add->(@_);
        $times{add} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::is_zero = sub {
        $counts{is_zero}++;
        my $t = time();
        my $r = $orig_is_zero->(@_);
        $times{is_zero} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::on_scan = sub {
        $counts{on_scan}++;
        my $t = time();
        my $r = $orig_on_scan->(@_);
        $times{on_scan} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::on_complete = sub {
        $counts{on_complete}++;
        my $t = time();
        my $r = $orig_on_complete->(@_);
        $times{on_complete} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::should_scan = sub {
        $counts{should_scan}++;
        my $t = time();
        my $r = $orig_should_scan->(@_);
        $times{should_scan} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Semiring::FilterComposite::one = sub {
        $counts{one}++;
        return $orig_one->(@_);
    };
}

# Also count Earley chart operations
{
    no warnings 'redefine';
    my $orig_chart_set = \&Chalk::Bootstrap::Earley::_chart_set;
    my $orig_chart_get = \&Chalk::Bootstrap::Earley::_chart_get;
    my $orig_chart_has = \&Chalk::Bootstrap::Earley::_chart_has;
    my $orig_predict = \&Chalk::Bootstrap::Earley::_predict;
    my $orig_scan = \&Chalk::Bootstrap::Earley::_scan;
    my $orig_complete = \&Chalk::Bootstrap::Earley::_complete;
    my $orig_advance = \&Chalk::Bootstrap::Earley::_advance_from_completed;

    my $orig_is_complete = \&Chalk::Bootstrap::Earley::_is_complete;
    my $orig_symbol_after = \&Chalk::Bootstrap::Earley::_symbol_after_dot;
    my $orig_make_item = \&Chalk::Bootstrap::Earley::_make_item;
    my $orig_advance_item = \&Chalk::Bootstrap::Earley::_advance_item;

    *Chalk::Bootstrap::Earley::_chart_set = sub {
        $counts{chart_set}++;
        my $t = time();
        my $r = $orig_chart_set->(@_);
        $times{chart_set} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_chart_get = sub {
        $counts{chart_get}++;
        my $t = time();
        my $r = $orig_chart_get->(@_);
        $times{chart_get} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_chart_has = sub {
        $counts{chart_has}++;
        my $t = time();
        my $r = $orig_chart_has->(@_);
        $times{chart_has} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_is_complete = sub {
        $counts{is_complete}++;
        my $t = time();
        my $r = $orig_is_complete->(@_);
        $times{is_complete} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_symbol_after_dot = sub {
        $counts{symbol_after_dot}++;
        my $t = time();
        my $r = $orig_symbol_after->(@_);
        $times{symbol_after_dot} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_make_item = sub {
        $counts{make_item}++;
        my $t = time();
        my $r = $orig_make_item->(@_);
        $times{make_item} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_advance_item = sub {
        $counts{advance_item}++;
        my $t = time();
        my $r = $orig_advance_item->(@_);
        $times{advance_item} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_predict = sub {
        $counts{predict}++;
        my $t = time();
        my $r = $orig_predict->(@_);
        $times{predict} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_scan = sub {
        $counts{scan}++;
        my $t = time();
        my $r = $orig_scan->(@_);
        $times{scan} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_complete = sub {
        $counts{complete}++;
        my $t = time();
        my $r = $orig_complete->(@_);
        $times{complete} += time() - $t;
        return $r;
    };
    *Chalk::Bootstrap::Earley::_advance_from_completed = sub {
        $counts{advance_completed}++;
        my $t = time();
        my $r = $orig_advance->(@_);
        $times{advance_completed} += time() - $t;
        return $r;
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

# === Report ===
print "=== Operation Counts ===\n";
for my $op (sort { ($counts{$b} // 0) <=> ($counts{$a} // 0) } keys %counts) {
    printf "  %-25s %10d", $op, $counts{$op};
    if (exists $times{$op}) {
        printf "  %8.2fs  (%4.1f%%)", $times{$op}, 100 * $times{$op} / $elapsed;
    }
    print "\n";
}

my $accounted = 0;
$accounted += $_ for values %times;
printf "\n  %-25s %10s  %8.2fs  (%4.1f%%)\n", "accounted", "", $accounted, 100 * $accounted / $elapsed;
printf "  %-25s %10s  %8.2fs  (%4.1f%%)\n", "unaccounted (overhead)", "", $elapsed - $accounted, 100 * ($elapsed - $accounted) / $elapsed;
printf "  %-25s %10s  %8.2fs\n", "TOTAL", "", $elapsed;
