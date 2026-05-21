# ABOUTME: Tests Perl::Actions semantic actions for Tier C files.
# ABOUTME: Parses 5 files with runtime method logic, validates IR structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Program;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
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
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result;
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
        if ($stmt isa Chalk::IR::Node::Constructor
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
        || ($_ isa Chalk::IR::Node::Constructor && $_->class() eq 'MethodDecl')
    } $body->@*;
}

# Helper to find MethodInfo or MethodDecl by name in class body
my sub find_method($class_decl, $name) {
    my $body = class_body($class_decl);
    for my $item ($body->@*) {
        if ($item isa Chalk::IR::MethodInfo && $item->name() eq $name) {
            return $item;
        }
        if ($item isa Chalk::IR::Node::Constructor
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
                || ($_ isa Chalk::IR::Node::Constructor
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
