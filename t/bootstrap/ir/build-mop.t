# ABOUTME: Tests build_graph_from_ir's MOP::Class/Field/Method/Adjust vocabulary: lines
# ABOUTME: declare onto a per-build Chalk::MOP, sealed and returned in list context.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;
use Scalar::Util qw(blessed);

# 019eb42a MOP-direct corpus vocabulary: class structure in ir blocks is
# declared via the real MOP declare_* API (the same accumulation the parser
# performs); the per-build MOP is sealed and rides to the backend via
# lower(mop => ...). Call lines name their class via class: "Name".

subtest 'MOP::Class + MOP::Method declare onto the per-build MOP' => sub {
    my $ir = <<'END_IR';
%cls    = MOP::Class(name: "Greeter")
%body   = Constant(42) :Int
%mi     = MOP::Method(class: %cls, name: "greet", body: %body, return_repr: "Int")
return %body
L: GREEN
END_IR

    my ($ret, $mop);
    eval { ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir) };
    is($@, '', 'build_graph_from_ir did not die');
    ok(defined $ret, 'return node is defined');
    ok(defined $mop, 'list context returns the per-build MOP');
    ok($mop->is_sealed, 'the MOP is sealed before return');

    my $cls = $mop->for_class('Greeter');
    ok(defined $cls, 'the class is registered');
    my ($m) = $cls->methods;
    is($m->name, 'greet', 'method declared with its name');
    is($m->return_type, 'Int', 'return_repr lands as return_type');
    ok(scalar(@{ $m->graph->returns }), 'the method graph carries a Return (the lowering root)');
};

subtest 'MOP::Field declares in order; explicit fieldix is asserted' => sub {
    my $ir = <<'END_IR';
%cls    = MOP::Class(name: "Pt")
%mf_x   = MOP::Field(class: %cls, name: "x", fieldix: 0, param: true, reader: true, has_default: false, type: "Int")
%mf_y   = MOP::Field(class: %cls, name: "y", fieldix: 1, param: false, reader: false, has_default: false, type: "Int")
%body   = Constant(1) :Int
return %body
L: GREEN
END_IR

    my ($ret, $mop);
    eval { ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir) };
    is($@, '', 'fields build without error');
    my @fields = $mop->for_class('Pt')->fields;
    is(scalar @fields, 2, 'two fields declared');
    is($fields[0]->name, 'x', 'first field is x');
    is($fields[0]->fieldix, 0, 'fieldix derived from order');
    ok($fields[0]->is_param,   'param: true becomes :param');
    ok($fields[0]->has_reader, 'reader: true becomes :reader');
    ok(!$fields[1]->is_param,  'param: false stays plain');

    # A fieldix that contradicts declaration order dies (silent slot drift guard).
    my $bad = <<'END_IR';
%cls    = MOP::Class(name: "Pt")
%mf_x   = MOP::Field(class: %cls, name: "x", fieldix: 3, param: false, reader: false, has_default: false, type: "Int")
%body   = Constant(1) :Int
return %body
L: GREEN
END_IR
    my $err;
    eval { Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($bad); 1 } or $err = $@;
    like($err, qr/fieldix/, 'contradictory fieldix dies');
};

subtest 'MOP::Adjust threads body statements in list order' => sub {
    my $ir = <<'END_IR';
%cls    = MOP::Class(name: "Box")
%mf_v   = MOP::Field(class: %cls, name: "v", fieldix: 0, param: true, reader: false, has_default: false, type: "Int")
%fa_lv  = FieldAccess(field_index: 0, field_stash: "Box") :Int
%nine   = Constant(9) :Int
%st_a   = Assign(%fa_lv, %nine) :Int
%st_b   = Assign(%fa_lv, %nine) :Int
%adj    = MOP::Adjust(class: %cls, body: [%st_a, %st_b])
%body   = Constant(1) :Int
return %body
L: GREEN
END_IR

    my ($ret, $mop);
    eval { ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir) };
    is($@, '', 'adjust builds without error');
    my ($adj) = $mop->for_class('Box')->adjust_blocks;
    ok(defined $adj, 'the phaser is declared');
    my @members = grep { blessed($_) && $_->can('operation') && $_->operation eq 'Assign' }
        $adj->graph->nodes->@*;
    is(scalar @members, 2, 'both statements are graph members');
    my ($second) = grep { defined $_->control_in } @members;
    ok(defined $second, 'the second statement is control-threaded after the first');
};

subtest 'MOP::Class parent kwarg becomes parent_name' => sub {
    my $ir = <<'END_IR';
%base   = MOP::Class(name: "Base")
%kid    = MOP::Class(name: "Kid", parent: "Base")
%body   = Constant(1) :Int
return %body
L: GREEN
END_IR

    my ($ret, $mop);
    eval { ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir) };
    is($@, '', 'parented classes build');
    is($mop->for_class('Kid')->parent_name, 'Base', 'parent kwarg lands as parent_name');
};

subtest 'a block with no MOP lines returns undef mop; scalar context unchanged' => sub {
    my $ir = <<'END_IR';
%body   = Constant(7) :Int
return %body
L: GREEN
END_IR

    my ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir);
    ok(defined $ret, 'return node defined');
    is($mop, undef, 'no class structure -> no MOP');

    my $scalar_ret = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir);
    ok(defined $scalar_ret, 'scalar-context callers still get the return node');
};

subtest 'Call class kwarg becomes the class_name node attribute' => sub {
    my $ir = <<'END_IR';
%cls    = MOP::Class(name: "Greeter")
%body   = Constant(42) :Int
%mi     = MOP::Method(class: %cls, name: "greet", body: %body, return_repr: "Int")
%new_g  = Call(dispatch_kind: "method", name: "new", class: "Greeter") :Object
%result = Call(%new_g, dispatch_kind: "method", name: "greet", class: "Greeter") :Int
return %result
L: GREEN
END_IR

    my ($ret, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir);
    my $call = $ret->inputs->[-1];
    is($call->operation, 'Call', 'return value is the Call');
    is($call->class_name, 'Greeter', 'class: kwarg landed as class_name');
    is(scalar(grep { blessed($_) } $call->inputs->@*), 1,
        'only the invocant rides as an input (no metadata object)');
};

done_testing;
