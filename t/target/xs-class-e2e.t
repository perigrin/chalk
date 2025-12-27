# ABOUTME: End-to-end tests for XS class compilation from Chalk source
# ABOUTME: Tests full pipeline: class source → parse → IR → XS → compile → load

use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Chalk::IR::Graph;
use Chalk::Target::XS;

# Helper to generate XS from Chalk class source code
sub generate_xs {
    my ($code, $class_name) = @_;
    $class_name //= 'TestClass';

    # Reset TypeRegistry to avoid state leaking between tests
    # (e.g., Test 2 uses Counter, Test 4 also uses Counter with method)
    Chalk::Grammar::Chalk::TypeRegistry->instance->reset();

    my $bnf_file = "grammar/chalk.bnf";
    open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Get winning node
    my $winning_node;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx->can('focus')) {
            $winning_node = $ctx->focus;
        }
    }
    return undef unless $winning_node && blessed($winning_node) && $winning_node->can('id');

    # Build graph
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse node references
        for my $method (qw(value_node value control left right operand condition source call callee)) {
            next unless $node->can($method);
            my $ref = $node->$method;
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }

        # Handle arrays
        for my $method (qw(branches control_users args)) {
            next unless $node->can($method) && $node->$method;
            for my $ref ($node->$method->@*) {
                next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                push @queue, $ref;
            }
        }

        # Traverse return_nodes for Stop
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }

        # Traverse function_defs for Stop
        if ($node->can('function_defs') && $node->function_defs) {
            for my $func ($node->function_defs->@*) {
                push @queue, $func if blessed($func) && $func->can('id') && !$visited{$func->id};
            }
        }

        # Traverse class_defs for Stop (new for Chapter 23)
        if ($node->can('class_defs') && $node->class_defs) {
            for my $class ($node->class_defs->@*) {
                push @queue, $class if blessed($class) && $class->can('id') && !$visited{$class->id};
            }
        }

        # Traverse fields for ClassDef
        if ($node->can('fields') && $node->fields) {
            for my $field ($node->fields->@*) {
                push @queue, $field if blessed($field) && $field->can('id') && !$visited{$field->id};
            }
        }

        # Traverse methods for ClassDef
        if ($node->can('methods') && $node->methods) {
            for my $method ($node->methods->@*) {
                push @queue, $method if blessed($method) && $method->can('id') && !$visited{$method->id};
            }
        }
    }

    # Generate XS
    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => $class_name,
    );

    my $xs_ast = $xs_target->generate();
    return $xs_ast->emit();
}

# Helper to compile XS to .so (placeholder for future)
sub compile_xs {
    my ($xs_file, $class_name) = @_;
    # TODO: Implement with ExtUtils::CBuilder
    # This will be used when we're ready to test actual compilation
    return undef;
}

# ===== Test 1: Empty class generates valid XS structure =====
subtest 'Empty class generates XS module' => sub {
        my $code = 'class Empty { }';
        my $xs = generate_xs($code, 'Empty');

        ok(defined $xs, 'XS generated');
        diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

        like($xs, qr/MODULE = Empty/, 'Has MODULE declaration');
        like($xs, qr/PACKAGE = Empty/, 'Has PACKAGE declaration');
    };

# ===== Test 2: Class with field generates constructor =====
subtest 'Class with field generates constructor' => sub {
        my $code = 'class Counter { field $count = 0; }';
        my $xs = generate_xs($code, 'Counter');

        ok(defined $xs, 'XS generated');
        diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

        like($xs, qr/MODULE = Counter/, 'Has MODULE declaration');
        like($xs, qr/new\s*\(/, 'Has constructor method');
        like($xs, qr/ObjectFIELDS/, 'Uses ObjectFIELDS for field storage');
        like($xs, qr/ObjectMAXFIELD/, 'Sets ObjectMAXFIELD');
    };

# ===== Test 3: Class with method generates XSUB =====
subtest 'Class with method generates callable XSUB' => sub {
        my $code = 'class Greeter { method hello { return "Hello"; } }';
        my $xs = generate_xs($code, 'Greeter');

        ok(defined $xs, 'XS generated');
        diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

        like($xs, qr/MODULE = Greeter/, 'Has MODULE declaration');
        like($xs, qr/hello\s*\(/, 'Has hello method');
        like($xs, qr/SV\*\s+self/, 'Method has $self parameter');
        like($xs, qr/RETVAL/, 'Method has RETVAL');
    };

# ===== Test 4: Method with field access =====
subtest 'Method with field access via ObjectFIELDS' => sub {
        my $code = 'class Counter { field $count = 0; method inc { $count += 1; return $count; } }';
        my $xs = generate_xs($code, 'Counter');

        ok(defined $xs, 'XS generated');
        diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};

        like($xs, qr/MODULE = Counter/, 'Has MODULE declaration');
        like($xs, qr/inc\s*\(/, 'Has inc method');
        like($xs, qr/ObjectFIELDS\s*\(\s*self\s*\)\s*\[\s*\d+\s*\]/, 'Accesses field via ObjectFIELDS[index]');
    };

# ===== Test 5: Multi-file output generates .xs and .pmc =====
subtest 'Multi-file output generates .xs and .pmc' => sub {
        my $code = 'class Counter { field $count = 0; method inc { $count += 1; return $count; } }';

        # Reset TypeRegistry
        Chalk::Grammar::Chalk::TypeRegistry->instance->reset();

        my $bnf_file = "grammar/chalk.bnf";
        open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
        my $content = do { local $/; <$fh> };
        close $fh;

        my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
        my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $semiring,
        );

        my $result = $parser->parse_string($code);
        ok(defined $result, 'Parsed successfully');

        my $winning_node = $result->context->focus;

        # Build graph (same as generate_xs helper)
        my $graph = Chalk::IR::Graph->new();
        my %visited;
        my @queue = ($winning_node);
        while (@queue) {
            my $node = shift @queue;
            next unless blessed($node) && $node->can('id');
            next if $visited{$node->id}++;
            $graph->add_node($node);
            # Traverse references
            for my $method (qw(value_node value control left right operand condition source call callee)) {
                next unless $node->can($method);
                my $ref = $node->$method;
                push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            }
            for my $method (qw(branches control_users args return_nodes function_defs class_defs fields methods)) {
                next unless $node->can($method) && $node->$method;
                for my $ref ($node->$method->@*) {
                    push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                }
            }
        }

        # Generate multi-file output
        my $xs_target = Chalk::Target::XS->new(
            graph => $graph,
            module_name => 'Counter',
        );

        # New API: generate_files() returns hashref with xs and pmc content
        my $files = $xs_target->generate_files();

        ok(ref($files) eq 'HASH', 'generate_files returns hashref');
        ok(exists $files->{xs}, 'Has xs key');
        ok(exists $files->{pmc}, 'Has pmc key');

        # Verify XS content
        my $xs = $files->{xs};
        like($xs, qr/MODULE = Counter/, 'XS has MODULE declaration');
        like($xs, qr/new\s*\(/, 'XS has constructor');

        # Verify PMC content
        my $pmc = $files->{pmc};
        like($pmc, qr/package Counter;/, 'PMC has package declaration');
        like($pmc, qr/use XSLoader/, 'PMC uses XSLoader');
        like($pmc, qr/XSLoader::load/, 'PMC calls XSLoader::load');

        diag "Generated XS:\n$xs" if $ENV{TEST_VERBOSE};
        diag "Generated PMC:\n$pmc" if $ENV{TEST_VERBOSE};
    };

done_testing();
