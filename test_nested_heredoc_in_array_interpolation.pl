#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::HeredocV2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

# Test the exact pattern from lex.t line 77-82
my $code = q{print <<E1 eq "foo\n\n" ? "ok 19\n" : "not ok 19\n";
@{[ <<E2 ]}
foo
E2
E1
};

say "=== Original Code ===";
say $code;

# Run preprocessor
my $preprocessor = Chalk::Preprocessor::HeredocV2->new(input => $code);
$preprocessor->transform();
my $transformed = $preprocessor->output;

say "\n=== After HeredocV2 Preprocessing ===";
say $transformed;

# Try to parse
say "\n=== Attempting to parse ===";
my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

if ($parser->parse_string($transformed)) {
    say "✓ Parse succeeded!";
} else {
    say "✗ Parse failed";
}
