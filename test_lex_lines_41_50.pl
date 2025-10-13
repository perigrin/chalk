#!/usr/bin/env perl
# ABOUTME: Test lines 41-50 from lex.t to debug heredoc nesting
# ABOUTME: Check if nested heredocs cause parsing issues
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

print "Testing lex.t lines 41-50\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: Line 45 alone (eval with nested heredoc)
my $line45 = q{eval <<\EOE, print $@;
print <<'EOF';
ok 10
EOF

$foo = 'ok 11';
};

print "Test 1: Just line 45 (eval with nested heredoc)\n";
my $r1 = $parser->parse_string($line45);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Show preprocessed output
my $pp = Chalk::Preprocessor::Heredoc->new(input => $line45);
$pp->transform();
print "  Preprocessed:\n";
for my $line (split /\n/, $pp->output) {
    print "    $line\n";
}
print "\n";

# Test 2: Lines 41-50
my $lines_41_50 = q{print <<EOF;
$foo
EOF

eval <<\EOE, print $@;
print <<'EOF';
ok 10
EOF

$foo = 'ok 11';
};

print "Test 2: Lines 41-50\n";
my $r2 = $parser->parse_string($lines_41_50);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
if (!$r1) {
    print "❌ Nested heredoc in eval fails\n";
}
