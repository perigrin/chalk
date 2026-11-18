# ABOUTME: A package's symbols on its Class: each name its stash holds and the slots its glob fills;
# ABOUTME: names whose presence is not known; and none claimed where no symbol table was given.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::MOP;

# NO TABLE GIVEN: the Class claims nothing either way.
{
    my $cls = Chalk::MOP->new->declare_class('Quiet');
    ok(!$cls->knows_symbols, 'a class given no symbol table knows none');
    is($cls->has_symbol('x'), undef, '... and answers neither yes nor no');
}

# A TABLE: a name in it is there, one listed unknown is not answered, the rest are not there.
{
    my $cls = Chalk::MOP->new->declare_class('main');
    $cls->declare_symbols(
        { floor => { code => 1, code_from => 'POSIX' }, answer => { scalar => 1 }, 'Foo::' => { package => 1 } },
        [ 'SIG', 'STDOUT' ],
    );
    ok($cls->knows_symbols, 'a class given its table knows its symbols');
    is($cls->has_symbol('floor'), 1, 'an imported sub is there');
    is($cls->symbol('floor')->{code_from}, 'POSIX', '... with the package it came from');
    is($cls->has_symbol('answer'), 1, 'an our scalar is there');
    is($cls->has_symbol('Foo::'), 1, 'a nested package is there');
    is($cls->has_symbol('nosuch'), 0, 'what the table lacks is not');
    is($cls->has_symbol('SIG'), undef, 'a name listed unknown is not answered');
    is_deeply([ $cls->symbol_names ], [ 'Foo::', 'answer', 'floor' ], 'its names, sorted');
}

# SEALED: the table is part of what construction declares.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Late');
    $mop->seal;
    ok(!eval { $cls->declare_symbols({}, []); 1 }, 'no symbol table declared after the seal');
}

done_testing;
