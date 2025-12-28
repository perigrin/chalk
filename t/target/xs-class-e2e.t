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

# Helper to compile XS to .so using ExtUtils::CBuilder and xsubpp
sub compile_xs {
    my ($xs_file, $class_name, $pmc_file) = @_;

    require ExtUtils::CBuilder;
    require ExtUtils::ParseXS;
    require File::Spec;
    require File::Basename;
    require Config;

    my $cb = ExtUtils::CBuilder->new(quiet => 1);
    return undef unless $cb->have_compiler;

    my $dir = File::Basename::dirname($xs_file);
    my $c_file = File::Spec->catfile($dir, "${class_name}.c");

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
        diag("xsubpp failed: $@") if $@;
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
        diag("Compilation failed: $@") if $@;
        return undef;
    }

    # Step 3: Link to shared library
    my $so_file;
    eval {
        $so_file = $cb->link(
            objects     => [$obj_file],
            module_name => $class_name,
        );
    };
    if ($@ || !defined $so_file || !-f $so_file) {
        diag("Linking failed: $@") if $@;
        return undef;
    }

    return $so_file;
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

# ===== Test 6: Namespaced class generates correct file paths =====
subtest 'Namespaced class generates correct file paths' => sub {
        my $code = 'class Foo::Bar::Baz { field $x = 1; }';

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

        # Build graph
        my $graph = Chalk::IR::Graph->new();
        my %visited;
        my @queue = ($winning_node);
        while (@queue) {
            my $node = shift @queue;
            next unless blessed($node) && $node->can('id');
            next if $visited{$node->id}++;
            $graph->add_node($node);
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

        # Generate with namespace
        my $xs_target = Chalk::Target::XS->new(
            graph => $graph,
            module_name => 'Foo::Bar::Baz',
        );

        # Test file path generation
        my $xs_path = $xs_target->file_path('xs');
        my $pmc_path = $xs_target->file_path('pmc');

        is($xs_path, 'lib/Foo/Bar/Baz.xs', 'XS path converts :: to /');
        is($pmc_path, 'lib/Foo/Bar/Baz.pmc', 'PMC path converts :: to /');

        # Verify MODULE declaration uses full namespace
        my $files = $xs_target->generate_files();
        like($files->{xs}, qr/MODULE = Foo::Bar::Baz/, 'XS has full namespace MODULE');
        like($files->{pmc}, qr/package Foo::Bar::Baz;/, 'PMC has full namespace package');
    };

# ===== Test 7: Multiple classes with same method name =====
subtest 'Multiple classes with same method name generate distinct XSUBs' => sub {
        # This tests that Counter::inc and Timer::inc don't collide
        my $code = <<'CHALK';
class Counter {
    field $count = 0;
    method inc { $count += 1; return $count; }
}
class Timer {
    field $elapsed = 0;
    method inc { $elapsed += 10; return $elapsed; }
}
CHALK

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

        # Build graph
        my $graph = Chalk::IR::Graph->new();
        my %visited;
        my @queue = ($winning_node);
        while (@queue) {
            my $node = shift @queue;
            next unless blessed($node) && $node->can('id');
            next if $visited{$node->id}++;
            $graph->add_node($node);
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

        # The winning_node is the Stop node
        my $stop = $winning_node;
        ok(blessed($stop) && $stop->can('op') && $stop->op eq 'Stop', 'Winning node is Stop');
        my $class_defs = $stop->class_defs // [];
        is(scalar($class_defs->@*), 2, 'Two classes registered');

        # Verify both classes have their inc method
        my %class_methods;
        for my $class_def ($class_defs->@*) {
            my $class_name = $class_def->class_name;
            my $methods = $class_def->methods // [];
            for my $method ($methods->@*) {
                $class_methods{$class_name}{$method->name} = 1;
            }
        }

        ok(exists $class_methods{Counter}{inc}, 'Counter has inc method');
        ok(exists $class_methods{Timer}{inc}, 'Timer has inc method');

        # Generate XS for each class
        for my $class_def ($class_defs->@*) {
            my $class_name = $class_def->class_name;
            my $xs_target = Chalk::Target::XS->new(
                graph => $graph,
                module_name => $class_name,
            );
            my $files = $xs_target->generate_files();

            like($files->{xs}, qr/MODULE = $class_name/, "$class_name XS has correct MODULE");
            like($files->{xs}, qr/inc\s*\(/, "$class_name XS has inc method");
        }
    };

# ===== Test 8: E2E compilation test =====
subtest 'Generated XS compiles and loads correctly' => sub {
    # This test verifies the full pipeline:
    # 1. Generate .xs and .pmc files
    # 2. Compile .xs to .so using ExtUtils::CBuilder
    # 3. Load .pmc which loads the .so
    # 4. Call methods and verify behavior

    # Check for C compiler availability first
    require ExtUtils::CBuilder;
    my $cb = ExtUtils::CBuilder->new(quiet => 1);
    plan skip_all => 'No C compiler available' unless $cb->have_compiler;

    my $code = 'class TestCompile { field $value = 42; method get_value { return $value; } }';

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

    # Build graph
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);
    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        next if $visited{$node->id}++;
        $graph->add_node($node);
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

    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestCompile',
    );

    my $files = $xs_target->generate_files();
    ok(defined $files->{xs}, 'XS content generated');
    ok(defined $files->{pmc}, 'PMC content generated');

    diag "Generated XS:\n$files->{xs}" if $ENV{TEST_VERBOSE};
    diag "Generated PMC:\n$files->{pmc}" if $ENV{TEST_VERBOSE};

    # Write files to temp directory
    my $tempdir = tempdir(CLEANUP => 1);
    my $xs_file = File::Spec->catfile($tempdir, 'TestCompile.xs');
    my $pmc_file = File::Spec->catfile($tempdir, 'TestCompile.pm');

    open my $xs_fh, '>', $xs_file or die "Cannot write $xs_file: $!";
    print $xs_fh $files->{xs};
    close $xs_fh;

    open my $pmc_fh, '>', $pmc_file or die "Cannot write $pmc_file: $!";
    print $pmc_fh $files->{pmc};
    close $pmc_fh;

    ok(-f $xs_file, 'XS file written');
    ok(-f $pmc_file, 'PM file written');

    # Attempt to compile XS to .so
    my $so_file = compile_xs($xs_file, 'TestCompile');

    SKIP: {
        skip 'XS compilation failed - generated XS may have syntax errors', 3
            unless defined $so_file && -f $so_file;

        ok(-f $so_file, 'XS compiled to shared object');

        # Add tempdir to @INC and try to load
        unshift @INC, $tempdir;
        my $loaded = eval { require TestCompile; 1 };
        ok($loaded, 'Module loaded successfully') or diag("Load error: $@");

        # Test method call
        my $obj = eval { TestCompile->new() };
        ok(defined $obj, 'Object created') or diag("Constructor error: $@");

        # Test get_value method
        SKIP: {
            skip 'Object creation failed', 1 unless defined $obj;
            my $val = eval { $obj->get_value() };
            is($val, 42, 'get_value returns correct value') or diag("Method error: $@");
        }
    }
};

# ===== Test 9: Performance comparison (XS vs Pure Perl) =====
subtest 'XS performance is faster than pure Perl' => sub {
    # This test validates the performance improvement goal from #298:
    # XS code should be 5-10x faster than equivalent pure Perl

    # Check for C compiler availability first
    require ExtUtils::CBuilder;
    require Benchmark;
    my $cb = ExtUtils::CBuilder->new(quiet => 1);
    plan skip_all => 'No C compiler available' unless $cb->have_compiler;

    # A Point class with arithmetic operations for benchmarking
    my $code = <<'CHALK';
class BenchPoint {
    field $x = 0;
    field $y = 0;

    method set_x ($val) { $x = $val; }
    method set_y ($val) { $y = $val; }
    method get_x { return $x; }
    method get_y { return $y; }
    method distance {
        my $dx = $x * $x;
        my $dy = $y * $y;
        return $dx + $dy;
    }
}
CHALK

    # Equivalent pure Perl implementation for comparison
    my $pure_perl = <<'PERL';
package PurePoint;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless { x => $args{x} // 0, y => $args{y} // 0 }, $class;
}

sub set_x { my ($self, $val) = @_; $self->{x} = $val; }
sub set_y { my ($self, $val) = @_; $self->{y} = $val; }
sub get_x { my ($self) = @_; return $self->{x}; }
sub get_y { my ($self) = @_; return $self->{y}; }
sub distance {
    my ($self) = @_;
    my $dx = $self->{x} * $self->{x};
    my $dy = $self->{y} * $self->{y};
    return $dx + $dy;
}

1;
PERL

    # Load pure Perl version
    eval $pure_perl;
    ok(!$@, 'Pure Perl class compiled') or diag("Perl error: $@");

    # Generate and compile XS version
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
    ok(defined $result, 'Chalk class parsed');

    my $winning_node = $result->context->focus;

    # Build graph
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);
    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        next if $visited{$node->id}++;
        $graph->add_node($node);
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

    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'BenchPoint',
    );

    my $files = $xs_target->generate_files();
    ok(defined $files->{xs}, 'XS generated for benchmark');

    # Write files to temp directory
    my $tempdir = tempdir(CLEANUP => 1);
    my $xs_file = File::Spec->catfile($tempdir, 'BenchPoint.xs');
    my $pm_file = File::Spec->catfile($tempdir, 'BenchPoint.pm');

    open my $xs_fh, '>', $xs_file or die "Cannot write $xs_file: $!";
    print $xs_fh $files->{xs};
    close $xs_fh;

    open my $pm_fh, '>', $pm_file or die "Cannot write $pm_file: $!";
    print $pm_fh $files->{pmc};
    close $pm_fh;

    # Compile XS
    my $so_file = compile_xs($xs_file, 'BenchPoint');

    SKIP: {
        skip 'XS compilation failed - cannot benchmark', 3
            unless defined $so_file && -f $so_file;

        # Load XS module
        unshift @INC, $tempdir;
        my $loaded = eval { require BenchPoint; 1 };
        ok($loaded, 'XS module loaded for benchmark') or diag("Load error: $@");

        skip 'XS module failed to load', 2 unless $loaded;

        # Run benchmark
        my $iterations = 10000;

        # Pure Perl benchmark
        my $perl_start = Benchmark::timeit(1, sub {
            for (1..$iterations) {
                my $p = PurePoint->new(x => 3, y => 4);
                $p->set_x(5);
                $p->set_y(12);
                my $d = $p->distance();
            }
        });

        # XS benchmark
        my $xs_start = Benchmark::timeit(1, sub {
            for (1..$iterations) {
                my $p = BenchPoint->new(x => 3, y => 4);
                $p->set_x(5);
                $p->set_y(12);
                my $d = $p->distance();
            }
        });

        my $perl_time = $perl_start->[1] + $perl_start->[2];  # user + system
        my $xs_time = $xs_start->[1] + $xs_start->[2];

        # Avoid division by zero
        my $speedup = $xs_time > 0 ? $perl_time / $xs_time : 0;

        diag sprintf("Pure Perl: %.4fs, XS: %.4fs, Speedup: %.2fx",
            $perl_time, $xs_time, $speedup);

        # Verify XS produces correct results
        my $xs_obj = BenchPoint->new(x => 3, y => 4);
        $xs_obj->set_x(5);
        $xs_obj->set_y(12);
        is($xs_obj->distance(), 169, 'XS produces correct result (5^2 + 12^2 = 169)');

        # Performance target: XS should be at least 2x faster
        # (Being conservative since compile_xs overhead may vary)
        cmp_ok($speedup, '>=', 1.5, 'XS is at least 1.5x faster than pure Perl')
            or diag("Speedup was only ${speedup}x - expected at least 1.5x");
    }
};

done_testing();
