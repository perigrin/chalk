#!/usr/bin/env perl
# ABOUTME: CLI application for Chalk parser with grammar loading and input processing
# ABOUTME: Supports grammar modules via -g option (e.g., -g Perl loads Chalk::Grammar::Perl)
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw(:std :utf8);
use lib 'lib';

use Chalk;

# Main execution when run as script
if ( !caller ) {
    # Parse command line options
    my $grammar_module = "Perl";  # default grammar module
    my $semiring_type = "SPPF";   # default semiring
    my $syntax_check_mode = 0;    # -c flag for syntax checking
    my $preprocess = ['Chalk::Preprocessor::Heredoc'];  # default to Heredoc
    my @remaining_args;

    my $i = 0;
    while ($i <= $#ARGV) {
        if ($ARGV[$i] eq '-g' && $i < $#ARGV) {
            $grammar_module = $ARGV[$i + 1];
            $i += 2; # skip both -g and the grammar module name
        } elsif ($ARGV[$i] eq '--semiring' && $i < $#ARGV) {
            $semiring_type = $ARGV[$i + 1];
            $i += 2; # skip both --semiring and the semiring type
        } elsif ($ARGV[$i] eq '-c') {
            $syntax_check_mode = 1;
            $semiring_type = "Boolean";  # -c implies Boolean semiring
            $i++;
        } elsif ($ARGV[$i] eq '--preprocess') {
            $preprocess = ['Chalk::Preprocessor::Heredoc'];  # Enable heredoc preprocessing
            $i++;
        } else {
            push @remaining_args, $ARGV[$i];
            $i++;
        }
    }
    @ARGV = @remaining_args;

    # Build grammar from BNF file
    use Chalk::Grammar;

    our $chalk_grammar;

    # Map grammar names to BNF files
    my %grammar_files = (
        'Perl'  => 'perl.bnf',
        'Chalk' => 'chalk.bnf',
    );

    if (exists $grammar_files{$grammar_module}) {
        # Load from BNF file
        my $bnf_file = "grammar/$grammar_files{$grammar_module}";
        open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
        my $content = do { local $/; <$fh> };
        close $fh;

        # Both Perl and Chalk grammars use 'Program' as start symbol
        my $start_symbol = ($grammar_module eq 'Perl' || $grammar_module eq 'Chalk') ? 'Program' : undef;
        $chalk_grammar = Chalk::Grammar->build_from_bnf($content, $start_symbol);
    } else {
        # Try loading as a module
        my $full_module_name = $grammar_module;
        unless ($full_module_name =~ /::/) {
            $full_module_name = "Chalk::Grammar::$full_module_name";
        }

        my $grammar_file = $full_module_name;
        $grammar_file =~ s{::}{/}g;
        $grammar_file .= ".pm";

        eval {
            require $grammar_file;
            $full_module_name->import();
        };
        if ($@) {
            die("Error: Failed to load grammar module '$full_module_name': $@\n");
        }

        # Try to get $chalk_grammar export
        no strict 'refs';
        $chalk_grammar = ${"${full_module_name}::chalk_grammar"};
    }

    # Verify grammar loaded
    if ( !defined($chalk_grammar) ) {
        die("Error: Grammar not loaded for '$grammar_module'!\n");
    }

    # Read input from STDIN or command line file
    my $input;
    if (@ARGV) {
        # Read from file
        my $filename = $ARGV[0];
        open( my $fh, '<', $filename ) or die("Cannot open $filename: $!\n");
        local $/;    # slurp mode
        $input = <$fh>;
        close($fh);
    }
    else {
        # Read from STDIN
        local $/;    # slurp mode
        $input = <STDIN>;
    }

    chomp($input) if defined($input);

    if ( defined($input) && length($input) > 0 ) {
        # Create semiring based on type
        my $semiring;
        if ($semiring_type eq "Boolean") {
            require Chalk::Semiring::Boolean;
            $semiring = Chalk::Semiring::Boolean->new();
        } elsif ($semiring_type eq "Position") {
            require Chalk::Semiring::Position;
            $semiring = Chalk::Semiring::Position->new();
        } elsif ($semiring_type eq "SPPF") {
            require Chalk::Semiring::SPPF;
            $semiring = Chalk::Semiring::SPPFViterbiSemiring->new();
        } else {
            die("Error: Unknown semiring type '$semiring_type'. Use 'Boolean', 'Position', or 'SPPF'\n");
        }

        # Create parser with grammar and semiring
        my $parser = Chalk::Parser->new(
            grammar => $chalk_grammar,
            semiring => $semiring,
            preprocess => $preprocess
        );

        # Parse the input
        my $result = $parser->parse_string($input);

        # Print the result
        if ($result) {
            if ($syntax_check_mode) {
                print("$ARGV[0] syntax OK\n") if @ARGV;
                print("syntax OK\n") unless @ARGV;
            } else {
                print("Parse successful: $result\n");
            }
            exit 0;  # Success - like perl -c
        }
        else {
            if ($syntax_check_mode) {
                print("$ARGV[0] syntax error\n") if @ARGV;
                print("syntax error\n") unless @ARGV;
            } else {
                print("Parse failed\n");
            }
            exit 1;  # Failure - like perl -c
        }
    }
    else {
        print("No input provided\n");
        exit 1;  # Failure - no input
    }
}

1;
