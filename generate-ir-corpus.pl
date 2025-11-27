#!/usr/bin/env perl
# ABOUTME: Generate IR corpus JSON files from chalk source files
# ABOUTME: Creates t/corpus/ir/*.json from t/corpus/ast/*.chalk

use 5.42.0;
use lib 'lib';
use JSON::PP ();
use File::Basename qw(basename);
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Load grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Parse and generate IR
sub generate_ir($input) {
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($input);
    return undef unless $result;

    my $builder = $ir_semiring->builder;
    my $graph = $builder->graph;

    # Prune to winning parse if possible
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            my $focus = $ctx->focus;
            if ($focus && $focus->can('id')) {
                eval { $graph->prune_to_reachable($focus->id) };
                return undef if $@;
            }
        }
    }

    return $graph;
}

# Copy chalk files and generate JSON
my @chalk_files = glob('t/corpus/ast/*.chalk');
my $json_encoder = JSON::PP->new->pretty->canonical->allow_blessed->convert_blessed;

my $success = 0;
my $failed = 0;

for my $chalk_file (sort @chalk_files) {
    my $test_name = basename($chalk_file, '.chalk');
    my $ir_chalk = "t/corpus/ir/$test_name.chalk";
    my $ir_json = "t/corpus/ir/$test_name.json";

    # Copy chalk file
    system("cp", $chalk_file, $ir_chalk);

    # Read and parse
    open my $fh, '<:utf8', $chalk_file or die "Cannot read $chalk_file: $!";
    my $input = do { local $/; <$fh> };
    close $fh;

    my $graph;
    eval {
        $graph = generate_ir($input);
    };
    my $error = $@;

    if ($graph && !$error) {
        my $ir_hash = $graph->to_json();
        my $json;
        eval {
            $json = $json_encoder->encode($ir_hash);
        };
        if ($@ || !$json) {
            print "FAIL: $test_name (JSON encoding error)\n";
            $failed++;
            next;
        }

        open my $out, '>:utf8', $ir_json or die "Cannot write $ir_json: $!";
        print $out $json;
        close $out;

        print "OK: $test_name\n";
        $success++;
    } else {
        print "FAIL: $test_name\n";
        $failed++;
    }
}

print "\nGenerated $success files, $failed failures\n";
