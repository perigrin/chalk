#!/usr/bin/env perl
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

# Read the actual file
my @lines = do { local (@ARGV) = 'perl-tests/base/lex.t'; <> };

# Test lines 1-21 (should work)
say "Lines 1-21:";
my $code1 = join('', @lines[0..20]);
my $result1 = $parser->parse_string($code1);
say $result1 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test lines 1-22 (incomplete string - should fail)
say "Lines 1-22 (incomplete string):";
my $code2 = join('', @lines[0..21]);
my $result2 = $parser->parse_string($code2);
say $result2 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test lines 1-26 (complete string - should work)
say "Lines 1-26 (complete string):";
my $code3 = join('', @lines[0..25]);
my $result3 = $parser->parse_string($code3);
say $result3 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test just the multi-line string by itself
say "Just the multi-line eval by itself:";
my $code4 = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};
my $result4 = $parser->parse_string($code4);
say $result4 ? "SUCCESS" : "FAILED";
