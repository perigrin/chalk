# ABOUTME: A Boolean recognition keeps no Context per derivation, however long the input.
# ABOUTME: Counts the Context objects alive after a parse while its result is still held.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use Scalar::Util qw(weaken);

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value)  { Chalk::Grammar::Symbol->new(type => 'terminal',  value => $value) }
sub reference($value) { Chalk::Grammar::Symbol->new(type => 'reference', value => $value) }
sub rule($name, @alts) { Chalk::Grammar::Rule->new(name => $name, expressions => [@alts]) }

# Every Context constructed, held weakly: an entry stays defined only
# while something else still refers to the object.
my @constructed;
{
    no warnings 'redefine';
    my $new = Chalk::Bootstrap::Context->can('new');
    *Chalk::Bootstrap::Context::new = sub {
        my $ctx = $new->(@_);
        push @constructed, $ctx;
        weaken($constructed[-1]);
        return $ctx;
    };
}

# List ::= Item | List , Item ;  and an ambiguous sum, so both multiply
# and add run.
my $grammar = [
    rule('List', [reference('E')], [reference('List'), terminal(';'), reference('E')]),
    rule('E',    [reference('E'), terminal('\+'), reference('E')], [terminal('a')]),
];

# Contexts alive once the parse of $items list items has returned, with
# its value still held.
sub contexts_alive_after($items) {
    @constructed = ();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );
    my $value = $parser->parse_value(join ';', ('a+a+a') x $items);
    ok(defined $value && !$value->is_zero(), "accepts $items items");
    return scalar grep { defined } @constructed;
}

my $small = contexts_alive_after(5);
my $large = contexts_alive_after(50);

# The two Boolean values are created once, on first use, and outlive every
# parse; nothing constructed during a parse survives it.
is($small, 1, 'the first parse leaves only the one() value alive');
is($large, 0, 'a later, longer parse leaves no Context of its own alive');

done_testing();
