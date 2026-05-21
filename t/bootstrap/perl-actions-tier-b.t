# ABOUTME: Tests Perl::Actions semantic actions for Tier B files.
# ABOUTME: Parses 5 files with fields and string interpolation, validates IR structure.
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
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Program;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ActionsTierBTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ActionsTierBTest::grammar();
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
    if ($node isa Chalk::IR::Program) {
        is($expected_class, 'Program', "$msg: is Program typed node");
        return;
    }
    # Shimmed typed nodes have operation() == class name; legacy Constructor nodes have operation() == 'Constructor'
    ok($node->operation() eq 'Constructor' || $node->class() eq $expected_class,
        "$msg: is Constructor");
    is($node->class(), $expected_class, "$msg: class is $expected_class");
}

# Get flattened statement list from Program (handles both typed and Constructor nodes)
my sub program_stmts($ir) {
    if ($ir isa Chalk::IR::Program) {
        return [ $ir->use_decls()->@*, $ir->classes()->@*, $ir->top_level_subs()->@*, $ir->other_stmts()->@* ];
    }
    return $ir->inputs()->[0];
}

# === Helpers for ClassInfo/ClassDecl dual-path ===

my sub class_body($cls) {
    return $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
}

my sub class_name_str($cls) {
    return $cls isa Chalk::IR::ClassInfo
        ? $cls->name()
        : $cls->inputs()->[0]->value();
}

my sub class_parent_str($cls) {
    return $cls isa Chalk::IR::ClassInfo
        ? $cls->parent()
        : (defined $cls->inputs()->[1] ? $cls->inputs()->[1]->value() : undef);
}

my sub method_body($meth) {
    return $meth isa Chalk::IR::MethodInfo ? $meth->body() : $meth->inputs()->[2];
}

my sub method_name_str($meth) {
    return $meth isa Chalk::IR::MethodInfo
        ? $meth->name()
        : $meth->inputs()->[0]->value();
}

my sub find_class_decl_in_stmts($stmts) {
    for my $stmt ($stmts->@*) {
        return $stmt if $stmt isa Chalk::IR::ClassInfo;
        return $stmt if $stmt isa Chalk::IR::Node::Constructor
            && $stmt->class() eq 'ClassDecl';
    }
    return undef;
}

my sub find_method_in_body($body, $name) {
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

my sub is_field_info($node, $expected_name, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    isa_ok($node, 'Chalk::IR::FieldInfo', $msg);
    return unless $node isa Chalk::IR::FieldInfo;
    is($node->name(), $expected_name, "$msg: name is '$expected_name'");
}

my sub is_constant($node, $expected_value, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    is($node->operation(), 'Constant', "$msg: is Constant");
    is($node->value(), $expected_value, "$msg: value is '$expected_value'");
}

# ============================================================
# 1. Constant.pm — :isa, 2 fields, method
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 30 unless defined $ir;

        is_constructor($ir, 'Program', 'Constant.pm Program');
        my $stmts = program_stmts($ir);
        my $cls = find_class_decl_in_stmts($stmts);
        ok(defined $cls, 'Constant.pm: found class declaration');
        is(class_name_str($cls), 'Chalk::Bootstrap::IR::Node::Constant', 'Constant.pm class name');
        is(class_parent_str($cls), 'Chalk::Bootstrap::IR::Node', 'Constant.pm parent class');

        my $body = class_body($cls);
        is(ref $body, 'ARRAY', 'Constant.pm: class body is arrayref');
        # 2 FieldInfo + 1 MethodInfo items at minimum
        ok(scalar $body->@* >= 3, 'Constant.pm: class body has at least 3 items');

        # Check for fields by name
        my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
        my ($f1) = grep { $_->name() eq '$const_type' } @fields;
        is_field_info($f1, '$const_type', 'Constant.pm field 1');
        my $f1_attrs = defined $f1 ? $f1->attributes() : [];
        is(ref $f1_attrs, 'ARRAY', 'Constant.pm field 1 attributes');
        is(scalar $f1_attrs->@*, 2, 'Constant.pm field 1 has 2 attributes');

        my ($f2) = grep { $_->name() eq '$value' } @fields;
        is_field_info($f2, '$value', 'Constant.pm field 2');

        # Method: operation() returning 'Constant'
        my $meth = find_method_in_body($body, 'operation');
        ok(defined $meth, 'Constant.pm: has operation method');
        if (defined $meth) {
            my $meth_body = method_body($meth);
            my $ret = $meth_body->[0];
            ok($ret isa Chalk::IR::Node::Return, 'Constant.pm return: is Return CFG node');
            is_constant($ret->inputs()->[1], 'Constant', 'Constant.pm return value');
        }
    }
}

# ============================================================
# 2. XS::AST::Node.pm — no parent, no fields, method with die
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Node.pm');
    ok(defined $ir, 'XS::AST::Node.pm: parse produces IR');

    SKIP: {
        skip 'XS::AST::Node.pm: no IR', 12 unless defined $ir;

        is_constructor($ir, 'Program', 'Node.pm Program');
        my $stmts = program_stmts($ir);
        my $cls = find_class_decl_in_stmts($stmts);
        ok(defined $cls, 'Node.pm: found class declaration');
        is(class_name_str($cls), 'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Node.pm class name');
        is(class_parent_str($cls), undef, 'Node.pm: no parent class');

        my $body = class_body($cls);
        my $meth = find_method_in_body($body, 'emit');
        ok(defined $meth, 'Node.pm: has emit method');
        is(method_name_str($meth), 'emit', 'Node.pm method name');

        if (defined $meth) {
            my $meth_body = method_body($meth);
            is(scalar $meth_body->@*, 1, 'Node.pm: method body has 1 statement');
            isa_ok($meth_body->[0], 'Chalk::IR::Node::Unwind', 'Node.pm method dies (Unwind CFG node)');
        }
    }
}

# ============================================================
# 3. XS::AST::Statement.pm — :isa, 1 field, method with interpolation
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Statement.pm');
    ok(defined $ir, 'Statement.pm: parse produces IR');

    SKIP: {
        skip 'Statement.pm: no IR', 41 unless defined $ir;

        is_constructor($ir, 'Program', 'Statement.pm Program');
        my $stmts = program_stmts($ir);
        my $cls = find_class_decl_in_stmts($stmts);
        ok(defined $cls, 'Statement.pm: found class declaration');
        is(class_name_str($cls), 'Chalk::Bootstrap::BNF::Target::XS::AST::Statement', 'Statement.pm class name');
        is(class_parent_str($cls), 'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Statement.pm parent class');

        my $body = class_body($cls);
        is(ref $body, 'ARRAY', 'Statement.pm: class body is arrayref');

        # Field: $code :param :reader
        my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
        my ($f1) = grep { $_->name() eq '$code' } @fields;
        is_field_info($f1, '$code', 'Statement.pm field');

        # Method: emit() returning interpolated string
        my $meth = find_method_in_body($body, 'emit');
        ok(defined $meth, 'Statement.pm: has emit method');
        is(method_name_str($meth), 'emit', 'Statement.pm method name');

        my $meth_body = defined $meth ? method_body($meth) : [];
        is(scalar $meth_body->@*, 1, 'Statement.pm: method body has 1 statement');
        my $ret = $meth_body->[0];
        ok($ret isa Chalk::IR::Node::Return, 'Statement.pm return: is Return CFG node');

        # Return value should be InterpolatedString
        my $interp = $ret->inputs()->[1];
        is_constructor($interp, 'InterpolatedString', 'Statement.pm interpolated string');
        my $parts = $interp->inputs()->[0];
        is(ref $parts, 'ARRAY', 'Statement.pm: parts is arrayref');
        is(scalar $parts->@*, 3, 'Statement.pm: exactly 3 parts');

        # Verify part types and values (validates escape handling)
        is($parts->[0]->const_type(), 'string', 'Statement.pm: part 0 is string literal');
        is($parts->[0]->value(), '    ', 'Statement.pm: part 0 is 4 spaces');
        is($parts->[1]->const_type(), 'variable', 'Statement.pm: part 1 is variable');
        is($parts->[1]->value(), '$code', 'Statement.pm: part 1 is $code');
        is($parts->[2]->const_type(), 'string', 'Statement.pm: part 2 is string literal');
        is($parts->[2]->value(), "\n", 'Statement.pm: part 2 is actual newline (not \\n)');
    }
}

# ============================================================
# 4. XS::AST::Module.pm — :isa, 2 fields, method with 2-var interpolation
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Module.pm');
    ok(defined $ir, 'Module.pm: parse produces IR');

    SKIP: {
        skip 'Module.pm: no IR', 46 unless defined $ir;

        is_constructor($ir, 'Program', 'Module.pm Program');
        my $stmts = program_stmts($ir);
        my $cls = find_class_decl_in_stmts($stmts);
        ok(defined $cls, 'Module.pm: found class declaration');
        is(class_name_str($cls), 'Chalk::Bootstrap::BNF::Target::XS::AST::Module', 'Module.pm class name');
        is(class_parent_str($cls), 'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Module.pm parent class');

        my $body = class_body($cls);
        is(ref $body, 'ARRAY', 'Module.pm: class body is arrayref');
        ok(scalar $body->@* >= 3, 'Module.pm: class body has at least 3 items');

        # Fields
        my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
        my ($f1) = grep { $_->name() eq '$module' } @fields;
        is_field_info($f1, '$module', 'Module.pm field 1');
        my ($f2) = grep { $_->name() eq '$package' } @fields;
        is_field_info($f2, '$package', 'Module.pm field 2');

        # Method with InterpolatedString containing 2 variables
        my $meth = find_method_in_body($body, 'emit');
        ok(defined $meth, 'Module.pm: has emit method');
        my $meth_body = defined $meth ? method_body($meth) : [];
        my $ret = $meth_body->[0];
        ok($ret isa Chalk::IR::Node::Return, 'Module.pm return: is Return CFG node');

        my $interp = $ret->inputs()->[1];
        is_constructor($interp, 'InterpolatedString', 'Module.pm interpolated string');
        my $parts = $interp->inputs()->[0];
        is(scalar $parts->@*, 5, 'Module.pm: exactly 5 parts (2 vars + 3 literals)');

        # Verify part types and values (validates multi-var interpolation)
        is($parts->[0]->const_type(), 'string', 'Module.pm: part 0 is string');
        is($parts->[0]->value(), 'MODULE = ', 'Module.pm: part 0 value');
        is($parts->[1]->const_type(), 'variable', 'Module.pm: part 1 is variable');
        is($parts->[1]->value(), '$module', 'Module.pm: part 1 is $module');
        is($parts->[2]->const_type(), 'string', 'Module.pm: part 2 is string');
        is($parts->[2]->value(), '  PACKAGE = ', 'Module.pm: part 2 value');
        is($parts->[3]->const_type(), 'variable', 'Module.pm: part 3 is variable');
        is($parts->[3]->value(), '$package', 'Module.pm: part 3 is $package');
        is($parts->[4]->const_type(), 'string', 'Module.pm: part 4 is string');
        is($parts->[4]->value(), "\n\n", 'Module.pm: part 4 is double newline');
    }
}

# ============================================================
# 5. Constructor.pm — :isa, 1 field, method, trailing 1;
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Constructor.pm');
    ok(defined $ir, 'Constructor.pm: parse produces IR');

    SKIP: {
        skip 'Constructor.pm: no IR', 15 unless defined $ir;

        is_constructor($ir, 'Program', 'Constructor.pm Program');
        my $stmts = program_stmts($ir);

        # Find the class declaration (ClassInfo or ClassDecl) in the statements
        my $class_decl = find_class_decl_in_stmts($stmts);

        ok(defined $class_decl, 'Constructor.pm: found class declaration');

        SKIP: {
            skip 'Constructor.pm: no class declaration', 10 unless defined $class_decl;

            is(class_name_str($class_decl),
                'Chalk::Bootstrap::IR::Node::Constructor', 'Constructor.pm class name');
            is(class_parent_str($class_decl),
                'Chalk::Bootstrap::IR::Node', 'Constructor.pm parent class');

            my $body = class_body($class_decl);
            is(ref $body, 'ARRAY', 'Constructor.pm: class body is arrayref');
            ok(scalar $body->@* >= 2, 'Constructor.pm: class body has at least 2 items');

            my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
            my ($f1) = grep { $_->name() eq '$class' } @fields;
            is_field_info($f1, '$class', 'Constructor.pm field');

            my $meth = find_method_in_body($body, 'operation');
            ok(defined $meth, 'Constructor.pm: has operation method');
            if (defined $meth) {
                my $meth_body = method_body($meth);
                my $ret = $meth_body->[0];
                is_constant($ret->inputs()->[1], 'Constructor', 'Constructor.pm return value');
            }
        }
    }
}

done_testing();
