#!/usr/bin/env perl
# ABOUTME: Test grammar-based heredoc preprocessor (V2)
# ABOUTME: Verify it correctly handles nested heredocs from lex.t
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::HeredocV2;

print "Testing HeredocV2 (grammar-based preprocessor)\n";
print "=" x 60 . "\n\n";

# Test 1: Simple heredoc
my $simple = q{print <<'EOF';
Hello World
EOF
};

print "Test 1: Simple heredoc\n";
my $pp1 = Chalk::Preprocessor::HeredocV2->new(input => $simple);
$pp1->transform();
print "Input:\n$simple\n";
print "Output:\n" . $pp1->output . "\n\n";

# Test 2: Backslash heredoc
my $backslash = q{print <<\EOF;
test
EOF
};

print "Test 2: Backslash heredoc\n";
my $pp2 = Chalk::Preprocessor::HeredocV2->new(input => $backslash);
$pp2->transform();
print "Input:\n$backslash\n";
print "Output:\n" . $pp2->output . "\n\n";

# Test 3: THE KEY TEST - Nested heredoc from lex.t lines 45-54
my $nested = q{eval <<\EOE, print $@;
print <<'EOF';
ok 10
EOF

$foo = 'ok 11';
print <<EOF;
$foo
EOF
EOE
};

print "Test 3: Nested heredoc (lex.t lines 45-54)\n";
my $pp3 = Chalk::Preprocessor::HeredocV2->new(input => $nested);
$pp3->transform();
print "Input:\n$nested\n";
print "Output:\n" . $pp3->output . "\n\n";

print "=" x 60 . "\n";
print "Expected output for Test 3:\n";
print "eval q{print <<'EOF';\nok 10\nEOF\n\n\$foo = 'ok 11';\nprint <<EOF;\n\$foo\nEOF\n}, print \$\@;\n\n";

# Test 4: Parse with V2 preprocessor
print "Test 4: Parse lex.t lines 45-54 with HeredocV2\n";
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

local $SIG{__WARN__} = sub {};
my $result = $parser->parse_string($nested);
printf "  Result: %s\n\n", $result ? "PASS ✓" : "FAIL ✗";

if ($result) {
    print "🎉 SUCCESS! V2 handles nested heredocs correctly!\n";
} else {
    print "❌ V2 still doesn't handle nested heredocs\n";
}
