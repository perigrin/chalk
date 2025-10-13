#!/usr/bin/env perl
# ABOUTME: Test backslash-quoted heredoc support in preprocessor
# ABOUTME: Check if <<\EOF syntax is handled correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

print "Testing backslash-quoted heredoc\n";
print "=" x 60 . "\n\n";

# Test 1: Check if preprocessor transforms <<\EOF
my $input = q{eval <<\EOE, print $@;
print "test";
EOE
};

print "Test 1: Preprocessor transformation\n";
print "Input:\n$input\n";

my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
$preprocessor->transform();
my $output = $preprocessor->output;

print "\nOutput:\n$output\n\n";

# Test 2: Parse backslash heredoc
print "Test 2: Parse backslash-quoted heredoc\n";
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

local $SIG{__WARN__} = sub {};
my $r1 = $parser->parse_string($input);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 3: Simple <<\EOF without eval
my $simple = q{print <<\EOF;
Hello
EOF
};

print "Test 3: Simple backslash heredoc\n";
my $r2 = $parser->parse_string($simple);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
if (!$r1 && !$r2) {
    print "❌ Backslash heredocs not supported by preprocessor\n";
} elsif ($r2 && !$r1) {
    print "⚠️  Simple backslash heredoc works, but comma expression fails\n";
}
