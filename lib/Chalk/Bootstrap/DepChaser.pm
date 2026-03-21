# ABOUTME: IR-driven dependency resolver for XS bootstrap compilation.
# ABOUTME: Extracts UseDecl module names from IR and resolves transitive closure.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::Node::Constructor;
use Chalk::Bootstrap::IR::Node::Constant;

class Chalk::Bootstrap::DepChaser {

    # Extract module names from UseDecl Constructor nodes in a Program IR.
    # Walks top-level statements looking for Constructor:UseDecl nodes.
    # Returns a list of module name strings.
    sub extract_use_decls($ir) {
        return unless defined $ir;
        return unless $ir isa Chalk::Bootstrap::IR::Node::Constructor;
        return unless $ir->class() eq 'Program';

        # Program's inputs()->[0] is the statements arrayref
        my $statements = $ir->inputs()->[0];
        return unless defined $statements && ref($statements) eq 'ARRAY';

        my @modules;
        for my $stmt ($statements->@*) {
            next unless $stmt isa Chalk::Bootstrap::IR::Node::Constructor;
            next unless $stmt->class() eq 'UseDecl';
            my $name_node = $stmt->inputs()->[0];
            next unless defined $name_node;
            next unless $name_node isa Chalk::Bootstrap::IR::Node::Constant;
            push @modules, $name_node->value();
        }
        return @modules;
    }

    # Map a module name to a lib/ relative path, only for Chalk:: modules.
    # Returns undef for non-Chalk modules (core, CPAN, etc.)
    sub module_to_path($module_name) {
        return unless $module_name =~ /^Chalk::/;
        my $path = $module_name;
        $path =~ s{::}{/}g;
        return "lib/$path.pm";
    }

    # Resolve the full transitive dependency closure starting from a root file.
    # Parses each file through the Chalk pipeline, extracts UseDecls, and recurses.
    # Returns list of file paths (excluding the root itself).
    sub resolve_deps($root_file, %opts) {
        my $grammar = _build_grammar('DepChaser', %opts);

        my %seen;       # file path => 1
        my @result;     # ordered dep list
        my @queue = ($root_file);

        while (@queue) {
            my $file = shift @queue;
            next if $seen{$file}++;
            next unless -f $file;

            my $ir = _parse_file_to_ir($grammar, $file);
            if (defined $ir) {
                my @modules = extract_use_decls($ir);
                for my $mod (@modules) {
                    my $path = module_to_path($mod);
                    next unless defined $path;
                    next unless -f $path;
                    next if $seen{$path};
                    push @queue, $path;
                }
            }

            # Add to result (but not the root file)
            push @result, $file unless $file eq $root_file;
        }

        return @result;
    }

    # Resolve the full transitive closure from multiple seed files.
    # Pass 1: BFS to discover all files and their dep edges.
    # Pass 2: Topological sort so deps come before dependents.
    # Returns a list of all file paths (seeds + transitive deps), deduplicated.
    sub resolve_closure($seed_files, %opts) {
        my $grammar = _build_grammar('DepClosure', %opts);

        # Pass 1: BFS — collect all files and their dependency edges
        my %seen;          # file path => 1
        my %deps_of;       # file => [dep_files]
        my @queue = ($seed_files->@*);

        while (@queue) {
            my $file = shift @queue;
            next if $seen{$file}++;
            next unless -f $file;

            my @dep_paths;
            my $ir = _parse_file_to_ir($grammar, $file);
            if (defined $ir) {
                my @modules = extract_use_decls($ir);
                for my $mod (@modules) {
                    my $path = module_to_path($mod);
                    next unless defined $path;
                    next unless -f $path;
                    push @dep_paths, $path;
                    push @queue, $path unless $seen{$path};
                }
            }
            $deps_of{$file} = \@dep_paths;
        }

        # Pass 2: Topological sort (Kahn's algorithm)
        # deps_of{A} = [B, C] means A depends on B and C, so B and C must come first.
        # Build reverse graph: dependents_of{B} = [A] means "A depends on B".
        # in_degree{A} = number of deps A has (= things that must come before A).
        my %dependents_of;  # dep => [files that depend on it]
        my %in_degree;
        for my $file (keys %deps_of) {
            $in_degree{$file} //= 0;
            for my $dep ($deps_of{$file}->@*) {
                push $dependents_of{$dep}->@*, $file;
                $in_degree{$file}++;
            }
            # Ensure leaf deps appear in in_degree
            for my $dep ($deps_of{$file}->@*) {
                $in_degree{$dep} //= 0;
            }
        }

        # Files with in_degree 0 have no deps — they go first
        my @ready = sort grep { $in_degree{$_} == 0 } keys %in_degree;
        my @sorted;
        while (@ready) {
            my $file = shift @ready;
            push @sorted, $file;
            for my $dependent (($dependents_of{$file} // [])->@*) {
                $in_degree{$dependent}--;
                if ($in_degree{$dependent} == 0) {
                    # Insert sorted to keep deterministic order
                    my $idx = 0;
                    $idx++ while $idx < scalar(@ready) && $ready[$idx] lt $dependent;
                    splice @ready, $idx, 0, $dependent;
                }
            }
        }

        return @sorted;
    }

    # Shared helper: build grammar pipeline for dep resolution
    sub _build_grammar($namespace_suffix, %opts) {
        return $opts{grammar} if defined $opts{grammar};

        require TestPipeline;
        require Chalk::Bootstrap::BNF::Target::Perl;
        require Chalk::Bootstrap::IR::NodeFactory;
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        my $raw_ir = TestPipeline::perl_pipeline();
        die "perl_pipeline returned undef" unless defined $raw_ir;
        my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $bnf_target->generate($raw_ir);
        my $ns = "Chalk::Grammar::Perl::$namespace_suffix";
        $generated =~ s/Chalk::Grammar::BNF::Generated/$ns/g;
        eval "$generated; 1" or die "Grammar eval failed: $@";
        no strict 'refs';
        return "${ns}::grammar"->();
    }

    # Shared helper: parse a single file to IR, return Program node or undef
    sub _parse_file_to_ir($grammar, $file) {
        require Chalk::Bootstrap::IR::NodeFactory;
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        require TestPipeline;
        my $parser = TestPipeline::build_perl_ir_parser($grammar, start => 'Program');
        my $semiring = $parser->semiring();
        $semiring->reset_cache();

        open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
        local $/;
        my $source = <$fh>;
        close $fh;

        my $parse_result = $parser->parse_value($source);
        return unless defined $parse_result;

        my $sem_ctx = $parse_result->[4];
        return unless defined $sem_ctx;
        return $sem_ctx->extract();
    }
}
