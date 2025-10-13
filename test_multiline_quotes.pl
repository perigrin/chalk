#!/usr/bin/env perl
# ABOUTME: Test multi-line quote operators (qq on separate line from delimiter)
# ABOUTME: Verify \s* in regex allows newlines between operator and delimiter
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

print "Testing multi-line quote operators\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: qq on same line (already worked)
my $same_line = q{print qq[ok 16\n];};
print "Test 1: qq and delimiter on same line\n";
my $r1 = $parser->parse_string($same_line);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 2: qq on separate line from delimiter (lex.t lines 65-67)
my $multi_line = q{print qq
[ok 16\n]
;};
print "Test 2: qq on separate line from delimiter\n";
my $r2 = $parser->parse_string($multi_line);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

# Test 3: q with newline
my $q_multi = q{print q
<ok 17>
;};
print "Test 3: q on separate line from delimiter\n";
my $r3 = $parser->parse_string($q_multi);
printf "  Result: %s\n\n", $r3 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
my $pass_count = grep { $_ } ($r1, $r2, $r3);
printf "Summary: %d/3 tests passed\n", $pass_count;

if ($pass_count == 3) {
    print "✅ Multi-line quote operators fully supported!\n";
}
