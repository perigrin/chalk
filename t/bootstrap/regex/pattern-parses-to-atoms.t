# ABOUTME: Chalk::Regex::Pattern reads a constant regex into atoms (G6's front
# ABOUTME: half, out of Context): literals, classes, groups, quantifiers; refusals by name.
use 5.42.0;
use Test::More;
use lib 'lib';
use Chalk::Regex::Pattern;

my $p = Chalk::Regex::Pattern::compile( '^a[b-d]\d+(x)y$', '' );
is_deeply [ map { $_->{kind} } $p->{atoms}->@* ], [qw(lit class class gopen lit gclose lit)], 'atoms in order';
ok $p->{anchored_start} && $p->{anchored_end}, '^ and $ anchor';
is $p->{ngroups}, 1, 'one capture';
is_deeply [ @{ $p->{atoms}[2] }{qw(min max)} ], [ 1, undef ], '\d+ is one or more';
is_deeply $p->{atoms}[1]{ranges}, [ [ ord 'b', ord 'd' ] ], 'a class range';

# NEVER A SILENT WRONG MATCH: what it does not read is refused by name.
for my $refused ( [ 'a|b', '' ], [ 'a', 'i' ], [ '\bx', '' ], [ '(?=x)', '' ] ) {
    ok !eval { Chalk::Regex::Pattern::compile(@$refused); 1 }, "/$refused->[0]/$refused->[1] refused";
    like $@, qr/\AGAP: /, '... as a GAP';
}

# A `u` flag that changes nothing here is dropped, as G6 did.
ok eval { Chalk::Regex::Pattern::compile( 'abc', 'u' ); 1 }, 'an inert /u is no flag' or diag $@;
is Chalk::Regex::Pattern::without_inert_u( '\w', 'u' ), 'u', '... but /u with \w is kept';

done_testing;
