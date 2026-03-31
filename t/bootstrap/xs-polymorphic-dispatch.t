# ABOUTME: Unit tests for the polymorphic dispatch map in Target::C.
# ABOUTME: Verifies that compiled_class_metadata is used to build $_polymorphic_dispatch.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

# Build a minimal IR: a class with a single no-op method so generate_c_files
# has something to process without hitting undef errors.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $method = $factory->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'stub'),
    params => [
        $factory->make('Constant', const_type => 'string', value => '$self'),
    ],
    body   => [
        $factory->make('Constructor',
            class => 'ReturnStmt',
            value => $factory->make('Constant', const_type => 'string', value => '1'),
        ),
    ],
    return_type => undef,
);

my $class_decl = $factory->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'Test::Dispatch::Host'),
    parent => undef,
    body   => [$method],
);

my $program = $factory->make('Constructor',
    class      => 'Program',
    statements => [$class_decl],
);

# Three fake compiled classes all implement is_zero, add, multiply.
# One class (Alpha) also has a unique method special (single-owner).
my $compiled_metadata = {
    'Test::Semiring::Alpha' => {
        slug    => 'testsemiringalpha',
        readers => {},
        methods => {
            is_zero   => 1,
            add       => 1,
            multiply  => 1,
            special   => 1,
        },
    },
    'Test::Semiring::Beta' => {
        slug    => 'testsemiringbeta',
        readers => {},
        methods => {
            is_zero  => 1,
            add      => 1,
            multiply => 1,
        },
    },
    'Test::Semiring::Gamma' => {
        slug    => 'testsemiringgamma',
        readers => {},
        methods => {
            is_zero  => 1,
            add      => 1,
            multiply => 1,
        },
    },
};

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name             => 'Test::Dispatch::Host',
    compiled_class_metadata => $compiled_metadata,
);

my $result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $result, 'generate_c_files succeeds with compiled_class_metadata') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# --- Verify _polymorphic_dispatch ---

my $poly = $target->_polymorphic_dispatch();
ok(defined $poly, '_polymorphic_dispatch is defined after generate_c_files');
is(ref $poly, 'HASH', '_polymorphic_dispatch is a hashref');

# Multi-owner methods should be in _polymorphic_dispatch
for my $meth (qw(is_zero add multiply)) {
    ok(exists $poly->{$meth}, "_polymorphic_dispatch has '$meth' (3-owner method)");
    is(scalar $poly->{$meth}->@*, 3, "_polymorphic_dispatch '$meth' has 3 candidates");
}

# Verify candidate structure: each entry must have slug and class_name
for my $meth (qw(is_zero add multiply)) {
    for my $candidate ($poly->{$meth}->@*) {
        ok(exists $candidate->{slug},       "candidate for '$meth' has slug");
        ok(exists $candidate->{class_name}, "candidate for '$meth' has class_name");
    }
}

# Single-owner method must NOT be in _polymorphic_dispatch
ok(!exists $poly->{special}, "_polymorphic_dispatch does NOT have 'special' (single-owner)");

# Also verify stub (local method on Host class) is not in _polymorphic_dispatch
ok(!exists $poly->{stub}, "_polymorphic_dispatch does NOT have 'stub' (local method)");

# --- Verify _method_dispatch still handles the single-owner method ---

my $mono = $target->_method_dispatch();
ok(defined $mono, '_method_dispatch is defined');
ok(exists $mono->{special}, "_method_dispatch DOES have 'special' (single-owner)");

# is_zero/add/multiply must NOT be in _method_dispatch (they're multi-owner)
for my $meth (qw(is_zero add multiply)) {
    ok(!exists $mono->{$meth}, "_method_dispatch does NOT have '$meth' (multi-owner, excluded)");
}

# --- Verify Component 3: stash statics, init_statics, and cross-class includes ---

my $c_result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $c_result, 'generate_c_files returns a result for Component 3 checks') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

my $c_text = $c_result->{files}{'host.c'};
ok(defined $c_text, 'generated .c file exists in result') or do {
    diag 'Keys: ' . join(', ', sort keys $c_result->{files}->%*);
    done_testing();
    exit;
};

# --- Static HV* stash pointer declarations ---
# Slugs are taken from compiled_class_metadata directly (not derived by _class_slug).
# The metadata sets: testsemiringalpha, testsemiringbeta, testsemiringgamma.
for my $slug (qw(testsemiringalpha testsemiringbeta testsemiringgamma)) {
    like($c_text, qr/static HV \*_${slug}_stash = NULL;/,
        "generated C contains static stash declaration for '$slug'");
}

# --- gv_stashpvn population in init_statics ---
# init_statics must populate each stash from the full class name.
my %expected_stashpvn = (
    'testsemiringalpha' => 'Test::Semiring::Alpha',
    'testsemiringbeta'  => 'Test::Semiring::Beta',
    'testsemiringgamma' => 'Test::Semiring::Gamma',
);
for my $slug (sort keys %expected_stashpvn) {
    my $class_name = $expected_stashpvn{$slug};
    my $len        = length($class_name);
    like($c_text,
        qr/\Q_${slug}_stash = gv_stashpvn("${class_name}", ${len}, GV_ADD);\E/,
        "init_statics populates _${slug}_stash via gv_stashpvn");
}

# --- Cross-class #include directives ---
# Each unique polymorphic-dispatch slug must be included (except self-include).
for my $slug (qw(testsemiringalpha testsemiringbeta testsemiringgamma)) {
    like($c_text, qr/#include "${slug}\.h"/,
        "generated C includes header for polymorphic-dispatch slug '$slug'");
}

# The poly-dispatch includes appear only once even if a slug also appears
# in field_types — create a second result using field_types that overlaps.
# Verify no duplicate includes for 'testsemiringalpha' (count occurrences).
my $alpha_include_count = () = $c_text =~ /#include "testsemiringalpha\.h"/g;
is($alpha_include_count, 1, '#include "testsemiringalpha.h" appears exactly once (no duplicates)');

# --- Component 2: Stash-compare dispatch chains in generated C ---
#
# Build a new IR program with a method that calls is_zero on an unknown-typed
# parameter $sr.  The invocant is NOT self and NOT a field_types-typed field,
# so it must fall through to the polymorphic-dispatch tier.
#   method check($sr, $v) { return $sr->is_zero($v); }

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory2 = Chalk::Bootstrap::IR::NodeFactory->instance();

my $call_node = $factory2->make('Constructor',
    class       => 'MethodCallExpr',
    invocant    => $factory2->make('Constant', const_type => 'string', value => '$sr'),
    method_name => $factory2->make('Constant', const_type => 'string', value => 'is_zero'),
    args        => [
        $factory2->make('Constant', const_type => 'string', value => '$v'),
    ],
);

my $check_method = $factory2->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory2->make('Constant', const_type => 'string', value => 'check'),
    params => [
        $factory2->make('Constant', const_type => 'string', value => '$self'),
        $factory2->make('Constant', const_type => 'string', value => '$sr'),
        $factory2->make('Constant', const_type => 'string', value => '$v'),
    ],
    body   => [
        $factory2->make('Constructor',
            class => 'ReturnStmt',
            value => $call_node,
        ),
    ],
    return_type => undef,
);

my $class_decl2 = $factory2->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory2->make('Constant', const_type => 'string', value => 'Test::Dispatch::Host2'),
    parent => undef,
    body   => [$check_method],
);

my $program2 = $factory2->make('Constructor',
    class      => 'Program',
    statements => [$class_decl2],
);

my $target2 = Chalk::Bootstrap::Perl::Target::C->new(
    module_name             => 'Test::Dispatch::Host2',
    compiled_class_metadata => $compiled_metadata,
);

my $result2 = eval { $target2->generate_c_files($program2, undef, undef) };
ok(defined $result2, 'generate_c_files succeeds for Component 2 stash-compare test') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

my $c_text2 = $result2->{files}{'host2.c'};
ok(defined $c_text2, 'Component 2: generated .c file exists') or do {
    diag 'Keys: ' . join(', ', sort keys $result2->{files}->%*);
    done_testing();
    exit;
};

# The stash-compare pattern must appear in the generated method.
like($c_text2, qr/SvSTASH\s*\(\s*SvRV\s*\(/,
    'Component 2: generated C contains stash-compare SvSTASH(SvRV(');

# Direct C calls for each polymorphic candidate must appear.
for my $slug (qw(testsemiringalpha testsemiringbeta testsemiringgamma)) {
    like($c_text2, qr/\b${slug}_is_zero\b/,
        "Component 2: generated C contains direct call ${slug}_is_zero");
}

# call_method fallback must still appear (for uncompiled classes).
like($c_text2, qr/call_method\s*\(\s*"is_zero"/,
    'Component 2: generated C retains call_method fallback for is_zero');

# The stash comparison must use the stash pointer statics populated by init_statics.
for my $slug (qw(testsemiringalpha testsemiringbeta testsemiringgamma)) {
    like($c_text2, qr/_${slug}_stash/,
        "Component 2: generated C references _${slug}_stash pointer static");
}

# ============================================================
# Reader edge case: shared :reader names must NOT appear in
# $_polymorphic_dispatch (readers use ObjectFIELDS, not C calls)
# ============================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $method_node = $f->make('Constructor',
        class  => 'MethodDecl',
        name   => $f->make('Constant', const_type => 'string', value => 'stub'),
        params => [$f->make('Constant', const_type => 'string', value => '$self')],
        body   => [
            $f->make('Constructor',
                class => 'ReturnStmt',
                value => $f->make('Constant', const_type => 'string', value => '1'),
            ),
        ],
        return_type => undef,
    );

    my $class_decl = $f->make('Constructor',
        class  => 'ClassDecl',
        name   => $f->make('Constant', const_type => 'string', value => 'Test::ReaderEdge'),
        parent => undef,
        body   => [$method_node],
    );

    my $program = $f->make('Constructor',
        class      => 'Program',
        statements => [$class_decl],
    );

    # Two classes that share a :reader 'name' — these should NOT go into poly dispatch
    my $reader_target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::ReaderEdge',
        compiled_class_metadata => {
            'Test::ClassA' => {
                slug    => 'testclassa',
                readers => { name => 0 },
                methods => { is_zero => 1 },
            },
            'Test::ClassB' => {
                slug    => 'testclassb',
                readers => { name => 0 },
                methods => { is_zero => 1 },
            },
        },
    );

    my $reader_result = eval { $reader_target->generate_c_files($program, undef, undef) };
    ok(defined $reader_result, 'reader edge case: generate_c_files succeeds');

    my $pd = $reader_target->_polymorphic_dispatch();
    ok(!exists $pd->{name}, 'reader edge case: shared :reader "name" is NOT in polymorphic dispatch');
    ok(exists $pd->{is_zero}, 'reader edge case: is_zero (pure method) IS in polymorphic dispatch');
}

done_testing;
