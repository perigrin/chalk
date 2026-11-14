#!/usr/bin/env perl
# ABOUTME: A builtin Call answers Perl's facts about its builtin (from TypeLibrary's signatures and
# ABOUTME: BuiltinTable), and an EntryDef whether its name is perl's own: no backend keeps the lists.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;

my $f = Chalk::IR::NodeFactory->new;
sub builtin ($name) { $f->make('Call', dispatch_kind => 'builtin', name => $name, inputs => []) }
sub sub_call ($kind, $name = 'main::f') { $f->make('Call', dispatch_kind => $kind, name => $name, inputs => []) }

subtest 'is_sub_call: a call of a sub (named, a method, a code value), not a builtin' => sub {
    ok( sub_call($_)->is_sub_call, "$_ is a sub call" ) for qw(direct method indirect);
    ok( !builtin('push')->is_sub_call, 'a builtin is not' );
};

subtest 'mutates_array: from the signature -- an Array operand first' => sub {
    ok( builtin($_)->mutates_array, "$_ changes its array" ) for qw(push pop shift unshift splice);
    ok( !builtin($_)->mutates_array, "$_ does not" ) for qw(keys join sort reverse lc);
    ok( !sub_call( 'direct', 'push' )->mutates_array, 'a sub named push is not the builtin' );
};

subtest 'result_type: the signature\'s, else the table\'s' => sub {
    is( builtin('join')->result_type, 'Str', 'join: a Str (TypeLibrary)' );
    is( builtin('keys')->result_type, 'List', 'keys: a List (TypeLibrary)' );
    is( builtin('lc')->result_type, 'Str', 'lc: a Str (BuiltinTable: no signature)' );
    is( builtin('quotemeta')->result_type, 'Str', 'quotemeta: a Str (BuiltinTable)' );
    is( builtin('no_such_builtin')->result_type, undef, 'an unknown builtin: undef' );
    is( sub_call('direct')->result_type, undef, 'a sub: undef (no builtin signature)' );
};

subtest 'returns_string: its result type is Str' => sub {
    ok( builtin($_)->returns_string, "$_ returns a string" )
        for qw(join sprintf substr lc uc lcfirst ucfirst quotemeta chr);
    ok( !builtin($_)->returns_string, "$_ does not" ) for qw(keys push length shift);
};

subtest 'changes_case: lc, uc, lcfirst, ucfirst' => sub {
    ok( builtin($_)->changes_case, "$_ changes case" ) for qw(lc uc lcfirst ucfirst);
    ok( !builtin($_)->changes_case, "$_ does not" ) for qw(quotemeta join substr);
};

subtest 'is_tie_builtin: tie, tied, untie' => sub {
    ok( builtin($_)->is_tie_builtin, "$_ is of a tie" ) for qw(tie tied untie);
    ok( !builtin($_)->is_tie_builtin, "$_ is not" ) for qw(bless push);
};

subtest 'takes_a_list: what it is given (after its first operand) is a LIST' => sub {
    ok( builtin($_)->takes_a_list, "$_ takes a list" ) for qw(push unshift join sprintf printf die warn);
    ok( !builtin($_)->takes_a_list, "$_ does not" ) for qw(shift pop lc length);
    ok( !sub_call('direct', 'join')->takes_a_list, 'a sub named join is not the builtin' );
};

subtest 'makes_a_string: a builtin returning a string makes one (chr and chop too, as their signatures say)' => sub {
    ok( builtin($_)->makes_a_string, "$_ makes a string" ) for qw(join sprintf substr lc quotemeta chr chop);
    ok( !builtin($_)->makes_a_string, "$_ does not" ) for qw(keys shift length);
    my $s = $f->make('Constant', value => 'a', const_type => 'string');
    my $q = $f->make('Constant', value => 'a', const_type => 'regex');
    ok( $s->makes_a_string, 'a string constant does' );
    ok( !$q->makes_a_string, 'a qr constant does not' );
    ok( $f->make('DefinedOr', inputs => [ $s, builtin('chr') ])->makes_a_string, 'a default of strings does' );
    ok( !$f->make('DefinedOr', inputs => [ $s, $q ])->makes_a_string, 'a default of a qr does not' );
};

subtest 'is_perls_own: a name perl gives its own meaning, by sigil' => sub {
    my $e = sub ($sigil, $symbol) { $f->make('EntryDef', sigil => $sigil, symbol => $symbol, package => 'main') };
    ok( $e->( '$', $_ )->is_perls_own, "\$$_ is perl's" ) for qw(ENV INC ARGV STDIN STDOUT STDERR 0 AUTOLOAD);
    ok( $e->( '@', $_ )->is_perls_own, "\@$_ is perl's" ) for qw(ISA ARGV INC _);
    ok( $e->( '%', $_ )->is_perls_own, "%$_ is perl's" ) for qw(ENV SIG INC);
    ok( !$e->( '$', $_ )->is_perls_own, "\$$_ is the program's" ) for qw(_ a b x ISA);
    ok( !$e->( '@', $_ )->is_perls_own, "\@$_ is the program's" ) for qw(a AUTOLOAD);
};

done_testing;
