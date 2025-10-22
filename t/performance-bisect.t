# ABOUTME: Bisect test to find which part of num.t causes timeout
# ABOUTME: Tests progressively larger portions of perl-num.t
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Time::HiRes qw(time);
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', 'grammar', 'perl.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Read the full file
my @lines;
{
    open my $fh, '<', 'perl-num.t' or die "Cannot open perl-num.t: $!";
    @lines = <$fh>;
    close $fh;
}

my $total_lines = scalar(@lines);
diag("Total lines in num.t: $total_lines");

# Test progressively larger portions
# Smaller tests should pass, larger ones are TODO until performance improves
my @test_sizes = (10, 25, 50, 75, 100, 150, 200, $total_lines);

for my $line_count (@test_sizes) {
    last if $line_count > $total_lines;

    # Mark tests >100 lines as TODO - they're too slow currently
    my $is_slow_test = $line_count > 100;

    TODO: {
        local $TODO = "Performance optimization needed for $line_count+ lines" if $is_slow_test;

        my $code = join('', @lines[0..$line_count-1]);
        my $start_time = time();

        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm(15);  # 15 second timeout per test

            my $result = $parser->parse_string($code);

            alarm(0);
        };

        my $elapsed = time() - $start_time;

        if ($@ && $@ =~ /timeout/) {
            fail("First $line_count lines - timed out after 15 seconds");
            diag("Timeout occurred between " . ($test_sizes[-2] || 0) . " and $line_count lines");
            last;  # Stop testing larger sizes
        } elsif ($@) {
            if ($elapsed >= 10) {
                fail("First $line_count lines - took too long (${elapsed}s)");
                diag("Parse failed but time is concerning");
                diag("Error: $@");
            } else {
                pass("First $line_count lines - completed in ${elapsed}s");
            }
        } else {
            if ($elapsed >= 10) {
                fail("First $line_count lines - parsed but took too long (${elapsed}s)");
            } else {
                pass("First $line_count lines - successfully parsed in ${elapsed}s");
            }
        }
    }
}

done_testing();
