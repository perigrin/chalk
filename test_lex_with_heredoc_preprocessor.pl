#!/usr/bin/env perl
# ABOUTME: Test lex.t parsing with heredoc preprocessor enabled
# ABOUTME: Verify preprocessor transforms heredocs to q{}/qq{} successfully
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

# Create parser WITH heredoc preprocessor
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

print "Testing lex.t with heredoc preprocessor\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: Simple heredoc
print "Test 1: Simple heredoc\n";
my $simple = q{print <<'EOF';
Hello World
EOF
};
my $r1 = $parser->parse_string($simple);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 2: Lines 36-40 from lex.t (the heredoc that broke parsing)
print "Test 2: Lines 36-40 from lex.t\n";
my $lex_heredoc = q{print <<'EOF';
ok 8
EOF

$foo = 'ok 9';
};
my $r2 = $parser->parse_string($lex_heredoc);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

# Test 3: Full lex.t file
print "Test 3: Full lex.t file with heredoc preprocessor\n";
open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my $code = do { local $/; <$fh> };
close $fh;

printf "  File size: %d bytes\n", length($code);
print "  Parsing with heredoc preprocessor...\n";

my $result = eval {
    local $SIG{ALRM} = sub { die "TIMEOUT\n" };
    alarm 60;
    my $r = $parser->parse_string($code);
    alarm 0;
    $r;
};

if ($@ && $@ =~ /TIMEOUT/) {
    print "  Result: TIMEOUT ⏱️\n\n";
} elsif ($@) {
    print "  Result: ERROR - $@\n\n";
} elsif ($result) {
    print "  Result: PASS ✅\n\n";
} else {
    print "  Result: FAIL ✗\n\n";
}

print "=" x 60 . "\n";
my $pass_count = grep { $_ } ($r1, $r2, $result);
printf "Summary: %d/3 tests passed\n", $pass_count;

if ($r1 && $r2 && $result) {
    print "\n🎉 SUCCESS! lex.t fully parses with heredoc preprocessor!\n";
} elsif ($r1 && $r2 && !$result) {
    print "\n⚠️  Heredocs work in isolation, but lex.t has other issues\n";
} elsif (!$r1) {
    print "\n❌ Heredoc preprocessor isn't working\n";
}
