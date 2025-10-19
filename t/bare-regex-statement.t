#!/usr/bin/env perl
# ABOUTME: Test bare regex patterns as statements
# ABOUTME: Issue: lex.t fails because /^/ after } isn't recognized
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::BNF::build_chalk_grammar($bnf_content, "Program");

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

print "1..8\n";

# Test 1: Simple bare regex with semicolon
my $result = $parser->parse_string('/^/;');
print $result ? "ok 1 - bare regex with semicolon\n" : "not ok 1 - bare regex with semicolon\n";

# Test 2: Bare regex in && expression
$result = $parser->parse_string('/^/ && 1;');
print $result ? "ok 2 - bare regex in && expression\n" : "not ok 2 - bare regex in && expression\n";

# Test 3: Bare regex after bare block
$result = $parser->parse_string('{ } /^/;');
print $result ? "ok 3 - bare regex after bare block\n" : "not ok 3 - bare regex after bare block\n";

# Test 4: Bare regex after if block
$result = $parser->parse_string('if (1) { } /^/;');
print $result ? "ok 4 - bare regex after if block\n" : "not ok 4 - bare regex after if block\n";

# Test 5: Bare regex after while block
$result = $parser->parse_string('while (0) { } /^/;');
print $result ? "ok 5 - bare regex after while block\n" : "not ok 5 - bare regex after while block\n";

# Test 6: The exact lex.t pattern (simplified)
$result = $parser->parse_string('while (0) { print "x"; }
/^/;');
print $result ? "ok 6 - while block then newline then bare regex\n" : "not ok 6 - while block then newline then bare regex\n";

# Test 7: Ensure bare regex in if condition still works (regression test)
$result = $parser->parse_string('if (/^/) { }');
print $result ? "ok 7 - bare regex in if condition (regression)\n" : "not ok 7 - bare regex in if condition (regression)\n";

# Test 8: Ensure explicit binding still works (regression test)
$result = $parser->parse_string('$_ =~ /^/;');
print $result ? "ok 8 - explicit binding (regression)\n" : "not ok 8 - explicit binding (regression)\n";
