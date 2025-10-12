#!/usr/bin/env perl
# ABOUTME: Test quotes in comments edge case
# ABOUTME: Verify parser handles # '; pattern correctly (lex.t line 18)
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 4;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test 1: Simple comment with quote
my $simple = q{my $x = 1; # '};
ok($parser->parse_string($simple), 'comment ending with quote');

# Test 2: The exact line 18 pattern from lex.t
my $line18 = q{$x = '\\'; # ';};
ok($parser->parse_string($line18), 'line 18 from lex.t');

# Test 3: Line 18 + blank line + eval
my $with_eval = q{$x = '\\'; # ';

eval 'print "hi";';};
ok($parser->parse_string($with_eval), 'line 18 plus blank line plus eval');

# Test 4: Line 18 + if statement + eval (like lex.t)
my $full_context = q{$x = '\\'; # ';

if (length($x) == 1) {print "ok 4\n";} else {print "not ok 4\n";}

eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

ok($parser->parse_string($full_context), 'lines 18-26 from lex.t');
