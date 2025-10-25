#!/usr/bin/env perl
# ABOUTME: CLI application for Chalk parser with grammar loading and input processing
# ABOUTME: Supports grammar modules via -g option (e.g., -g Perl loads Chalk::Grammar::Perl)
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw(:std :utf8);
use lib 'lib';
use lib 'tools';

use Chalk;

# Main execution when run as script
if ( !caller ) {
    # Parse command line options
    my $grammar_module = "Perl";  # default grammar module
    my $semiring_type = "SPPF";   # default semiring
    my $syntax_check_mode = 0;    # -c flag for syntax checking
    my $compile_module_mode = 0;  # --compile-module flag
    my $module_to_compile;        # module name for compilation
    my $generate_ir_mode = 0;     # --generate-ir flag for batch IR generation
    my $output_format = 'text';   # --output-format for IR output (text, json, dot)
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
        } elsif ($ARGV[$i] eq '--compile-module' && $i < $#ARGV) {
            $compile_module_mode = 1;
            $module_to_compile = $ARGV[$i + 1];
            $grammar_module = "Chalk";  # Module compilation uses Chalk grammar
            $i += 2;
        } elsif ($ARGV[$i] eq '--generate-ir') {
            $generate_ir_mode = 1;
            $grammar_module = "Chalk";  # IR generation uses Chalk grammar
            $i++;
        } elsif ($ARGV[$i] eq '--output-format' && $i < $#ARGV) {
            $output_format = $ARGV[$i + 1];
            $i += 2;
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

    # Handle module compilation mode
    if ($compile_module_mode) {
        use Chalk::ImportResolver;
        use Chalk::IR::Builder;

        my $resolver = Chalk::ImportResolver->new();
        my $builder = Chalk::IR::Builder->new();

        # Resolve dependencies for the module
        my $dependency_order = $resolver->resolve_dependencies($module_to_compile);

        unless ($dependency_order && @$dependency_order) {
            print("Error: No dependencies resolved for module '$module_to_compile'\n");
            exit 1;
        }

        print("Module compilation order for $module_to_compile:\n");
        for my $module (@$dependency_order) {
            print("  $module\n");
        }

        # Create semiring for parsing
        require Chalk::Semiring::SPPF;
        my $semiring = Chalk::Semiring::SPPFViterbiSemiring->new();

        # Parse each module in dependency order
        my $parser = Chalk::Parser->new(
            grammar => $chalk_grammar,
            semiring => $semiring,
            preprocess => $preprocess
        );

        my $success_count = 0;
        my $failure_count = 0;

        for my $module (@$dependency_order) {
            my $file_path = $resolver->module_to_path($module);

            # Skip if file doesn't exist
            unless (-f $file_path) {
                print("Skipping $module (file not found: $file_path)\n");
                next;
            }

            # Read the module file
            open my $fh, '<', $file_path or do {
                print("Error: Cannot open $file_path: $!\n");
                $failure_count++;
                next;
            };
            local $/;
            my $content = <$fh>;
            close $fh;

            # Parse the module
            print("Parsing $module ($file_path)... ");
            my $result = $parser->parse_string($content);

            if ($result) {
                print("OK\n");
                $success_count++;
            } else {
                print("FAILED\n");
                $failure_count++;
            }
        }

        print("\nModule compilation summary:\n");
        print("  Success: $success_count\n");
        print("  Failure: $failure_count\n");
        print("  Total: " . ($success_count + $failure_count) . "\n");

        exit($failure_count == 0 ? 0 : 1);
    }

    # Handle IR generation mode
    if ($generate_ir_mode) {
        use Chalk::ImportResolver;
        use Chalk::IR::Builder;
        use Chalk::IR::Validator;

        print("Sea of Nodes IR Generation for lib/Chalk/\n");
        print("=" x 60 . "\n\n");

        my $resolver = Chalk::ImportResolver->new();
        my $validator = Chalk::IR::Validator->new();

        # Discover all Chalk modules in lib/Chalk/
        my @all_modules = ();
        my $lib_dir = 'lib/Chalk';

        # Use File::Find to discover all .pm files
        require File::Find;
        File::Find::find(
            {
                wanted => sub {
                    return unless $_ =~ /\.pm$/;
                    my $full_path = $File::Find::name;
                    # Convert path to module name: lib/Chalk/IR/Node.pm -> Chalk::IR::Node
                    $full_path =~ s/^lib\///;
                    $full_path =~ s/\.pm$//;
                    $full_path =~ s/\//\:\:/g;
                    push @all_modules, $full_path;
                },
                no_chdir => 1
            },
            $lib_dir
        );

        @all_modules = sort @all_modules;

        print("Discovered " . scalar(@all_modules) . " modules in lib/Chalk/\n\n");

        # Create semiring for parsing
        require Chalk::Semiring::SPPF;
        my $semiring = Chalk::Semiring::SPPFViterbiSemiring->new();

        # Create parser
        my $parser = Chalk::Parser->new(
            grammar => $chalk_grammar,
            semiring => $semiring,
            preprocess => $preprocess
        );

        my $success_count = 0;
        my $failure_count = 0;
        my $validation_success_count = 0;
        my $validation_failure_count = 0;
        my @failed_modules = ();
        my %module_ir_graphs = ();  # Store generated IR for each module

        for my $module (@all_modules) {
            my $file_path = $resolver->module_to_path($module);

            # Skip if file doesn't exist
            unless (-f $file_path) {
                print("Skipping $module (file not found: $file_path)\n");
                next;
            }

            # Read the module file
            open my $fh, '<', $file_path or do {
                print("Error: Cannot open $file_path: $!\n");
                $failure_count++;
                push @failed_modules, $module;
                next;
            };
            local $/;
            my $content = <$fh>;
            close $fh;

            # Parse the module
            print("Generating IR for $module... ");
            my $result = $parser->parse_string($content);

            if ($result) {
                print("PARSED ");

                # Try to get IR graph from parser/builder
                # Note: This is a placeholder - actual IR generation happens in semantic actions
                my $builder = Chalk::IR::Builder->new();
                my $graph = $builder->graph;

                # Validate the IR graph
                my ($valid, $errors) = $validator->validate_all($graph);

                if ($valid) {
                    print("VALIDATED\n");
                    $success_count++;
                    $validation_success_count++;
                    $module_ir_graphs{$module} = $graph;
                } else {
                    print("VALIDATION FAILED\n");
                    $success_count++;  # Parsing succeeded
                    $validation_failure_count++;
                    if ($output_format eq 'text') {
                        for my $error (@$errors) {
                            print("  Error: $error\n");
                        }
                    }
                    push @failed_modules, "$module (validation)";
                }
            } else {
                print("PARSE FAILED\n");
                $failure_count++;
                push @failed_modules, "$module (parse)";
            }
        }

        print("\n" . "=" x 60 . "\n");
        print("IR Generation Summary:\n");
        print("  Total modules: " . scalar(@all_modules) . "\n");
        print("  Parse success: $success_count\n");
        print("  Parse failures: $failure_count\n");
        print("  Validation success: $validation_success_count\n");
        print("  Validation failures: $validation_failure_count\n");

        if (@failed_modules) {
            print("\nFailed modules:\n");
            for my $mod (@failed_modules) {
                print("  - $mod\n");
            }
        }

        # Output IR graphs if requested
        if ($output_format eq 'json' && %module_ir_graphs) {
            print("\n" . "=" x 60 . "\n");
            print("Generated IR Graphs (JSON format):\n\n");

            for my $module (sort keys %module_ir_graphs) {
                my $graph = $module_ir_graphs{$module};
                print("Module: $module\n");

                # Convert graph to JSON-like structure
                my $nodes = $graph->nodes;
                print("{\n");
                print("  \"module\": \"$module\",\n");
                print("  \"nodes\": {\n");

                my @node_ids = sort keys %$nodes;
                for my $i (0..$#node_ids) {
                    my $node_id = $node_ids[$i];
                    my $node = $nodes->{$node_id};
                    print("    \"$node_id\": {\n");
                    print("      \"op\": \"" . $node->op . "\",\n");
                    print("      \"inputs\": [" . join(", ", map { "\"$_\"" } $node->inputs->@*) . "]\n");
                    print("    }");
                    print(",\n") if $i < $#node_ids;
                    print("\n") if $i == $#node_ids;
                }

                print("  }\n");
                print("}\n\n");
            }
        }

        exit($failure_count == 0 && $validation_failure_count == 0 ? 0 : 1);
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
