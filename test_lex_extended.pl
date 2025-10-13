#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::HeredocV2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

# Read lex.t
my $file = 'perl-tests/base/lex.t';
open my $fh, '<', $file or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close $fh;

my @lines = split /\n/, $content;
my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

sub test_lines {
    my ($end_line) = @_;
    my $test_content = join("\n", @lines[0..$end_line-1]);
    my $pp = Chalk::Preprocessor::HeredocV2->new(input => $test_content);
    $pp->transform();
    my $transformed = $pp->output;
    return $parser->parse_string($transformed);
}

# Find the actual maximum by scanning forward
say "Scanning for maximum parseable line...";
say "(Note: some ranges may fail due to incomplete heredocs)";
say "";

my $last_success = 0;
for my $line (85..150) {
    my $result = test_lines($line);
    my $status = $result ? "✓" : "✗";

    if ($result) {
        $last_success = $line;
        printf "Line %-3d: %s (SUCCESS)\n", $line, $status;
    } elsif ($line % 5 == 0) {
        # Only print some failures to reduce noise
        printf "Line %-3d: %s\n", $line, $status;
    }

    # If we've had 10 consecutive successes, we're probably good
    if ($result && $line - $last_success > 10 && $last_success > 90) {
        say "...";
        say "Continuing to check...";
    }
}

say "\nLast successful line: $last_success";
say "Percentage: ", sprintf("%.1f", ($last_success / scalar(@lines)) * 100), "%";
