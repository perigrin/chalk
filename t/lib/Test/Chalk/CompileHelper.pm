# ABOUTME: Shared test library for Chalk to XS compilation workflow
# ABOUTME: Provides reusable functions for parsing, IR graph building, and XS compilation
use 5.42.0;
use experimental 'class';

class Test::Chalk::CompileHelper {
    use Exporter 'import';
    use Chalk::Grammar;
    use Chalk::Parser;
    use Chalk::Semiring::ChalkIR;
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::IR::Graph;
    use Chalk::Target::XS;
    use ExtUtils::CBuilder;
    use ExtUtils::ParseXS;
    use File::Spec;
    use File::Basename;
    use File::Path qw(make_path);
    use File::Temp qw(tempdir);
    use Config;
    use Scalar::Util qw(blessed);

    our @EXPORT_OK = qw(
        compile_module
        parse_chalk_file
        build_ir_graph
        compile_xs
    );

    # Cache for the Chalk grammar to avoid expensive reloading
    my $cached_grammar;

    # Parse Chalk source file to IR
    # Takes: file path to Chalk source
    # Returns: IR root node from successful parse, or undef on failure
    sub parse_chalk_file {
        my ($file_path) = @_;

        # Read source file
        open my $fh, '<:utf8', $file_path or do {
            warn "Cannot read $file_path: $!";
            return undef;
        };
        my $source = do { local $/; <$fh> };
        close $fh;

        return undef unless defined $source && length($source) > 0;

        # Reset type registry for clean parse
        Chalk::Grammar::Chalk::TypeRegistry->instance->reset();

        # Load grammar (use cache if available)
        unless ($cached_grammar) {
            my $bnf_file = "grammar/chalk.bnf";
            open my $bnf_fh, '<:utf8', $bnf_file or do {
                warn "Cannot open $bnf_file: $!";
                return undef;
            };
            my $bnf_content = do { local $/; <$bnf_fh> };
            close $bnf_fh;

            $cached_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
        }

        # Create parser with ChalkIR semiring
        my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $cached_grammar);
        my $parser = Chalk::Parser->new(
            grammar => $cached_grammar,
            semiring => $semiring,
        );

        # Parse the source
        my $result = $parser->parse_string($source);
        return undef unless defined $result;

        # Extract IR root from parse result
        my $ir_root = $result->context->focus;
        return $ir_root;
    }

    # Build IR graph from root node using breadth-first traversal
    # Takes: IR root node
    # Returns: Chalk::IR::Graph populated with all reachable nodes
    sub build_ir_graph {
        my ($ir_root) = @_;

        return undef unless blessed($ir_root) && $ir_root->can('id');

        my $graph = Chalk::IR::Graph->new();
        my %visited;
        my @queue = ($ir_root);

        while (@queue) {
            my $node = shift @queue;
            next unless blessed($node) && $node->can('id');
            next if $visited{$node->id}++;

            $graph->add_node($node);

            # Traverse single-node references
            for my $method (qw(value_node value control left right operand condition source call callee)) {
                next unless $node->can($method);
                my $ref = $node->$method;
                push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            }

            # Traverse array references
            for my $method (qw(branches control_users args return_nodes function_defs class_defs fields methods)) {
                next unless $node->can($method) && $node->$method;
                for my $ref ($node->$method->@*) {
                    push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                }
            }
        }

        return $graph;
    }

    # Compile XS file to shared library (.so) using ExtUtils::CBuilder
    # Takes: path to .xs file, module name (e.g., 'Chalk::Grammar::Token')
    # Returns: path to compiled .so file, or undef on failure
    sub compile_xs {
        my ($xs_file, $module_name) = @_;

        my $cb = ExtUtils::CBuilder->new(quiet => 1);
        return undef unless $cb->have_compiler;

        my $dir = File::Basename::dirname($xs_file);
        my $c_file = File::Spec->catfile($dir, "${module_name}.c");

        # Step 1: Run xsubpp to convert .xs to .c
        eval {
            ExtUtils::ParseXS::process_file(
                filename   => $xs_file,
                output     => $c_file,
                'C++'      => 0,
                hiertype   => 0,
                prototypes => 0,
                linenumbers => 1,
            );
        };
        if ($@ || !-f $c_file) {
            warn "xsubpp failed: $@" if $@;
            return undef;
        }

        # Step 2: Compile .c to object file
        my $obj_file;
        eval {
            $obj_file = $cb->compile(
                source => $c_file,
                extra_compiler_flags => $Config::Config{ccflags},
            );
        };
        if ($@ || !defined $obj_file || !-f $obj_file) {
            warn "Compilation failed: $@" if $@;
            return undef;
        }

        # Step 3: Link to shared library
        my $so_file;
        eval {
            $so_file = $cb->link(
                objects     => [$obj_file],
                module_name => $module_name,
            );
        };
        if ($@ || !defined $so_file || !-f $so_file) {
            warn "Linking failed: $@" if $@;
            return undef;
        }

        return $so_file;
    }

    # Main entry point - compiles a Chalk module to XS
    # Takes: source file path, module name
    # Returns: hashref with {xs, pmc, so_file, tempdir} or undef on failure
    sub compile_module {
        my ($source_file, $module_name) = @_;

        # Step 1: Parse Chalk source to IR
        my $ir_root = parse_chalk_file($source_file);
        return undef unless defined $ir_root;

        # Step 2: Build IR graph
        my $graph = build_ir_graph($ir_root);
        return undef unless defined $graph;

        # Step 3: Generate XS code
        my $xs_target = Chalk::Target::XS->new(
            graph => $graph,
            module_name => $module_name,
        );

        my $files = $xs_target->generate_files();
        return undef unless defined $files->{xs} && defined $files->{pmc};

        # Step 4: Write files to temp directory with proper namespace structure
        my $tempdir = tempdir(CLEANUP => 0);  # Keep files for inspection
        my @parts = split /::/, $module_name;
        my $file_name = pop @parts;
        my $module_dir = File::Spec->catdir($tempdir, @parts);
        File::Path::make_path($module_dir);

        my $xs_file = File::Spec->catfile($module_dir, "${file_name}.xs");
        my $pm_file = File::Spec->catfile($module_dir, "${file_name}.pm");

        open my $xs_fh, '>', $xs_file or do {
            warn "Cannot write $xs_file: $!";
            return undef;
        };
        print $xs_fh $files->{xs};
        close $xs_fh;

        open my $pm_fh, '>', $pm_file or do {
            warn "Cannot write $pm_file: $!";
            return undef;
        };
        print $pm_fh $files->{pmc};
        close $pm_fh;

        # Step 5: Compile XS to .so
        my $so_file = compile_xs($xs_file, $module_name);

        return {
            xs => $files->{xs},
            pmc => $files->{pmc},
            so_file => $so_file,
            tempdir => $tempdir,
            xs_file => $xs_file,
            pm_file => $pm_file,
        };
    }
}

1;
