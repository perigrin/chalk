#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::HeredocV2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

# Test 1: Single-line array ref (we know this works)
my $test1 = '@{[1]}';
say "Test 1 (single-line): $test1";
say "  Result: ", $parser->parse_string($test1) ? "✓" : "✗";

# Test 2: Multi-line array ref with simple content
my $test2 = '@{[
  1
]}';
say "\nTest 2 (multi-line simple):";
say "  ", join(" ", map { sprintf("%02d", ord($_)) =~ /\d+/ ? $_ : ord($_) } split //, $test2);
say "  Result: ", $parser->parse_string($test2) ? "✓" : "✗";

# Test 3: Multi-line array ref with string
my $test3 = '@{[
  "foo"
]}';
say "\nTest 3 (multi-line string):";
say "  Result: ", $parser->parse_string($test3) ? "✓" : "✗";

# Test 4: The actual lex.t pattern (without heredoc, using qq instead)
my $test4 = '@{[
  qq{foo}
]}';
say "\nTest 4 (multi-line qq):";
say "  Result: ", $parser->parse_string($test4) ? "✓" : "✗";

# Test 5: What our preprocessor produces
my $code5 = q{print <<E1 eq "foo\n\n" ? "ok 20\n" : "not ok 20\n";
@{[
  <<E2
foo
E2
]}
E1
};

say "\n=== Test 5: Full lex.t pattern ===";
say "Original:";
say $code5;

my $pp5 = Chalk::Preprocessor::HeredocV2->new(input => $code5);
$pp5->transform();
my $transformed5 = $pp5->output;

say "\nAfter preprocessing:";
say $transformed5;

say "\nParse result: ", $parser->parse_string($transformed5) ? "✓" : "✗";
