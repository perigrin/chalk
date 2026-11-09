# ABOUTME: BlessedRef is any blessed reference; Object is the class feature's
# ABOUTME: instance under it; Regex (a qr//) is a sibling of Object, not under it.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::Grammar::Perl::TypeLibrary;

my $sub  = \&Chalk::Grammar::Perl::TypeLibrary::is_subtype;
my $join = \&Chalk::Grammar::Perl::TypeLibrary::join_types;

ok $sub->('BlessedRef', 'Ref'),    'a BlessedRef is a Ref';
ok $sub->('Object', 'BlessedRef'), 'an Object is a BlessedRef';
ok $sub->('Regex', 'BlessedRef'),  'a Regex is a BlessedRef';
ok !$sub->('Regex', 'Object'),     'a Regex is not an Object';
is $join->('Object', 'Regex'), 'BlessedRef', 'their join is BlessedRef';

done_testing;
