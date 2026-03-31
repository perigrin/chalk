# ABOUTME: Tests that XS wrapper emits correct aTHX calls for void-param functions.
# ABOUTME: Validates init_statics filter works when class slug differs from module slug.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build a minimal IR: a class with one method (so we get exported_functions)
my $class_name = 'Foo::Bar::Baz';
my $method_body_return = $factory->make('Constructor',
    class => 'ReturnStmt',
    value => $factory->make('Constant', const_type => 'string', value => '1'),
);
my $method = $factory->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'hello'),
    params => [$factory->make('Constant', const_type => 'string', value => '$self')],
    body   => [$method_body_return],
    return_type => undef,
);
my $class_decl = $factory->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory->make('Constant', const_type => 'string', value => $class_name),
    parent => undef,
    body   => [$method],
);
my $program = $factory->make('Constructor',
    class      => 'Program',
    statements => [$class_decl],
);

# Use a module name that produces a different slug than the class name.
# Class slug: baz (from Foo::Bar::Baz)
# Module slug: testbaz (from Some::Module::TestBaz)
my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Some::Module::TestBaz',
);

# Generate C files (sets up class slug from IR)
my $c_result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $c_result, 'generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# The C function should use class slug 'baz' → baz_init_statics
my $c_file = $c_result->{files}{'baz.c'};
ok(defined $c_file, 'C file exists with class slug');
like($c_file, qr/void baz_init_statics\(pTHX\)/, 'init_statics uses class slug');

# Generate XS wrapper — this should NOT produce aTHX_ with no trailing args
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

# The XS BOOT block should call baz_init_statics(aTHX) — using class slug
like($xs_text, qr/baz_init_statics\(aTHX\)/, 'BOOT calls init_statics using class slug');

# init_statics should NOT appear as a regular XSUB function declaration
unlike($xs_text, qr/^baz_init_statics\(/m, 'init_statics not exposed as XSUB function');

# No aTHX_ followed by ) anywhere (the generic fix)
unlike($xs_text, qr/aTHX_\s*\)/, 'no aTHX_ with empty args anywhere in XS');

done_testing();
