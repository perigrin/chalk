# ABOUTME: Tests that XS BOOT block correctly emits :isa inheritance registration.
# ABOUTME: Validates that XS-compiled subclasses inherit from parent classes.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

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
        $factory->make('Constructor',
            class => 'ReturnStmt',
            value => $factory->make('Constant', const_type => 'string', value => 'hello'),
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

my $c_result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $c_result, 'generate_c_files succeeds') or do {
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

done_testing();
