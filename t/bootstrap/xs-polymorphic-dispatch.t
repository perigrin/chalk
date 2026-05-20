# ABOUTME: Unit tests for the polymorphic dispatch map in Target::C.
# ABOUTME: Verifies that compiled_class_metadata is used to build $_polymorphic_dispatch.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;
use Chalk::IR::Node::Return;

# Build a minimal IR: a class with a single no-op method so _generate_c_files
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
        $factory->make_cfg('Return',
            inputs => [
                $factory->make('Start'),
                $factory->make('Constant', const_type => 'string', value => '1'),
            ],
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

my $result = eval { $target->_generate_c_files($program, undef, undef) };
ok(defined $result, '_generate_c_files succeeds with compiled_class_metadata') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# --- Verify _polymorphic_dispatch ---

my $poly = $target->_polymorphic_dispatch();
ok(defined $poly, '_polymorphic_dispatch is defined after _generate_c_files');
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

my $c_result = eval { $target->_generate_c_files($program, undef, undef) };
ok(defined $c_result, '_generate_c_files returns a result for Component 3 checks') or do {
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
        $factory2->make_cfg('Return',
            inputs => [ $factory2->make('Start'), $call_node ],
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

my $result2 = eval { $target2->_generate_c_files($program2, undef, undef) };
ok(defined $result2, '_generate_c_files succeeds for Component 2 stash-compare test') or do {
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
            $f->make_cfg('Return',
                inputs => [ $f->make('Start'), $f->make('Constant', const_type => 'string', value => '1') ],
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

    my $reader_result = eval { $reader_target->_generate_c_files($program, undef, undef) };
    ok(defined $reader_result, 'reader edge case: _generate_c_files succeeds');

    my $pd = $reader_target->_polymorphic_dispatch();
    ok(!exists $pd->{name}, 'reader edge case: shared :reader "name" is NOT in polymorphic dispatch');
    ok(exists $pd->{is_zero}, 'reader edge case: is_zero (pure method) IS in polymorphic dispatch');
}

# ============================================================
# Component 4: Behavioral verification on real FilterComposite.pm
#
# Parse lib/Chalk/Bootstrap/Semiring/FilterComposite.pm through
# the full grammar pipeline, generate C with compiled_class_metadata
# for the real 5 semiring classes, and verify the generated C
# contains stash-compare dispatch chains for is_zero, add, multiply.
#
# We do NOT compile/load the generated module — that would require
# all 5 semiring .so files to be present.  We only inspect the
# generated C text.
# ============================================================

subtest 'Component 4: real FilterComposite.pm pipeline' => sub {
    use lib 't/bootstrap/lib';
    use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

    # ---- grammar setup ----
    my $gen_grammar = eval { setup_xs_grammar('TestXSGrammar::C4') };
    if ($@ || !defined $gen_grammar) {
        BAIL_OUT("Component 4: grammar pipeline setup failed: $@");
    }
    pass('Component 4: grammar pipeline setup succeeded');

    # ---- parse FilterComposite.pm to IR ----
    my $fc_file = 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm';
    my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, $fc_file);
    if (!defined $ir) {
        BAIL_OUT("Component 4: parse of FilterComposite.pm failed — IR is undef");
    }
    pass('Component 4: FilterComposite.pm parsed to IR');

    # ---- set up compiled_class_metadata for the real 5 semiring classes ----
    my $real_metadata = {
        'Chalk::Bootstrap::Semiring::Boolean' => {
            slug    => 'boolean',
            readers => {},
            methods => {
                is_zero    => 1,
                add        => 1,
                multiply   => 1,
                zero       => 1,
                one        => 1,
                on_scan    => 1,
                on_complete => 1,
                should_scan => 1,
            },
        },
        'Chalk::Bootstrap::Semiring::Precedence' => {
            slug    => 'precedence',
            readers => {},
            methods => {
                is_zero    => 1,
                add        => 1,
                multiply   => 1,
                zero       => 1,
                one        => 1,
                on_scan    => 1,
                on_complete => 1,
                should_scan => 1,
            },
        },
        'Chalk::Bootstrap::Semiring::TypeInference' => {
            slug    => 'typeinference',
            readers => {},
            methods => {
                is_zero    => 1,
                add        => 1,
                multiply   => 1,
                zero       => 1,
                one        => 1,
                on_scan    => 1,
                on_complete => 1,
                should_scan => 1,
            },
        },
        'Chalk::Bootstrap::Semiring::Structural' => {
            slug    => 'structural',
            readers => {},
            methods => {
                is_zero    => 1,
                add        => 1,
                multiply   => 1,
                zero       => 1,
                one        => 1,
                on_scan    => 1,
                on_complete => 1,
                should_scan => 1,
            },
        },
        'Chalk::Bootstrap::Semiring::SemanticAction' => {
            slug    => 'semanticaction',
            readers => {},
            methods => {
                is_zero    => 1,
                add        => 1,
                multiply   => 1,
                zero       => 1,
                one        => 1,
                on_scan    => 1,
                on_complete => 1,
                should_scan => 1,
            },
        },
    };

    my $fc_target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name             => 'Chalk::Bootstrap::Semiring::FilterComposite',
        compiled_class_metadata => $real_metadata,
    );

    # ---- generate C files ----
    my $fc_result = eval {
        $fc_target->_reset_cfg_lookup();
        $fc_target->_build_cfg_lookup($sa, $sem_ctx);
        $fc_target->_generate_c_files($ir, $sa, $sem_ctx);
    };
    if ($@ || !defined $fc_result) {
        BAIL_OUT("Component 4: _generate_c_files for FilterComposite failed: $@");
    }
    pass('Component 4: _generate_c_files succeeded for FilterComposite');

    # ---- locate the generated .c file ----
    my ($c_key) = grep { /\.c$/ } sort keys $fc_result->{files}->%*;
    ok(defined $c_key, 'Component 4: generated .c file key exists in result')
        or do { diag 'Keys: ' . join(', ', sort keys $fc_result->{files}->%*); done_testing(); return; };

    my $c_text = $fc_result->{files}{$c_key};
    ok(defined $c_text && length($c_text) > 0, 'Component 4: generated .c file has content');

    # ---- stash-compare dispatch chain present ----
    like($c_text, qr/SvSTASH\s*\(\s*SvRV\s*\(/,
        'Component 4: generated C contains stash-compare SvSTASH(SvRV(');

    # ---- direct calls for the 5 real semiring slugs on each shared method ----
    for my $method (qw(is_zero add multiply)) {
        for my $slug (qw(boolean precedence typeinference structural semanticaction)) {
            like($c_text, qr/\b${slug}_${method}\b/,
                "Component 4: generated C contains direct call ${slug}_${method}");
        }
    }

    # ---- call_method fallback still present ----
    like($c_text, qr/call_method/,
        'Component 4: generated C retains call_method fallback');

    # ---- stash pointer statics for all 5 semirings ----
    for my $slug (qw(boolean precedence typeinference structural semanticaction)) {
        like($c_text, qr/static HV \*_${slug}_stash = NULL;/,
            "Component 4: generated C has static stash declaration for '$slug'");
    }

    # ---- gv_stashpvn in init_statics for all 5 semirings ----
    my %real_class_names = (
        boolean       => 'Chalk::Bootstrap::Semiring::Boolean',
        precedence    => 'Chalk::Bootstrap::Semiring::Precedence',
        typeinference => 'Chalk::Bootstrap::Semiring::TypeInference',
        structural    => 'Chalk::Bootstrap::Semiring::Structural',
        semanticaction => 'Chalk::Bootstrap::Semiring::SemanticAction',
    );
    for my $slug (sort keys %real_class_names) {
        my $class_name = $real_class_names{$slug};
        my $len        = length($class_name);
        like($c_text,
            qr/\Q_${slug}_stash = gv_stashpvn("${class_name}", ${len}, GV_ADD);\E/,
            "Component 4: init_statics populates _${slug}_stash via gv_stashpvn");
    }

    # ---- cross-class #include directives ----
    for my $slug (qw(boolean precedence typeinference structural semanticaction)) {
        like($c_text, qr/#include "${slug}\.h"/,
            "Component 4: generated C includes header for '$slug'");
    }

    # ---- count call_method vs direct-dispatch — report but don't gate on ratio ----
    my $call_method_count = () = $c_text =~ /call_method/g;
    my $direct_call_count = () = $c_text =~ /\b(?:boolean|precedence|typeinference|structural|semanticaction)_(?:is_zero|add|multiply|zero|one|on_scan|on_complete|should_scan)\b/g;
    diag sprintf(
        'Component 4 dispatch stats: %d direct calls replaced, %d call_method calls remain',
        $direct_call_count, $call_method_count,
    );

    done_testing();
};

done_testing;
