#!/usr/bin/env perl
# ABOUTME: Generate expected JSON AST output for corpus test .chalk files
# ABOUTME: Parses .chalk files and writes corresponding .json expected output
#
# USAGE:
#   ./generate-corpus-json.pl t/corpus/*.chalk
#   ./generate-corpus-json.pl path/to/specific/file.chalk
#
# PURPOSE:
#   This is a developer tool for maintaining the corpus test suite. When you
#   add new .chalk test files to t/corpus/, run this script to generate the
#   corresponding .json files containing the expected AST output.
#
#   The corpus tests (t/corpus.t) compare parsed AST output against these
#   .json files to verify the parser produces correct results.
#
# WORKFLOW:
#   1. Create a new .chalk file with the syntax you want to test
#   2. Run: ./generate-corpus-json.pl path/to/new/file.chalk
#   3. Review the generated .json to ensure it matches expected AST
#   4. Commit both .chalk and .json files together
#
# NOTE:
#   If parsing fails, the script warns and continues to the next file.
#   Always verify generated JSON is correct before committing.

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw/:std :utf8/;
use lib 'lib';
use JSON::PP ();
use Chalk::Grammar::BNF;
use Chalk::Semiring::AST;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Composite;

my @files = @ARGV or die "Usage: $0 <file.chalk> ...\n";

# Load grammar
open my $grammar_fh, "<:utf8", "grammar/chalk.bnf" or die $!;
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");

for my $file (@files) {
    die "File must end in .chalk: $file\n" unless $file =~ /\.chalk$/;

    # Read input
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    # Parse to AST
    my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $ast = Chalk::Semiring::AST->new();
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$chalksyntax, $ast]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($content);

    unless ($result) {
        warn "FAILED to parse: $file\n";
        next;
    }

    # Extract AST element from composite
    my $ast_element;
    if ($result->can('elements')) {
        my $elements = $result->elements;
        $ast_element = $elements->[1];  # Second element is AST
    } else {
        die "Result doesn't have elements() method\n";
    }

    # Convert to JSON
    my $ast_hash = $ast_element->to_hash();
    my $json = JSON::PP->new->utf8->pretty->canonical->encode($ast_hash);

    # Write output
    my $json_file = $file;
    $json_file =~ s/\.chalk$/.json/;

    open my $out, '>:utf8', $json_file or die "Cannot write $json_file: $!";
    print $out $json;
    close $out;

    print "Generated: $json_file\n";
}
