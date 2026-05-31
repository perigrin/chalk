# ABOUTME: Phase scope/control divorce C1 — verifies control_head shadow field behavior.
# ABOUTME: Confirms field default undef, propagation through extend(), and override.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Bindings;
use Chalk::IR::NodeFactory;

# Default value is undef.
my $ctx0 = Chalk::Bootstrap::Context->new(focus => undef);
ok(!defined $ctx0->control_head, 'default control_head is undef');

# Constructor accepts the field.
my $factory = Chalk::IR::NodeFactory->new();
my $start = $factory->make('Start');
my $ctx1 = Chalk::Bootstrap::Context->new(
    focus => undef,
    control_head => $start,
);
is(refaddr($ctx1->control_head), refaddr($start),
   'constructor accepts control_head');

# extend() propagates control_head.
my $ctx2 = $ctx1->extend(sub { 'whatever' });
is(refaddr($ctx2->control_head), refaddr($start),
   'extend() propagates control_head from self');

# extend() with explicit control_head override.
my $start2 = $factory->make('Start');
my $ctx3 = $ctx1->extend(sub { 'x' }, control_head => $start2);
is(refaddr($ctx3->control_head), refaddr($start2),
   'extend() with explicit control_head override works');

done_testing();
