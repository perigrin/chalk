#!/usr/bin/env perl
# ABOUTME: CLI application for Chalk parser with grammar loading and input processing
# ABOUTME: Supports grammar modules via -g option (e.g., -g Perl loads Chalk::Grammar::Perl)
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw(:std :utf8);
use lib 'lib';
use lib 'tools';
use Scalar::Util qw(blessed);

use Chalk;

# Main execution when run as script
if ( !caller ) {
    # Parse command line options
    my $grammar_module = "Chalk";  # default grammar module
    my $semiring_type;            # explicit semiring type (Boolean, Position, SPPF)
    my $generate_ir = 1;          # default: generate IR (issue #112)
    my $syntax_check_mode = 0;    # -c flag for syntax checking
    my $compile_module_mode = 0;  # --compile-module flag
    my $module_to_compile;        # module name for compilation
    my $target_type;              # --target flag (e.g., 'xs')
    my $module_name;              # --module flag for XS module name
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
            $generate_ir = 0;         # -c disables IR generation
            $i++;
        } elsif ($ARGV[$i] eq '--compile-module' && $i < $#ARGV) {
            $compile_module_mode = 1;
            $module_to_compile = $ARGV[$i + 1];
            $grammar_module = "Chalk";  # Module compilation uses Chalk grammar
            $i += 2;
        } elsif ($ARGV[$i] eq '--preprocess') {
            $preprocess = ['Chalk::Preprocessor::Heredoc'];  # Enable heredoc preprocessing
            $i++;
        } elsif ($ARGV[$i] eq '--target' && $i < $#ARGV) {
            $target_type = $ARGV[$i + 1];
            $i += 2;
        } elsif ($ARGV[$i] =~ /^--target=(.+)$/) {
            $target_type = $1;
            $i++;
        } elsif ($ARGV[$i] eq '--module' && $i < $#ARGV) {
            $module_name = $ARGV[$i + 1];
            $i += 2;
        } elsif ($ARGV[$i] =~ /^--module=(.+)$/) {
            $module_name = $1;
            $i++;
        } else {
            push @remaining_args, $ARGV[$i];
            $i++;
        }
    }
    @ARGV = @remaining_args;

    # Build grammar from BNF file
    use Chalk::Grammar;
    use Chalk::Grammar::Chalk;  # Pre-loads all Chalk grammar rule classes for static compilation

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
        $chalk_grammar = Chalk::Grammar->build_from_bnf($content, $start_symbol, $grammar_module);
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

        my $resolver = Chalk::ImportResolver->new();

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
        # Create semiring and parser based on mode
        my $semiring;

        # Choose semiring based on explicit type or IR generation mode
        if ($semiring_type) {
            # Explicit semiring type requested via --semiring flag
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
        } elsif ($generate_ir) {
            # Default: Generate IR using ChalkIR semiring
            # This encapsulates Composite(SPPF, Semantic) configuration (issue #112)
            require Chalk::Semiring::ChalkIR;

            $semiring = Chalk::Semiring::ChalkIR->new(grammar => $chalk_grammar);
        } else {
            # No IR generation (e.g., -c flag) - use ChalkSyntax for syntax check
            # ChalkSyntax = SPPF + Precedence (validates syntax and precedence)
            require Chalk::Semiring::ChalkSyntax;
            $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $chalk_grammar);
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
            } elsif ($target_type && $target_type eq 'xs') {
                # XS target mode: parse → IR → optimize → XS generate → emit
                require Chalk::IR::Graph;
                require Chalk::Target::XS;

                # Get winning IR node from parse result
                my $winning_node;
                if ($result->can('context')) {
                    my $ctx = $result->context;
                    if ($ctx->can('focus')) {
                        $winning_node = $ctx->focus;
                    }
                }

                # Build graph from IR node
                if ($winning_node && blessed($winning_node) && $winning_node->can('id')) {
                    my $graph = Chalk::IR::Graph->new();
                    my %visited;
                    my @queue = ($winning_node);

                    while (@queue) {
                        my $node = shift @queue;
                        next unless blessed($node) && $node->can('id');
                        my $node_id = $node->id;
                        next if $visited{$node_id}++;

                        # Add node to graph
                        $graph->add_node($node);

                        # Traverse via object references (same as IR mode)
                        if ($node->can('value_node')) {
                            my $val = $node->value_node;
                            push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
                        }
                        if ($node->can('value') && $node->can('op') && $node->op ne 'Constant') {
                            my $val = $node->value;
                            push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
                        }
                        if ($node->can('control') && $node->control) {
                            my $ctrl = $node->control;
                            push @queue, $ctrl if blessed($ctrl) && $ctrl->can('id') && !$visited{$ctrl->id};
                        }
                        if ($node->can('left')) {
                            my $left = $node->left;
                            push @queue, $left if blessed($left) && $left->can('id') && !$visited{$left->id};
                        }
                        if ($node->can('right')) {
                            my $right = $node->right;
                            push @queue, $right if blessed($right) && $right->can('id') && !$visited{$right->id};
                        }
                        if ($node->can('operand')) {
                            my $op = $node->operand;
                            push @queue, $op if blessed($op) && $op->can('id') && !$visited{$op->id};
                        }
                        if ($node->can('condition')) {
                            my $cond = $node->condition;
                            push @queue, $cond if blessed($cond) && $cond->can('id') && !$visited{$cond->id};
                        }
                        if ($node->can('source') && $node->source) {
                            my $src = $node->source;
                            push @queue, $src if blessed($src) && $src->can('id') && !$visited{$src->id};
                        }
                        if ($node->can('branches') && $node->branches) {
                            for my $branch ($node->branches->@*) {
                                push @queue, $branch if blessed($branch) && $branch->can('id') && !$visited{$branch->id};
                            }
                        }
                        if ($node->can('control_users') && $node->control_users) {
                            for my $user ($node->control_users->@*) {
                                push @queue, $user if blessed($user) && $user->can('id') && !$visited{$user->id};
                            }
                        }
                        if ($node->can('returns') && $node->returns) {
                            for my $ret ($node->returns->@*) {
                                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
                            }
                        }
                    }

                    # Run optimization pipeline (IterPeeps -> DCE -> GCM)
                    require Chalk::IR::Optimizer;
                    $graph = Chalk::IR::Optimizer->optimize($graph);

                    # Generate XS code
                    my $xs_module_name = $module_name // 'ChalkModule';
                    my $xs_target = Chalk::Target::XS->new(
                        graph => $graph,
                        module_name => $xs_module_name,
                    );

                    my $xs_ast = $xs_target->generate();
                    my $xs_code = $xs_ast->emit();
                    print($xs_code);
                } else {
                    print("Parse successful but no IR node produced\n");
                }
            } else {
                # IR mode: build graph from winning IR node and execute
                if ($generate_ir) {
                    require Chalk::IR::Graph;

                    # Get winning IR node from parse result
                    my $winning_node;
                    if ($result->can('context')) {
                        my $ctx = $result->context;
                        if ($ctx->can('focus')) {
                            $winning_node = $ctx->focus;
                        }
                    }

                    # Check if winning_node is an IR node
                    if ($winning_node && blessed($winning_node) && $winning_node->can('id')) {
                        # Build graph by traversing from winning node via object references
                        my $graph = Chalk::IR::Graph->new();
                        my %visited;
                        my @queue = ($winning_node);

                        while (@queue) {
                            my $node = shift @queue;
                            next unless blessed($node) && $node->can('id');
                            my $node_id = $node->id;
                            next if $visited{$node_id}++;

                            # Add node to graph
                            $graph->add_node($node);

                            # Traverse via object references (polymorphic nodes)
                            # Return: value_node, control
                            if ($node->can('value_node')) {
                                my $val = $node->value_node;
                                push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
                            }
                            if ($node->can('value') && $node->can('op') && $node->op ne 'Constant') {
                                my $val = $node->value;
                                push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
                            }
                            if ($node->can('control') && $node->control) {
                                my $ctrl = $node->control;
                                push @queue, $ctrl if blessed($ctrl) && $ctrl->can('id') && !$visited{$ctrl->id};
                            }

                            # Binary ops: left, right
                            if ($node->can('left')) {
                                my $left = $node->left;
                                push @queue, $left if blessed($left) && $left->can('id') && !$visited{$left->id};
                            }
                            if ($node->can('right')) {
                                my $right = $node->right;
                                push @queue, $right if blessed($right) && $right->can('id') && !$visited{$right->id};
                            }

                            # Unary ops: operand
                            if ($node->can('operand')) {
                                my $op = $node->operand;
                                push @queue, $op if blessed($op) && $op->can('id') && !$visited{$op->id};
                            }

                            # Conditional: condition
                            if ($node->can('condition')) {
                                my $cond = $node->condition;
                                push @queue, $cond if blessed($cond) && $cond->can('id') && !$visited{$cond->id};
                            }

                            # Issue #195 fix: Proj source (If node that Proj projects from)
                            # This enables finding the If node from IfFalse/IfTrue Proj
                            if ($node->can('source') && $node->source) {
                                my $src = $node->source;
                                push @queue, $src if blessed($src) && $src->can('id') && !$visited{$src->id};
                            }

                            # Issue #195 fix: If node branches (IfTrue/IfFalse Proj nodes)
                            # This ensures both control paths are included in graph traversal
                            if ($node->can('branches') && $node->branches) {
                                for my $branch ($node->branches->@*) {
                                    push @queue, $branch if blessed($branch) && $branch->can('id') && !$visited{$branch->id};
                                }
                            }

                            # Issue #195 fix: Proj control_users (forward traversal)
                            # This enables finding early returns that USE a Proj as control
                            if ($node->can('control_users') && $node->control_users) {
                                for my $user ($node->control_users->@*) {
                                    push @queue, $user if blessed($user) && $user->can('id') && !$visited{$user->id};
                                }
                            }

                            # Issue #195 fix: Stop node returns (for if-else where both branches return)
                            # When ConditionalStatement creates Stop node, it stores Return nodes in 'returns' field
                            if ($node->can('returns') && $node->returns) {
                                for my $ret ($node->returns->@*) {
                                    push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
                                }
                            }
                        }

                        # Run optimization pipeline (IterPeeps -> DCE -> GCM)
                        require Chalk::IR::Optimizer;
                        $graph = Chalk::IR::Optimizer->optimize($graph);

                        # Execute with CEK interpreter
                        require Chalk::Interpreter::CEKDataflow;
                        my $func_registry = $semiring->can('function_registry') ? $semiring->function_registry : undef;
                        my $cek = Chalk::Interpreter::CEKDataflow->new(
                            graph => $graph,
                            function_registry => $func_registry,
                        );
                        my $execution_result = eval { $cek->execute() };
                        if ($@) {
                            print(STDERR "Execution error: $@\n");
                            exit 1;
                        }
                        print($execution_result // '');
                    } else {
                        print("Parse successful but no IR node produced\n");
                    }
                } else {
                    print("Parse successful: $result\n");
                }
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
