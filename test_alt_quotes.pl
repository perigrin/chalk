#!/usr/bin/env perl
# ABOUTME: Test if alternative quote delimiters are already supported
# ABOUTME: Check qq(...), qq[...], q<...> forms from lex.t
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

print "Testing alternative quote delimiters\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test forms from lex.t lines 63-70
my @tests = (
    [ 'qq(text)', q{print qq(ok 15\n);} ],
    [ 'qq[text]', q{print qq[ok 16\n];} ],
    [ 'q<text>', q{print q<ok 17>;} ],
    [ 'q{text}', q{print q{ok 18};} ],
    [ 'qq{text}', q{print qq{ok 19};} ],
);

my $pass_count = 0;
for my $test (@tests) {
    my ($name, $code) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-10s : %s\n", $name, $result ? "PASS ✓" : "FAIL ✗";
    $pass_count++ if $result;
}

print "\n";
print "=" x 60 . "\n";
printf "Summary: %d/%d forms supported\n", $pass_count, scalar(@tests);

if ($pass_count == scalar(@tests)) {
    print "✅ All forms already supported!\n";
} else {
    print "❌ Need to add grammar rules for unsupported forms\n";
}
