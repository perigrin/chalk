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

# A MODULE SUB B::SoN REFUSED (wire `refused`) is absent; reaching it refuses
# the program in the module's own words, not as a call to an unknown sub.
my %refused = ( 'M::g' => 'GAP: `goto` transfers control and is not compiled' );
my %prog = ( 'main::__PROGRAM__' => { nodes => [ $call->( name => 'M::g', dispatch_kind => 'direct' ) ] } );
ok !eval { Chalk::IR::Serialize::JSON::_reachable_methods( \%prog, {}, \%refused ); 1 },
    'a direct call to a refused module sub refuses';
like $@, qr/M::g.*`goto` transfers control/, '... in the module\'s words';
%prog = ( 'main::__PROGRAM__' => { nodes => [ $call->( name => 'g', class_name => 'M', dispatch_kind => 'method' ) ] } );
ok !eval { Chalk::IR::Serialize::JSON::_reachable_methods( \%prog, {}, \%refused ); 1 },
    'so does M->g, which dispatches to it';
# ONLY WHERE IT SURELY RUNS: a method call on an unknown invocant may reach a
# sub of its name, and a module sub reached that way may call the refused one;
# neither is reason to refuse the program.
%prog = ( 'main::__PROGRAM__' => { nodes => [ $call->( name => 'import', dispatch_kind => 'method' ) ] },
          'M::import' => { nodes => [ $call->( name => 'M::g', dispatch_kind => 'direct' ) ], module => 'M' } );
ok eval { Chalk::IR::Serialize::JSON::_reachable_methods( \%prog, {}, \%refused ); 1 },
    'a refused sub reached only through a guess refuses nothing' or diag $@;
%prog = ( 'main::__PROGRAM__' => { nodes => [ $call->( name => 'M::other', dispatch_kind => 'direct' ) ] }, 'M::other' => { nodes => [], module => 'M' } );
ok eval { Chalk::IR::Serialize::JSON::_reachable_methods( \%prog, {}, \%refused ); 1 },
    'a refused sub nothing reaches refuses nothing' or diag $@;

done_testing;
