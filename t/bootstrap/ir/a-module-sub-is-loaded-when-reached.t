# ABOUTME: a followed module's sub is loaded only when the program may run it:
# ABOUTME: called by name, or by a method call that may dispatch to it.
use 5.42.0;
use Test::More;
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;

my $call = sub (%f) { { op => 'Call', fields => {%f} } };
my %methods = (
    'main::__PROGRAM__' => { nodes => [
        $call->( name => 'M::used', dispatch_kind => 'direct' ),
        $call->( name => 'import', class_name => 'Greet', dispatch_kind => 'method' ),
        $call->( name => 'speak', dispatch_kind => 'method' ),
    ] },
    'Greet::import' => { nodes => [] },
    'M::used'       => { nodes => [], module => 'M' },
    'M::unused'     => { nodes => [], module => 'M' },
    'M::import'     => { nodes => [], module => 'M' },
    'M::speak'      => { nodes => [], module => 'M' },
);
my %classes = ( Greet => { name => 'Greet' } );
my %r = map { $_ => 1 } Chalk::IR::Serialize::JSON::_reachable_methods( \%methods, \%classes );

ok $r{'M::used'},    'a module sub called by name is reached';
ok !$r{'M::unused'}, 'one nothing calls is not';
ok !$r{'M::import'}, 'Greet->import reaches Greet::import, not every import';
ok $r{'M::speak'},   'a method call on an unknown invocant may reach any sub of its name';

done_testing;
