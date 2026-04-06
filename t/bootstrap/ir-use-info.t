# ABOUTME: Tests for Chalk::IR::UseInfo metadata struct.
# ABOUTME: Verifies that UseInfo stores module name and import args correctly.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::UseInfo;

# === Basic construction ===

my $ui = Chalk::IR::UseInfo->new(name => 'strict', args => []);
isa_ok($ui, 'Chalk::IR::UseInfo', 'UseInfo is a UseInfo');
is($ui->name(), 'strict', 'UseInfo name');
is_deeply($ui->args(), [], 'UseInfo args is empty arrayref');

# === Name-only (no args) with default ===

my $ui2 = Chalk::IR::UseInfo->new(name => '5.42.0');
is($ui2->name(), '5.42.0', 'UseInfo name is version string');
is_deeply($ui2->args(), [], 'UseInfo args defaults to empty arrayref');

# === With import args ===

my $ui3 = Chalk::IR::UseInfo->new(name => 'experimental', args => ['class']);
is($ui3->name(), 'experimental', 'UseInfo with args: name');
is_deeply($ui3->args(), ['class'], 'UseInfo with args: args preserved');

# === Multiple import args ===

my $ui4 = Chalk::IR::UseInfo->new(name => 'feature', args => ['say', 'state']);
is($ui4->name(), 'feature', 'UseInfo multi args: name');
is_deeply($ui4->args(), ['say', 'state'], 'UseInfo multi args: both preserved');

# === id() method (for NodeFactory hash-cons compatibility) ===

my $ui5 = Chalk::IR::UseInfo->new(name => 'strict', args => []);
my $id1 = $ui5->id();
ok(defined $id1, 'UseInfo id() returns a value');
like($id1, qr/UseInfo/, 'UseInfo id() contains UseInfo marker');
like($id1, qr/strict/, 'UseInfo id() contains module name');

my $ui6 = Chalk::IR::UseInfo->new(name => 'strict', args => []);
is($ui5->id(), $ui6->id(), 'UseInfo id() is content-based (same name/args => same id)');

my $ui7 = Chalk::IR::UseInfo->new(name => 'warnings', args => []);
isnt($ui5->id(), $ui7->id(), 'UseInfo id() differs for different names');

# === add_consumer() no-op ===

my $ui8 = Chalk::IR::UseInfo->new(name => 'strict', args => []);
ok(eval { $ui8->add_consumer('dummy'); 1 }, 'add_consumer() does not die');

done_testing;
