# ABOUTME: A derivation reaching an already-processed item is kept, whatever follows it.
# ABOUTME: Counts derivations with a counting semiring; a dropped one shows as a lower count.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;

# The number of derivations: add sums, multiply multiplies. Scan and
# completion events (Contexts) leave the count as it is.
package CountingSemiring {
    sub new($class) { return bless {}, $class }
    sub n($v) { return bless { n => $v }, 'CountingSemiring::Value' }
    sub zero($self) { return n(0) }
    sub one($self) { return n(1) }
    sub one_with_control($self, $node) { return n(1) }
    sub is_zero($self, $v) { return $v->{n} == 0 }
    sub add($self, $l, $r) { return n($l->{n} + $r->{n}) }
    sub multiply($self, $l, $r) {
        return $l unless blessed($r) && $r isa CountingSemiring::Value;
        return n($l->{n} * $r->{n});
    }
}

sub terminal($value)  { Chalk::Grammar::Symbol->new(type => 'terminal',  value => $value) }
sub reference($value) { Chalk::Grammar::Symbol->new(type => 'reference', value => $value) }
sub rule($name, @alts) { Chalk::Grammar::Rule->new(name => $name, expressions => [@alts]) }

# X has two derivations of "ab", which complete at the same position in
# different agenda turns: `a b` directly, and `a Q` one completion later.
# The second reaches `S ::= X . W y` after it was processed.
sub count_parses($tail_rule, $input) {
    my $grammar = [
        rule('S', [reference('X'), reference($tail_rule), terminal('y')]),
        rule('X', [terminal('a'), terminal('b')], [reference('P')]),
        rule('P', [terminal('a'), reference('Q')]),
        rule('Q', [terminal('b')]),
        rule('W', [terminal('w')]),
    ];
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => CountingSemiring->new,
    );
    my $value = $parser->parse_value($input);
    return defined $value ? $value->{n} : undef;
}

is(count_parses('W', 'abwy'), 2,
    'both derivations of X survive when a nonterminal that completes later follows it');

done_testing();
