# ABOUTME: Tests that XS BOOT block correctly emits :isa inheritance registration.
# ABOUTME: Validates that XS-compiled subclasses inherit from parent classes.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Path qw(make_path);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;
use Chalk::IR::Node::Return;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build IR for a class with :isa(Parent)
my $parent_name = 'Test::ISA::Parent';
my $child_name  = 'Test::ISA::Child';

my $child_method = $factory->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'greet'),
    params => [$factory->make('Constant', const_type => 'string', value => '$self')],
    body   => [
        $factory->make_cfg('Return',
            inputs => [
                $factory->make('Start'),
                $factory->make('Constant', const_type => 'string', value => 'hello'),
            ],
        ),
    ],
    return_type => undef,
);

my $class_decl = $factory->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory->make('Constant', const_type => 'string', value => $child_name),
    parent => $factory->make('Constant', const_type => 'string', value => $parent_name),
    body   => [$child_method],
);

my $program = $factory->make('Constructor',
    class      => 'Program',
    statements => [$class_decl],
);

# Generate XS wrapper and check it contains :isa registration
my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => $child_name,
);

my $c_result = eval { $target->_generate_c_files($program, undef, undef) };
ok(defined $c_result, '_generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

my $xs_text = eval {
    $target->generate_xs_wrapper(
        $program,
        $c_result->{exported_functions},
        $c_result->{anon_sub_registrations},
    );
};
ok(defined $xs_text, 'generate_xs_wrapper succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# The BOOT block should register the parent class
like($xs_text, qr/class_apply_attributes/, 'XS BOOT calls class_apply_attributes for :isa');
like($xs_text, qr/isa\(Test::ISA::Parent\)/, 'XS BOOT has isa(Parent) attribute');

# The forward declarations should include class_apply_attributes
like($xs_text, qr/extern.*class_apply_attributes/, 'class_apply_attributes is forward-declared');

# ============================================================
# Runtime verification: build and load a real child class,
# verify $obj->isa('Parent') returns true at runtime.
# ============================================================

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

SKIP: {
    skip 'No C compiler available', 3 unless $have_compiler;

    use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load fork_test);

    # Load the parent class as a plain Perl package so it exists in the
    # symbol table when the child's BOOT block runs class_apply_attributes.
    # A plain package is sufficient: class_apply_attributes registers @ISA
    # against the parent package name, and Perl isa() uses the MRO from there.
    #
    # We also write a .pm file to a temp dir and add it to @INC, because the
    # child's XS BOOT block (via class_apply_attributes) triggers a require
    # of the parent class even if it is already in the symbol table.
    my $parent_tmpdir = tempdir(CLEANUP => 1);
    make_path("$parent_tmpdir/Test/ISA/Runtime");
    my $parent_pm = "$parent_tmpdir/Test/ISA/Runtime/Parent.pm";
    open(my $pfh, '>', $parent_pm) or die "Cannot write parent pm: $!";
    print $pfh <<'PARENT_PM';
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
class Test::ISA::Runtime::Parent {
    method greet_from_parent() {
        return 'hello from parent';
    }
}
1;
PARENT_PM
    close $pfh;
    unshift @INC, $parent_tmpdir;

    my $parent_eval_ok = eval { require Test::ISA::Runtime::Parent; 1 };
    ok($parent_eval_ok, 'parent class loaded as pure-Perl') or do {
        diag "Parent require failed: $@";
        skip 'Parent class load failed', 2;
    };

    # Write a temp .pm file containing only the child class with :isa(Parent).
    my ($fh, $source_file) = tempfile(SUFFIX => '.pm', UNLINK => 1);
    print $fh <<'CHILD_CLASS';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class Test::ISA::Runtime::Child :isa(Test::ISA::Runtime::Parent) {
    field $name :param :reader;

    method greet() {
        return "hello from child: $name";
    }
}
CHILD_CLASS
    close $fh;

    # Parse child class to IR via the full Chalk grammar pipeline.
    my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSIsaRuntime') };
    ok(defined $gen, 'grammar pipeline setup for isa runtime test') or do {
        diag "setup_xs_grammar failed: $@";
        skip 'Grammar setup failed', 1;
    };

    my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $source_file) };
    ok(defined $ir, 'child class parses to IR') or do {
        diag "parse_file_ir failed: $@";
        skip 'IR parse failed', 0;
    };

    # Build and load the XS child class.
    my ($result, $build_err) = eval { build_and_load($ir, $sa, $ctx, 'Test::ISA::Runtime::Child') };
    ok(defined $result, 'child XS module built and loaded') or do {
        diag "build_and_load failed: " . ($build_err // $@);
        skip 'XS build failed', 0;
    };

    # Behavioral verification: fork so a segfault cannot abort the test process.
    fork_test('Test::ISA::Runtime::Child', sub ($mod) {
        my $obj = $mod->new(name => 'tester');
        die "isa(Parent) returned false"
            unless $obj->isa('Test::ISA::Runtime::Parent');
        die "isa(Child) returned false"
            unless $obj->isa('Test::ISA::Runtime::Child');
        die "greet() returned wrong value: " . $obj->greet()
            unless $obj->greet() eq 'hello from child: tester';
        die "greet_from_parent() returned wrong value: " . $obj->greet_from_parent()
            unless $obj->greet_from_parent() eq 'hello from parent';
    }, 'runtime isa and inherited method dispatch');
}

done_testing();
