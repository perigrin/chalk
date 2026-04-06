# ABOUTME: Tests for Chalk::IR::Program metadata struct.
# ABOUTME: Verifies that Program stores use_decls, classes, and top_level_subs with id() and add_consumer().
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Program;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::SubInfo;

# === Basic construction with defaults ===

my $prog_empty = Chalk::IR::Program->new();
isa_ok($prog_empty, 'Chalk::IR::Program', 'empty Program is a Program');
is_deeply($prog_empty->use_decls(),      [], 'Program use_decls defaults to []');
is_deeply($prog_empty->classes(),        [], 'Program classes defaults to []');
is_deeply($prog_empty->top_level_subs(), [], 'Program top_level_subs defaults to []');

# === Construction with members ===

my $ui  = Chalk::IR::UseInfo->new(name => 'strict');
my $ci  = Chalk::IR::ClassInfo->new(name => 'Foo');
my $si  = Chalk::IR::SubInfo->new(name => 'bar');

my $prog = Chalk::IR::Program->new(
    use_decls      => [$ui],
    classes        => [$ci],
    top_level_subs => [$si],
);

is(scalar $prog->use_decls()->@*,      1, 'Program stores 1 use_decl');
is(scalar $prog->classes()->@*,        1, 'Program stores 1 class');
is(scalar $prog->top_level_subs()->@*, 1, 'Program stores 1 top_level_sub');

is($prog->use_decls()->[0],      $ui, 'Program use_decls[0] is the UseInfo');
is($prog->classes()->[0],        $ci, 'Program classes[0] is the ClassInfo');
is($prog->top_level_subs()->[0], $si, 'Program top_level_subs[0] is the SubInfo');

# === id() method ===

my $id = $prog_empty->id();
ok(defined $id, 'Program id() returns a value');
like($id, qr/Program/, 'Program id() contains Program marker');

# Same content → same id
my $prog_a = Chalk::IR::Program->new();
my $prog_b = Chalk::IR::Program->new();
is($prog_a->id(), $prog_b->id(), 'Program id() is content-based (same content => same id)');

# Different content → different id
my $prog_with_use = Chalk::IR::Program->new(use_decls => [$ui]);
isnt($prog_empty->id(), $prog_with_use->id(), 'Program id() differs when use_decls differ');

# id() includes class names
my $prog_with_class = Chalk::IR::Program->new(classes => [$ci]);
isnt($prog_empty->id(), $prog_with_class->id(), 'Program id() differs when classes differ');

# === add_consumer() no-op ===

ok(eval { $prog_empty->add_consumer('dummy'); 1 }, 'add_consumer() does not die');
ok(eval { $prog->add_consumer(bless {}, 'FakeNode'); 1 }, 'add_consumer() works with any arg');

done_testing;
