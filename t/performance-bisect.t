# ABOUTME: Bisect test to find which part of num.t causes timeout
# ABOUTME: Tests progressively larger portions of perl-num.t
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Time::HiRes qw(time);
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

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
my @test_sizes = (10, 25, 50, 75, 100, 150, 200, $total_lines);

for my $line_count (@test_sizes) {
    last if $line_count > $total_lines;

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

done_testing();
