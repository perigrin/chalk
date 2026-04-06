# ABOUTME: Tests for Chalk::IR metadata structs (Program, ClassInfo, etc.).
# ABOUTME: Verifies plain data containers for program structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Program;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::FieldInfo;

my $fi = Chalk::IR::FieldInfo->new(name => '$type', attributes => [{name => 'param'}, {name => 'reader'}]);
is($fi->name(), '$type', 'FieldInfo name');
is(scalar $fi->attributes()->@*, 2, 'FieldInfo has 2 attributes');
is($fi->default_value(), undef, 'FieldInfo default_value is undef');

my $fi2 = Chalk::IR::FieldInfo->new(name => '$count', default_value => '0');
is($fi2->default_value(), '0', 'FieldInfo default_value');
is_deeply($fi2->attributes(), [], 'FieldInfo attributes default empty');

# id() — content-based, used for NodeFactory hash-cons keys
my $id1 = $fi->id();
ok(defined $id1, 'FieldInfo id() returns a value');
like($id1, qr/FieldInfo/, 'FieldInfo id() contains FieldInfo marker');
like($id1, qr/\$type/, 'FieldInfo id() contains field name');

my $fi_same = Chalk::IR::FieldInfo->new(name => '$type', attributes => [{name => 'param'}, {name => 'reader'}]);
is($fi->id(), $fi_same->id(), 'FieldInfo id() is content-based (same content => same id)');
isnt($fi->id(), $fi2->id(), 'FieldInfo id() differs for different names');

# add_consumer() — no-op, does not participate in use-def chain
ok(eval { $fi->add_consumer('dummy'); 1 }, 'FieldInfo add_consumer() does not die');

my $mi = Chalk::IR::MethodInfo->new(name => 'foo', params => ['$self', '$x'], graph => undef);
is($mi->name(), 'foo', 'MethodInfo name');
is(scalar $mi->params()->@*, 2, 'MethodInfo params');
is($mi->graph(), undef, 'MethodInfo graph');
is($mi->return_type(), undef, 'MethodInfo return_type default');

# body field — stores raw statement array
my $mi_with_body = Chalk::IR::MethodInfo->new(
    name   => 'bar',
    params => ['$self'],
    body   => ['stmt1', 'stmt2'],
);
is(scalar $mi_with_body->body()->@*, 2, 'MethodInfo body stores statement array');
is($mi_with_body->body()->[0], 'stmt1', 'MethodInfo body element 0 correct');

my $mi_no_body = Chalk::IR::MethodInfo->new(name => 'baz', params => []);
is_deeply($mi_no_body->body(), [], 'MethodInfo body defaults to empty arrayref');

# id() — content-based ID for hash-cons compatibility
my $id = $mi->id();
ok(defined $id, 'MethodInfo id() returns a value');
like($id, qr/MethodInfo/, 'MethodInfo id() contains MethodInfo marker');
like($id, qr/foo/, 'MethodInfo id() contains method name');

my $mi_same = Chalk::IR::MethodInfo->new(name => 'foo', params => ['$self', '$x'], graph => undef);
is($mi->id(), $mi_same->id(), 'MethodInfo id() is content-based (same content => same id)');

my $mi_diff = Chalk::IR::MethodInfo->new(name => 'other', params => ['$self'], graph => undef);
isnt($mi->id(), $mi_diff->id(), 'MethodInfo id() differs for different names');

# add_consumer() — no-op, does not participate in use-def chain
ok(eval { $mi->add_consumer('dummy'); 1 }, 'MethodInfo add_consumer() does not die');

my $si = Chalk::IR::SubInfo->new(name => '_helper', params => ['$a'], scope => 'my');
is($si->name(), '_helper', 'SubInfo name');
is($si->scope(), 'my', 'SubInfo scope');

my $si2 = Chalk::IR::SubInfo->new(name => 'pkg_sub', params => []);
is($si2->scope(), 'package', 'SubInfo default scope is package');

# body field — stores raw statement array
my $si_with_body = Chalk::IR::SubInfo->new(
    name   => 'do_thing',
    params => ['$x'],
    scope  => 'package',
    body   => ['stmt1', 'stmt2'],
);
is(scalar $si_with_body->body()->@*, 2, 'SubInfo body stores statement array');
is($si_with_body->body()->[0], 'stmt1', 'SubInfo body element 0 correct');

my $si_no_body = Chalk::IR::SubInfo->new(name => 'bare_sub', params => []);
is_deeply($si_no_body->body(), [], 'SubInfo body defaults to empty arrayref');

# id() — content-based ID for hash-cons compatibility
my $si_id = $si->id();
ok(defined $si_id, 'SubInfo id() returns a value');
like($si_id, qr/SubInfo/, 'SubInfo id() contains SubInfo marker');
like($si_id, qr/_helper/, 'SubInfo id() contains sub name');
like($si_id, qr/my/, 'SubInfo id() contains scope');

my $si_same = Chalk::IR::SubInfo->new(name => '_helper', params => ['$a'], scope => 'my');
is($si->id(), $si_same->id(), 'SubInfo id() is content-based (same content => same id)');

my $si_diff = Chalk::IR::SubInfo->new(name => 'other_sub', params => ['$a'], scope => 'my');
isnt($si->id(), $si_diff->id(), 'SubInfo id() differs for different names');

# add_consumer() — no-op, does not participate in use-def chain
ok(eval { $si->add_consumer('dummy'); 1 }, 'SubInfo add_consumer() does not die');

my $ci = Chalk::IR::ClassInfo->new(name => 'MyClass', parent => 'BaseClass', fields => [$fi], methods => [$mi], subs => [$si]);
is($ci->name(), 'MyClass', 'ClassInfo name');
is($ci->parent(), 'BaseClass', 'ClassInfo parent');
is(scalar $ci->fields()->@*, 1, 'ClassInfo fields');
is(scalar $ci->methods()->@*, 1, 'ClassInfo methods');
is(scalar $ci->subs()->@*, 1, 'ClassInfo subs');

my $ci2 = Chalk::IR::ClassInfo->new(name => 'Bare');
is($ci2->parent(), undef, 'ClassInfo parent defaults undef');
is_deeply($ci2->fields(), [], 'ClassInfo fields default empty');

my $prog = Chalk::IR::Program->new(use_decls => [{module => 'strict'}], classes => [$ci], top_level_subs => [$si]);
is(scalar $prog->use_decls()->@*, 1, 'Program use_decls');
is(scalar $prog->classes()->@*, 1, 'Program classes');
is(scalar $prog->top_level_subs()->@*, 1, 'Program top_level_subs');

my $prog2 = Chalk::IR::Program->new();
is_deeply($prog2->use_decls(), [], 'Program use_decls default empty');
is_deeply($prog2->classes(), [], 'Program classes default empty');

done_testing();
