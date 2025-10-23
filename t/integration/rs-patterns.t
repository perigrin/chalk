#!/usr/bin/env perl
# ABOUTME: Integration test for issue #45 - combining all three features
# ABOUTME: Tests that special variables, or/and operators, and two-arg open work together

use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


# Create parser
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test the exact failure case from rs.t line 13
subtest 'rs.t line 13 - the original failure' => sub {
    my $code = 'open TESTFILE, ">./foo" or die "error $! $^E opening"';
    ok($parser->parse_string($code),
       "Should parse rs.t line 13");

    # This line requires all three features:
    # 1. Two-argument open with bareword filehandle (TESTFILE)
    # 2. Low-precedence 'or' operator at statement level
    # 3. Special variables ($! and $^E) in the die message
};

# Test a larger snippet from rs.t
subtest 'rs.t snippet (lines 11-16)' => sub {
    my $snippet = <<'EOF';
1 while unlink 'foo';
rmdir 'foo';
open TESTFILE, ">./foo" or die "error $! $^E opening";
binmode TESTFILE;
print TESTFILE $teststring;
close TESTFILE or die "error $! $^E closing";
EOF

    ok($parser->parse_string($snippet),
       "Should parse rs.t lines 11-16 snippet");
};

# Test all three features combined in various ways
subtest 'combined feature tests' => sub {
    # Special vars + or operator
    ok($parser->parse_string('$x = $! or die'),
       'Should parse: $x = $! or die');

    # TODO: Print with string literal argument and or/and operators
    # This is a known limitation - PrintExpr with args isn't in NonBrace expression context
    TODO: {
        local $TODO = "print with string arg and or/and operators not yet supported";
        ok($parser->parse_string('print "Error: $!" or die'),
           'Should parse: print "Error: $!" or die');
    }

    # Two-arg open + or + special vars
    ok($parser->parse_string('open FH, "<$file" or die "Can\'t open: $!"'),
       'Should parse: open FH, "<$file" or die "Can\'t open: $!"');

    # close + or warn + special vars
    ok($parser->parse_string('close FH or warn "Warning: $!"'),
       'Should parse: close FH or warn "Warning: $!"');

    # Multiple special vars in one expression
    ok($parser->parse_string('die "Error: $! ($^E) at line $."'),
       'Should parse: die "Error: $! ($^E) at line $."');

    # Complex chaining with and
    ok($parser->parse_string('open FH, ">file" and print FH $data and close FH or die $!'),
       'Should parse: open FH, ">file" and print FH $data and close FH or die $!');
};

# Test that each feature works independently
subtest 'individual feature verification' => sub {
    # Special variables alone
    ok($parser->parse_string('$!'),
       'Special variables: $!');

    ok($parser->parse_string('$^E'),
       'Special variables: $^E');

    ok($parser->parse_string('$/'),
       'Special variables: $/');

    ok($parser->parse_string('$$'),
       'Special variables: $$');

    # or/and operators alone
    ok($parser->parse_string('1 or 0'),
       'Logical operators: 1 or 0');

    ok($parser->parse_string('1 and 1'),
       'Logical operators: 1 and 1');

    ok($parser->parse_string('func() or die'),
       'Logical operators: func() or die');

    # Two-arg open alone
    ok($parser->parse_string('open FH, ">file"'),
       'Two-arg open: open FH, ">file"');

    ok($parser->parse_string('close FH'),
       'Bareword filehandle: close FH');

    ok($parser->parse_string('print FH "data"'),
       'Print to bareword: print FH "data"');
};

# Test error handling patterns (very common in Perl)
subtest 'common error handling patterns' => sub {
    ok($parser->parse_string('open FH, "<file" or die "Cannot open file: $!"'),
       'Should parse: open FH, "<file" or die "Cannot open file: $!"');

    ok($parser->parse_string('close FH or warn "Close failed: $!"'),
       'Should parse: close FH or warn "Close failed: $!"');

    ok($parser->parse_string('unlink $file or warn "Could not delete: $!"'),
       'Should parse: unlink $file or warn "Could not delete: $!"');

    ok($parser->parse_string('mkdir $dir or die "Cannot create directory: $! ($^E)"'),
       'Should parse: mkdir $dir or die "Cannot create directory: $! ($^E)"');
};

done_testing();
