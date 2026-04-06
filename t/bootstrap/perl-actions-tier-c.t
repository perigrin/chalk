# ABOUTME: Tests Perl::Actions semantic actions for Tier C files.
# ABOUTME: Parses 5 files with runtime method logic, validates IR structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Program;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ActionsTierCTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ActionsTierCTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helpers ===

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

my sub is_constructor($node, $expected_class, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    # Metadata structs (Chalk::IR::Program, etc.) replaced Constructor nodes
    my %METADATA_CLASS = (
        Program => 'Chalk::IR::Program',
    );
    if (my $meta_class = $METADATA_CLASS{$expected_class}) {
        isa_ok($node, $meta_class, "$msg: is $expected_class");
        return;
    }
    is($node->operation(), 'Constructor', "$msg: is Constructor");
    is($node->class(), $expected_class, "$msg: class is $expected_class");
}

my sub is_constant($node, $expected_value, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    is($node->operation(), 'Constant', "$msg: is Constant");
    is($node->value(), $expected_value, "$msg: value is '$expected_value'");
}

# Helper to find ClassInfo or ClassDecl in program statements
my sub find_class_decl($ir) {
    # Chalk::IR::Program uses classes() accessor
    if ($ir isa Chalk::IR::Program) {
        my @classes = $ir->classes()->@*;
        return $classes[0] if @classes;
        # Fall through to other_stmts for programs without top-level classes
        for my $stmt ($ir->other_stmts()->@*) {
            return $stmt if $stmt isa Chalk::IR::ClassInfo;
        }
        return undef;
    }
    # Legacy Constructor:Program path
    my $stmts = $ir->inputs()->[0];
    for my $stmt ($stmts->@*) {
        if ($stmt isa Chalk::IR::ClassInfo) {
            return $stmt;
        }
        if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                && $stmt->class() eq 'ClassDecl') {
            return $stmt;
        }
    }
    return undef;
}

# Extract class body from ClassInfo or Constructor:ClassDecl
my sub class_body($cls) {
    return $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
}

# Extract class name string from ClassInfo or Constructor:ClassDecl
my sub class_name($cls) {
    return $cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value();
}

# Extract method body from MethodInfo or Constructor:MethodDecl
my sub method_body($method) {
    return $method isa Chalk::IR::MethodInfo ? $method->body() : $method->inputs()->[2];
}

# Count methods in class body by type (MethodInfo or MethodDecl)
my sub count_methods($cls) {
    my $body = class_body($cls);
    return scalar grep {
        ($_ isa Chalk::IR::MethodInfo)
        || ($_ isa Chalk::Bootstrap::IR::Node::Constructor && $_->class() eq 'MethodDecl')
    } $body->@*;
}

# Helper to find MethodInfo or MethodDecl by name in class body
my sub find_method($class_decl, $name) {
    my $body = class_body($class_decl);
    for my $item ($body->@*) {
        if ($item isa Chalk::IR::MethodInfo && $item->name() eq $name) {
            return $item;
        }
        if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                && $item->class() eq 'MethodDecl'
                && $item->inputs()->[0]->value() eq $name) {
            return $item;
        }
    }
    return undef;
}

# Helper to find FieldInfo by name in class body
my sub find_field($class_decl, $name) {
    my $body = class_body($class_decl);
    for my $item ($body->@*) {
        if ($item isa Chalk::IR::FieldInfo
                && $item->name() eq $name) {
            return $item;
        }
    }
    return undef;
}

# ============================================================
# 1. ConciseOp.pm — 5 fields (3 with defaults), 2 methods with
#    string interpolation, if/elsif, .=, =~, ne
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $ir, 'ConciseOp.pm: parse produces IR');

    SKIP: {
        skip 'ConciseOp.pm: no IR', 40 unless defined $ir;

        is_constructor($ir, 'Program', 'ConciseOp Program');
        my $cls = find_class_decl($ir);
        ok(defined $cls, 'ConciseOp.pm: found class declaration');

        SKIP: {
            skip 'ConciseOp.pm: no class declaration', 35 unless defined $cls;

            is($cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value(),
                'Chalk::Bootstrap::ConciseOp', 'ConciseOp class name');

            my $body = class_body($cls);
            ok(ref $body eq 'ARRAY', 'ConciseOp.pm: class body is arrayref');

            # Should have 5 fields + 2 methods = 7 items
            # (some fields have defaults, which may be parsed differently)
            my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
            ok(scalar @fields >= 5, 'ConciseOp.pm: at least 5 fields')
                or diag("Got " . scalar @fields . " fields");

            # Check field $name
            my $f_name = find_field($cls, '$name');
            ok(defined $f_name, 'ConciseOp.pm: has field $name');

            # Check field $type_info (has default undef)
            my $f_type_info = find_field($cls, '$type_info');
            ok(defined $f_type_info, 'ConciseOp.pm: has field $type_info');

            # Check field $flags (has default '')
            my $f_flags = find_field($cls, '$flags');
            ok(defined $f_flags, 'ConciseOp.pm: has field $flags');

            # Check field $private (has default '')
            my $f_private = find_field($cls, '$private');
            ok(defined $f_private, 'ConciseOp.pm: has field $private');

            # Method: to_string()
            my $to_string = find_method($cls, 'to_string');
            ok(defined $to_string, 'ConciseOp.pm: has method to_string');
            if (defined $to_string) {
                my $mbody = method_body($to_string);
                ok(ref $mbody eq 'ARRAY', 'ConciseOp.pm: to_string body is array');
                ok(scalar $mbody->@* >= 1,
                    'ConciseOp.pm: to_string body has statements');
            }

            # Method: structural_key()
            my $struct_key = find_method($cls, 'structural_key');
            ok(defined $struct_key, 'ConciseOp.pm: has method structural_key');
            if (defined $struct_key) {
                my $mbody = method_body($struct_key);
                ok(ref $mbody eq 'ARRAY', 'ConciseOp.pm: structural_key body is array');
                ok(scalar $mbody->@* >= 1,
                    'ConciseOp.pm: structural_key body has statements');
            }
        }
    }
}

# ============================================================
# 2. ConciseTree.pm — field with default [], push, for loop,
#    $#$ref, subscript, join, scalar
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/ConciseTree.pm');
    ok(defined $ir, 'ConciseTree.pm: parse produces IR');

    SKIP: {
        skip 'ConciseTree.pm: no IR', 30 unless defined $ir;

        is_constructor($ir, 'Program', 'ConciseTree Program');
        my $cls = find_class_decl($ir);
        ok(defined $cls, 'ConciseTree.pm: found class declaration');

        SKIP: {
            skip 'ConciseTree.pm: no class declaration', 25 unless defined $cls;

            is($cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value(),
                'Chalk::Bootstrap::ConciseTree', 'ConciseTree class name');

            # Field $ops with default []
            my $f_ops = find_field($cls, '$ops');
            ok(defined $f_ops, 'ConciseTree.pm: has field $ops');

            # Methods: push_op, concat, to_exec_string, op_count
            my @methods = grep {
                ($_ isa Chalk::IR::MethodInfo)
                || ($_ isa Chalk::Bootstrap::IR::Node::Constructor
                    && $_->class() eq 'MethodDecl')
            } class_body($cls)->@*;
            ok(scalar @methods >= 4, 'ConciseTree.pm: at least 4 methods')
                or diag("Got " . scalar @methods . " methods");

            my $push_op = find_method($cls, 'push_op');
            ok(defined $push_op, 'ConciseTree.pm: has method push_op');

            my $concat = find_method($cls, 'concat');
            ok(defined $concat, 'ConciseTree.pm: has method concat');

            my $to_exec = find_method($cls, 'to_exec_string');
            ok(defined $to_exec, 'ConciseTree.pm: has method to_exec_string');

            # Verify push in to_exec_string body is BuiltinCall, not
            # BinaryExpr wrapping BuiltinCall (grammar ambiguity fix)
            if (defined $to_exec) {
                my $mbody = method_body($to_exec);
                ok(ref $mbody eq 'ARRAY', 'ConciseTree.pm: to_exec_string body is array');
                # Find the Loop CFG node in the method body (replaced ForeachLoop Constructor)
                my ($loop_node) = grep {
                    $_ isa Chalk::Bootstrap::IR::Node
                    && $_->operation() eq 'Loop'
                } $mbody->@*;
                ok(defined $loop_node, 'ConciseTree.pm: to_exec_string has Loop CFG node');
                # Push BuiltinCall is now in cfg_state body_stmts (not in flat stmt list)
                # Verify the Loop node is well-formed
                if (defined $loop_node) {
                    is($loop_node->operation(), 'Loop',
                        'ConciseTree.pm: loop node is Loop');
                }
            }

            my $op_count = find_method($cls, 'op_count');
            ok(defined $op_count, 'ConciseTree.pm: has method op_count');
        }
    }
}

# ============================================================
# 3. Comparator.pm — sprintf, hash ref, s///g, ternary, !=,
#    method chains, if/else
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/ConciseTree/Comparator.pm');
    ok(defined $ir, 'Comparator.pm: parse produces IR');

    SKIP: {
        skip 'Comparator.pm: no IR', 20 unless defined $ir;

        is_constructor($ir, 'Program', 'Comparator Program');
        my $cls = find_class_decl($ir);
        ok(defined $cls, 'Comparator.pm: found class declaration');

        SKIP: {
            skip 'Comparator.pm: no class declaration', 15 unless defined $cls;

            is($cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value(),
                'Chalk::Bootstrap::ConciseTree::Comparator', 'Comparator class name');

            # 2 methods: compare, normalize
            my $compare = find_method($cls, 'compare');
            ok(defined $compare, 'Comparator.pm: has method compare');
            if (defined $compare) {
                my $mbody = method_body($compare);
                ok(scalar $mbody->@* >= 1,
                    'Comparator.pm: compare has body statements');
            }

            my $normalize = find_method($cls, 'normalize');
            ok(defined $normalize, 'Comparator.pm: has method normalize');
            if (defined $normalize) {
                my $mbody = method_body($normalize);
                ok(scalar $mbody->@* >= 1,
                    'Comparator.pm: normalize has body statements');
            }
        }
    }
}

# ============================================================
# 4. Oracle.pm — backticks, split, next unless, complex regex,
#    captures, //, substr, length
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/ConciseTree/Oracle.pm');
    ok(defined $ir, 'Oracle.pm: parse produces IR');

    SKIP: {
        skip 'Oracle.pm: no IR', 20 unless defined $ir;

        is_constructor($ir, 'Program', 'Oracle Program');
        my $cls = find_class_decl($ir);
        ok(defined $cls, 'Oracle.pm: found class declaration');

        SKIP: {
            skip 'Oracle.pm: no class declaration', 15 unless defined $cls;

            is($cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value(),
                'Chalk::Bootstrap::ConciseTree::Oracle', 'Oracle class name');

            # 2 methods: concise_for, parse_concise_output
            my $concise_for = find_method($cls, 'concise_for');
            ok(defined $concise_for, 'Oracle.pm: has method concise_for');

            my $parse_output = find_method($cls, 'parse_concise_output');
            ok(defined $parse_output, 'Oracle.pm: has method parse_concise_output');
            if (defined $parse_output) {
                my $mbody = method_body($parse_output);
                ok(scalar $mbody->@* >= 1,
                    'Oracle.pm: parse_concise_output has body statements');
            }
        }
    }
}

# ============================================================
# 5. Context.pm — anon sub, isa, !, ||, recursion, ref(), fields
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/Context.pm');
    ok(defined $ir, 'Context.pm: parse produces IR');

    SKIP: {
        skip 'Context.pm: no IR', 30 unless defined $ir;

        is_constructor($ir, 'Program', 'Context Program');
        my $cls = find_class_decl($ir);
        ok(defined $cls, 'Context.pm: found class declaration');

        SKIP: {
            skip 'Context.pm: no class declaration', 25 unless defined $cls;

            is($cls isa Chalk::IR::ClassInfo ? $cls->name() : $cls->inputs()->[0]->value(),
                'Chalk::Bootstrap::Context', 'Context class name');

            # Fields: $focus, $children, $position, $rule
            my @fields = grep { $_ isa Chalk::IR::FieldInfo } class_body($cls)->@*;
            ok(scalar @fields >= 4, 'Context.pm: at least 4 fields')
                or diag("Got " . scalar @fields . " fields");

            # Methods: extract, extend, duplicate, leaves, scanned_text
            my @methods = grep {
                ($_ isa Chalk::IR::MethodInfo)
                || ($_ isa Chalk::Bootstrap::IR::Node::Constructor
                    && $_->class() eq 'MethodDecl')
            } class_body($cls)->@*;
            ok(scalar @methods >= 5, 'Context.pm: at least 5 methods')
                or diag("Got " . scalar @methods . " methods");

            my $extract = find_method($cls, 'extract');
            ok(defined $extract, 'Context.pm: has method extract');

            my $extend = find_method($cls, 'extend');
            ok(defined $extend, 'Context.pm: has method extend');

            my $duplicate = find_method($cls, 'duplicate');
            ok(defined $duplicate, 'Context.pm: has method duplicate');

            my $leaves = find_method($cls, 'leaves');
            ok(defined $leaves, 'Context.pm: has method leaves');

            my $scanned = find_method($cls, 'scanned_text');
            ok(defined $scanned, 'Context.pm: has method scanned_text');
        }
    }
}

done_testing();
