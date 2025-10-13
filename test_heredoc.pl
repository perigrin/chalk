#!/usr/bin/env perl
# ABOUTME: Test if heredoc syntax is the issue in lex.t
# ABOUTME: Verify grammar doesn't support <<'EOF' syntax
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing heredoc support\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: Lines 31-35 (before heredoc)
my $before_heredoc = q{eval '$foo = 123+123.4+123e4+123.4E5+123.4e+5+.12;';

$foo = int($foo * 100 + .5);
if ($foo eq 2591024652) {print "ok 7\n";} else {print "not ok 7 :$foo:\n";}

};

print "Test 1: Lines before heredoc (31-35)\n";
my $r1 = $parser->parse_string($before_heredoc);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 2: Simple heredoc
my $simple_heredoc = q{print <<'EOF';
Hello World
EOF
};

print "Test 2: Simple heredoc\n";
my $r2 = $parser->parse_string($simple_heredoc);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

# Test 3: Heredoc with double quotes
my $double_heredoc = q{print <<"EOF";
Hello World
EOF
};

print "Test 3: Heredoc with double quotes\n";
my $r3 = $parser->parse_string($double_heredoc);
printf "  Result: %s\n\n", $r3 ? "PASS ✓" : "FAIL ✗";

# Test 4: Heredoc with bareword
my $bareword_heredoc = q{print <<EOF;
Hello World
EOF
};

print "Test 4: Heredoc with bareword\n";
my $r4 = $parser->parse_string($bareword_heredoc);
printf "  Result: %s\n\n", $r4 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
my $pass_count = grep { $_ } ($r1, $r2, $r3, $r4);
printf "Summary: %d/4 tests passed\n", $pass_count;

if ($r1 && !$r2 && !$r3 && !$r4) {
    print "\n❌ CONFIRMED: Heredocs are not supported\n";
    print "The grammar needs heredoc support to parse lex.t\n";
}
