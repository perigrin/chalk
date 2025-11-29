#!/usr/bin/env perl
# ABOUTME: Generate AST corpus JSON files from chalk source files
# ABOUTME: Regenerates t/corpus/ast/*.json from t/corpus/ast/*.chalk

use 5.42.0;
use lib 'lib';
use JSON::PP ();
use File::Basename qw(basename);
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::AST;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Composite;

# Load grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Parse and generate AST
sub generate_ast($input) {
    my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $ast = Chalk::Semiring::AST->new();
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$chalksyntax, $ast]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($input);
    return undef unless $result;

    # Extract AST element from composite
    if ($result->can('elements')) {
        my @elements = $result->elements->@*;
        return $elements[1] if @elements > 1;
    }

    return $result;
}

# Find all chalk files and generate JSON
my @chalk_files = glob('t/corpus/ast/*.chalk');
my $json_encoder = JSON::PP->new->pretty->canonical;

my $success = 0;
my $failed = 0;

for my $chalk_file (sort @chalk_files) {
    my $test_name = basename($chalk_file, '.chalk');
    my $json_file = $chalk_file =~ s/\.chalk$/.json/r;

    # Read and parse
    open my $fh, '<:utf8', $chalk_file or die "Cannot read $chalk_file: $!";
    my $input = do { local $/; <$fh> };
    close $fh;

    my $ast;
    eval {
        $ast = generate_ast($input);
    };
    my $error = $@;

    if ($ast && !$error) {
        my $ast_hash = $ast->to_hash();
        my $json;
        eval {
            $json = $json_encoder->encode($ast_hash);
        };
        if ($@ || !$json) {
            print "FAIL: $test_name (JSON encoding error: $@)\n";
            $failed++;
            next;
        }

        open my $out, '>:utf8', $json_file or die "Cannot write $json_file: $!";
        print $out $json;
        close $out;

        print "OK: $test_name\n";
        $success++;
    } else {
        my $err_msg = $error // 'Parse returned undef';
        print "FAIL: $test_name ($err_msg)\n";
        $failed++;
    }
}

print "\nGenerated $success files, $failed failures\n";
