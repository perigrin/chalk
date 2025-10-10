# ABOUTME: Test for issue #38 - parser timeout on num.t file
# ABOUTME: Verifies that the parser can handle numeric expressions within reasonable time
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Time::HiRes qw(time);
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Test that parsing completes within 10 seconds for numeric expressions
# This is a simplified version of the patterns in num.t that were causing timeouts

my @numeric_test_cases = (
    # Simple integers
    { code => '$a = 1;', desc => 'simple integer' },
    { code => '$a = -1;', desc => 'negative integer' },

    # Decimal numbers
    { code => '$a = 1.;', desc => 'trailing decimal' },
    { code => '$a = -1.;', desc => 'negative trailing decimal' },
    { code => '$a = 0.1;', desc => 'leading zero decimal' },
    { code => '$a = -0.1;', desc => 'negative leading zero decimal' },
    { code => '$a = .1;', desc => 'no leading zero decimal' },
    { code => '$a = -.1;', desc => 'negative no leading zero decimal' },
    { code => '$a = 10.01;', desc => 'multi-digit decimal' },

    # Scientific notation
    { code => '$a = 1e3;', desc => 'scientific notation lowercase' },
    { code => '$a = 10.01e3;', desc => 'decimal with scientific notation' },
    { code => '$a = 1e34;', desc => 'large scientific notation' },
    { code => '$a = 1e+34;', desc => 'scientific notation with positive exponent' },

    # Binary literals
    { code => '$a = 0b100;', desc => 'binary literal lowercase' },
    { code => '$a = 0B1101;', desc => 'binary literal uppercase' },

    # Octal literals
    { code => '$a = 0100;', desc => 'octal literal old style' },
    { code => '$a = 0o100;', desc => 'octal literal lowercase o' },
    { code => '$a = 0O1703;', desc => 'octal literal uppercase O' },

    # Hexadecimal literals
    { code => '$a = 0x100;', desc => 'hex literal lowercase' },
    { code => '$a = 0Xabcdef;', desc => 'hex literal uppercase X' },
    { code => '$a = 0XFEDCBA;', desc => 'hex literal uppercase X and digits' },

    # Complex decimal numbers
    { code => '$a = 0.00049999999999999999999999999999999999999;', desc => 'many decimal places' },
    { code => '$a = 0.00000000000000000000000000000000000000000000000000000000000000000001;', desc => 'very many decimal places' },
    { code => '$a = 80000.0000000000000000000000000;', desc => 'large number with trailing zeros' },
    { code => '$a = 1.0000000000000000000000000000000000000000000000000000000000000000000e1;', desc => 'scientific with many decimal zeros' },

    # Expressions with numeric operators
    { code => '$a = 1; $b = $a + 1;', desc => 'addition expression' },
    { code => '$a = -1; $b = $a + 1;', desc => 'negative addition expression' },
    { code => '$a = 0.1; $b = $a + 1;', desc => 'decimal addition' },
    { code => '$a = 1e3; $b = $a + 1;', desc => 'scientific notation addition' },

    # Print statements with numeric comparisons (common pattern in num.t)
    { code => 'print $a == 1 ? "yes" : "no";', desc => 'ternary with numeric comparison' },
    { code => 'print $a eq "1" ? "ok" : "not ok";', desc => 'ternary with string comparison' },
);

# Create a parser with Boolean semiring for faster validation
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

plan tests => scalar(@numeric_test_cases) + 1;

# Test each numeric pattern
for my $test (@numeric_test_cases) {
    my $start_time = time();

    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm(10);  # 10 second timeout per test case

        my $result = $parser->parse_string($test->{code});

        alarm(0);
    };

    my $elapsed = time() - $start_time;

    if ($@ && $@ =~ /timeout/) {
        fail("$test->{desc} - timed out after 10 seconds");
        diag("Code: $test->{code}");
    } elsif ($@) {
        # Parse error is OK for this test - we're only testing performance
        # The grammar may not support all features yet
        pass("$test->{desc} - completed in ${elapsed}s (parse may have failed, but didn't timeout)");
    } else {
        pass("$test->{desc} - completed in ${elapsed}s");
    }
}

# Final test: Try parsing the actual full num.t file
# Read the actual perl-num.t file
my $full_num_t;
{
    local $/;
    open my $fh, '<', 'perl-num.t' or die "Cannot open perl-num.t: $!";
    $full_num_t = <$fh>;
    close $fh;
}

my $start_time = time();

eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm(120);  # 2 minute timeout - num.t is long, give it more time

    my $result = $parser->parse_string($full_num_t);

    alarm(0);
};

my $elapsed = time() - $start_time;

if ($@ && $@ =~ /timeout/) {
    fail("full num.t - timed out after 2 minutes");
    diag("This is the core issue #38 - parser times out on num.t");
} elsif ($@) {
    # Parse error
    fail("full num.t - parse error after ${elapsed}s");
    diag("Error: $@");
} else {
    # Successfully parsed - num.t is 224 lines of complex numeric code
    # Parsing under 2 minutes is acceptable for this size/complexity
    if ($elapsed < 120) {
        pass("full num.t - successfully parsed in ${elapsed}s");
    } else {
        fail("full num.t - parsed but took too long (${elapsed}s)");
    }
}

done_testing();
