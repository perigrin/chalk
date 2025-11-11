#!/usr/bin/env perl
# ABOUTME: Tests for two-argument open with bareword filehandles - issue #45 phase 3
# ABOUTME: Legacy Perl open syntax that is common in older codebases

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
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


# Create parser
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test basic two-argument open with bareword filehandles
subtest 'basic two-arg open patterns' => sub {
    # Write mode
    ok($parser->parse_string('open FH, ">file.txt"'),
       'Should parse: open FH, ">file.txt"');

    ok($parser->parse_string('open TESTFILE, ">./foo"'),
       'Should parse: open TESTFILE, ">./foo"');

    # Read mode
    ok($parser->parse_string('open FH, "<file.txt"'),
       'Should parse: open FH, "<file.txt"');

    ok($parser->parse_string('open INPUT, "</tmp/data"'),
       'Should parse: open INPUT, "</tmp/data"');

    # Append mode
    ok($parser->parse_string('open LOG, ">>logfile"'),
       'Should parse: open LOG, ">>logfile"');
};

# Test two-arg open with variables in the filename
subtest 'two-arg open with variables' => sub {
    ok($parser->parse_string('open FH, ">$filename"'),
       'Should parse: open FH, ">$filename"');

    ok($parser->parse_string('open FH, "<$input_file"'),
       'Should parse: open FH, "<$input_file"');
};

# Test two-arg open with 'or die' pattern - the key failure from rs.t
subtest 'two-arg open with or die' => sub {
    ok($parser->parse_string('open FH, ">file" or die'),
       'Should parse: open FH, ">file" or die');

    ok($parser->parse_string('open FH, ">file" or die "error"'),
       'Should parse: open FH, ">file" or die "error"');

    ok($parser->parse_string('open TESTFILE, ">./foo" or die "error $! $^E opening"'),
       'Should parse: open TESTFILE, ">./foo" or die "error $! $^E opening"');
};

# Test close with bareword filehandles
subtest 'close with bareword filehandles' => sub {
    ok($parser->parse_string('close FH'),
       'Should parse: close FH');

    ok($parser->parse_string('close TESTFILE'),
       'Should parse: close TESTFILE');

    ok($parser->parse_string('close FH or die'),
       'Should parse: close FH or die');

    ok($parser->parse_string('close TESTFILE or die "error $! $^E closing"'),
       'Should parse: close TESTFILE or die "error $! $^E closing"');
};

# Test print to bareword filehandles
subtest 'print to bareword filehandles' => sub {
    ok($parser->parse_string('print FH "data"'),
       'Should parse: print FH "data"');

    ok($parser->parse_string('print TESTFILE $teststring'),
       'Should parse: print TESTFILE $teststring');

    ok($parser->parse_string('print TESTFILE "data\n"'),
       'Should parse: print TESTFILE "data\n"');
};

# Test the exact patterns from rs.t
subtest 'rs.t exact patterns' => sub {
    # Line 13 - the main failure point
    ok($parser->parse_string('open TESTFILE, ">./foo" or die "error $! $^E opening"'),
       'Should parse rs.t line 13: open TESTFILE, ">./foo" or die "error $! $^E opening"');

    # Line 15
    ok($parser->parse_string('print TESTFILE $teststring'),
       'Should parse rs.t line 15: print TESTFILE $teststring');

    # Line 16
    ok($parser->parse_string('close TESTFILE or die "error $! $^E closing"'),
       'Should parse rs.t line 16: close TESTFILE or die "error $! $^E closing"');

    # Line 19
    ok($parser->parse_string('open TESTFILE, "<./foo"'),
       'Should parse rs.t line 19: open TESTFILE, "<./foo"');

    # Line 22
    ok($parser->parse_string('close TESTFILE'),
       'Should parse rs.t line 22: close TESTFILE');

    # Line 27
    ok($parser->parse_string('open TESTFILE, ">./foo"'),
       'Should parse rs.t line 27: open TESTFILE, ">./foo"');

    # Line 28
    ok($parser->parse_string('print TESTFILE $teststring2'),
       'Should parse rs.t line 28: print TESTFILE $teststring2');

    # Line 31
    ok($parser->parse_string('open TESTFILE, "<./foo"'),
       'Should parse rs.t line 31: open TESTFILE, "<./foo"');
};

# Test two-arg open with inline variable declarations (our/my) - rs.t line 97
subtest 'open with inline variable declarations' => sub {
    # Basic our variable declaration
    ok($parser->parse_string('open our $T, "./foo"'),
       'Should parse: open our $T, "./foo"');

    # Basic my variable declaration
    ok($parser->parse_string('open my $T, "./foo"'),
       'Should parse: open my $T, "./foo"');

    # With read mode
    ok($parser->parse_string('open our $fh, "<./file"'),
       'Should parse: open our $fh, "<./file"');

    ok($parser->parse_string('open my $fh, "<./file"'),
       'Should parse: open my $fh, "<./file"');

    # With write mode
    ok($parser->parse_string('open our $fh, ">./file"'),
       'Should parse: open our $fh, ">./file"');

    ok($parser->parse_string('open my $fh, ">./file"'),
       'Should parse: open my $fh, ">./file"');

    # With append mode
    ok($parser->parse_string('open our $fh, ">>./file"'),
       'Should parse: open our $fh, ">>./file"');

    ok($parser->parse_string('open my $fh, ">>./file"'),
       'Should parse: open my $fh, ">>./file"');

    # With variables in path
    ok($parser->parse_string('open our $fh, ">$filename"'),
       'Should parse: open our $fh, ">$filename"');

    ok($parser->parse_string('open my $fh, "<$input"'),
       'Should parse: open my $fh, "<$input"');
};

# Test the exact failing pattern from rs.t line 97
subtest 'rs.t line 97 - open with our variable' => sub {
    ok($parser->parse_string('open our $T, "./foo"'),
       'Should parse rs.t line 97: open our $T, "./foo"');
};

done_testing();
