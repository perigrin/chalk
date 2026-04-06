# ABOUTME: Tests Perl::Actions semantic actions for Tier B files.
# ABOUTME: Parses 5 files with fields and string interpolation, validates IR structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::FieldInfo;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
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
    is($node->operation(), 'Constructor', "$msg: is Constructor");
    is($node->class(), $expected_class, "$msg: class is $expected_class");
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
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Constant.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::IR::Node::Constant', 'Constant.pm class name');
        is_constant($cls->inputs()->[1],
            'Chalk::Bootstrap::IR::Node', 'Constant.pm parent class');

        my $body = $cls->inputs()->[2];
        is(ref $body, 'ARRAY', 'Constant.pm: class body is arrayref');
        # Expect 2 FieldDecl + 1 MethodDecl = 3 items
        is(scalar $body->@*, 3, 'Constant.pm: class body has 3 items');

        # First field: $const_type :param :reader
        my $f1 = $body->[0];
        is_field_info($f1, '$const_type', 'Constant.pm field 1');
        my $f1_attrs = defined $f1 ? $f1->attributes() : [];
        is(ref $f1_attrs, 'ARRAY', 'Constant.pm field 1 attributes');
        is(scalar $f1_attrs->@*, 2, 'Constant.pm field 1 has 2 attributes');

        # Second field: $value :param :reader
        my $f2 = $body->[1];
        is_field_info($f2, '$value', 'Constant.pm field 2');

        # Method: operation() returning 'Constant'
        my $meth = $body->[2];
        is_constructor($meth, 'MethodDecl', 'Constant.pm method');
        is_constant($meth->inputs()->[0], 'operation', 'Constant.pm method name');
        my $ret = $meth->inputs()->[2][0];
        is_constructor($ret, 'ReturnStmt', 'Constant.pm return');
        is_constant($ret->inputs()->[0], 'Constant', 'Constant.pm return value');
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
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Node.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Node.pm class name');
        is($cls->inputs()->[1], undef, 'Node.pm: no parent class');

        my $body = $cls->inputs()->[2];
        is(scalar $body->@*, 1, 'Node.pm: class body has 1 method');

        my $meth = $body->[0];
        is_constructor($meth, 'MethodDecl', 'Node.pm method');
        is_constant($meth->inputs()->[0], 'emit', 'Node.pm method name');

        my $meth_body = $meth->inputs()->[2];
        is(scalar $meth_body->@*, 1, 'Node.pm: method body has 1 statement');
        is_constructor($meth_body->[0], 'DieCall', 'Node.pm method dies');
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
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Statement.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::BNF::Target::XS::AST::Statement', 'Statement.pm class name');
        is_constant($cls->inputs()->[1],
            'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Statement.pm parent class');

        my $body = $cls->inputs()->[2];
        is(ref $body, 'ARRAY', 'Statement.pm: class body is arrayref');
        # 1 FieldDecl + 1 MethodDecl = 2 items
        is(scalar $body->@*, 2, 'Statement.pm: class body has 2 items');

        # Field: $code :param :reader
        my $f1 = $body->[0];
        is_field_info($f1, '$code', 'Statement.pm field');

        # Method: emit() returning interpolated string
        my $meth = $body->[1];
        is_constructor($meth, 'MethodDecl', 'Statement.pm method');
        is_constant($meth->inputs()->[0], 'emit', 'Statement.pm method name');

        my $meth_body = $meth->inputs()->[2];
        is(scalar $meth_body->@*, 1, 'Statement.pm: method body has 1 statement');
        my $ret = $meth_body->[0];
        is_constructor($ret, 'ReturnStmt', 'Statement.pm return');

        # Return value should be InterpolatedString
        my $interp = $ret->inputs()->[0];
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
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Module.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::BNF::Target::XS::AST::Module', 'Module.pm class name');
        is_constant($cls->inputs()->[1],
            'Chalk::Bootstrap::BNF::Target::XS::AST::Node', 'Module.pm parent class');

        my $body = $cls->inputs()->[2];
        is(ref $body, 'ARRAY', 'Module.pm: class body is arrayref');
        # 2 FieldDecl + 1 MethodDecl = 3 items
        is(scalar $body->@*, 3, 'Module.pm: class body has 3 items');

        # Fields
        my $f1 = $body->[0];
        is_field_info($f1, '$module', 'Module.pm field 1');
        my $f2 = $body->[1];
        is_field_info($f2, '$package', 'Module.pm field 2');

        # Method with InterpolatedString containing 2 variables
        my $meth = $body->[2];
        is_constructor($meth, 'MethodDecl', 'Module.pm method');
        my $ret = $meth->inputs()->[2][0];
        is_constructor($ret, 'ReturnStmt', 'Module.pm return');

        my $interp = $ret->inputs()->[0];
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
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];

        # The last meaningful statement should be the ClassDecl
        # (trailing 1; may appear as a bare Constant after the class)
        # So find the ClassDecl in the statements
        my $class_decl;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                $class_decl = $stmt;
            }
        }

        ok(defined $class_decl, 'Constructor.pm: found ClassDecl');

        SKIP: {
            skip 'Constructor.pm: no ClassDecl', 10 unless defined $class_decl;

            is_constant($class_decl->inputs()->[0],
                'Chalk::Bootstrap::IR::Node::Constructor', 'Constructor.pm class name');
            is_constant($class_decl->inputs()->[1],
                'Chalk::Bootstrap::IR::Node', 'Constructor.pm parent class');

            my $body = $class_decl->inputs()->[2];
            is(ref $body, 'ARRAY', 'Constructor.pm: class body is arrayref');
            # 1 FieldDecl + 1 MethodDecl = 2 items
            is(scalar $body->@*, 2, 'Constructor.pm: class body has 2 items');

            my $f1 = $body->[0];
            is_field_info($f1, '$class', 'Constructor.pm field');

            my $meth = $body->[1];
            is_constructor($meth, 'MethodDecl', 'Constructor.pm method');
            my $ret = $meth->inputs()->[2][0];
            is_constant($ret->inputs()->[0], 'Constructor', 'Constructor.pm return value');
        }
    }
}

done_testing();
