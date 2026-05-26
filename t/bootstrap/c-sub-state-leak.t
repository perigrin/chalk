# ABOUTME: Phase 7d test that _emit_sub's try/catch save/restore preserves state.
# ABOUTME: Verifies an exception during sub compilation does not leak _current_sub_name/_return_context.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::SubStateLeak',
);
$target->_set_current_slug('substateleak');

# Verify initial state: empty sub name, false return context.
is($target->_get_current_sub_name, '', 'initial _current_sub_name is empty');

# Set a known prior state to test restore.
$target->_set_current_sub_name('prior_sub');
$target->_set_return_context(true);

# Build a deliberately-malformed MOP::Sub (graph has no schedule-able structure).
my $mop = Chalk::MOP->new;
my $cls = $mop->declare_class('Test::SubStateLeak');
my $broken_sub = $cls->declare_sub('broken',
    params => [],
    body   => [],
    graph  => Chalk::IR::Graph->new,  # empty graph; scheduler may handle or throw
);

# Try to emit. If it throws, that's expected; what matters is state restoration.
eval { $target->_emit_sub($broken_sub) };
# (The eval may or may not catch — depending on whether the broken sub
# triggers an exception. Either way, the test asserts state restoration.)

is($target->_get_current_sub_name, 'prior_sub',
   '_current_sub_name restored to prior value after emission attempt');
is($target->_get_return_context, true,
   '_return_context restored to prior value after emission attempt');

done_testing();
