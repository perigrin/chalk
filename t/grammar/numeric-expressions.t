# ABOUTME: Minimal test to identify exact pattern causing timeout in issue #38
# ABOUTME: Tests specific problematic patterns from num.t
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Time::HiRes qw(time);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test the exact pattern from num.t
my $minimal_case = <<'PERL';
$a = 1; "$a";
print $a eq "1" ? "ok 1\n" : "not ok 1 # $a\n";
PERL

my $start_time = time();

eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm(10);

    my $result = $parser->parse_string($minimal_case);

    alarm(0);
};

my $elapsed = time() - $start_time;

if ($@ && $@ =~ /timeout/) {
    fail("minimal case - timed out after 10 seconds");
    diag("Pattern: two-line case with string interpolation and print ternary");
} elsif ($@) {
    fail("minimal case - parse failed in ${elapsed}s");
    diag("Error: $@");
    diag("Note: Fast failure doesn't mean success - parse should work");
} else {
    if ($elapsed >= 5) {
        fail("minimal case - parsed but took too long (${elapsed}s)");
    } else {
        pass("minimal case - successfully parsed in ${elapsed}s");
    }
}

# Test with multiple repetitions
my $repeated_case = ($minimal_case x 10);  # 10 repetitions

$start_time = time();

eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm(30);

    my $result = $parser->parse_string($repeated_case);

    alarm(0);
};

$elapsed = time() - $start_time;

if ($@ && $@ =~ /timeout/) {
    fail("10x repetition - timed out after 30 seconds");
    diag("This indicates exponential growth in parse time");
} elsif ($@) {
    fail("10x repetition - parse failed in ${elapsed}s");
    diag("Error: $@");
    diag("Note: Fast failure doesn't mean success - parse should work");
} else {
    if ($elapsed >= 10) {
        fail("10x repetition - parsed but took too long (${elapsed}s)");
        diag("Expected ~10x slowdown from single case, got much worse");
    } else {
        pass("10x repetition - successfully parsed in ${elapsed}s");
    }
}

done_testing();
