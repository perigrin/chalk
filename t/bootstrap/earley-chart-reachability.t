# ABOUTME: Chart rows that no live item can reach any more are freed during the parse.
# ABOUTME: The rows held at once stay bounded on a long input, and parse values are unchanged.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value)  { Chalk::Grammar::Symbol->new(type => 'terminal',  value => $value) }
sub reference($value) { Chalk::Grammar::Symbol->new(type => 'reference', value => $value) }
sub rule($name, @alts) { Chalk::Grammar::Rule->new(name => $name, expressions => [@alts]) }

# The derivation written out as text: a value that differs whenever the
# parse differs in any way, including the order of its alternatives.
package TreeSemiring {
    sub new($class) { return bless {}, $class }
    sub v($text) { return bless { t => $text }, 'TreeSemiring::Value' }
    sub zero($self) { return bless { t => '', zero => true }, 'TreeSemiring::Value' }
    sub one($self) { return v('') }
    sub one_with_control($self, $node) { return v('') }
    sub is_zero($self, $value) { return $value->{zero} ? true : false }
    sub add($self, $l, $r) {
        return $r if $l->{zero};
        return $l if $r->{zero};
        return v("{$l->{t}|$r->{t}}");
    }
    sub multiply($self, $l, $r) {
        return $l if $l->{zero};
        if (blessed($r) && $r isa TreeSemiring::Value) {
            return $r if $r->{zero};
            return v("$l->{t}$r->{t}");
        }
        my $event = $r->annotations();
        return v($l->{t} . $r->extract()) if $event->{scan};
        return v("($event->{rule_name}.$event->{alt_idx} $l->{t})");
    }
}

# The number of derivations: add sums, multiply multiplies.
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

sub parser($grammar, $semiring, %opts) {
    return Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
        %opts,
    );
}

# Statements of ambiguous, nested sums in a left-recursive list. A
# statement's rows are unreachable once the list has moved past it.
my $statements = [
    rule('List', [reference('Stmt')], [reference('List'), reference('Stmt')]),
    rule('Stmt', [reference('E'), terminal(';')]),
    rule('E',
        [reference('E'), terminal('\+'), reference('E')],
        [terminal('\('), reference('E'), terminal('\)')],
        [terminal('a')],
    ),
];
my $statement = 'a+(a+a)+a;';

subtest 'rows held at once do not grow with the input' => sub {
    my %held;
    for my $count (200, 800) {
        my $p = parser($statements, Chalk::Bootstrap::Semiring::Boolean->new());
        ok($p->parse($statement x $count), "accepts $count statements");
        my $stats = $p->gc_stats();
        $held{$count} = $stats->{rows_held_max};
        cmp_ok($stats->{unreachable_freed} // 0, '>', length($statement) * $count / 2,
            "$count statements: most rows were freed as unreachable");
    }
    ok(defined $held{800}, 'the parser reports the most rows it held at once');
    is($held{800}, $held{200}, 'four times the input holds no more rows at once');

    my $off = parser($statements, Chalk::Bootstrap::Semiring::Boolean->new(), chart_gc => false);
    ok($off->parse($statement x 200), 'accepts with chart_gc off');
    is($off->gc_stats()->{unreachable_freed} // 0, 0, 'chart_gc => false frees no unreachable rows');
};

# Freeing must not change any value: compare each parse with the same
# parse run with the sweep off.
sub same_with_and_without_gc($grammar, $input, $label) {
    for my $semiring_class (qw(TreeSemiring CountingSemiring)) {
        my $on  = parser($grammar, $semiring_class->new());
        my $off = parser($grammar, $semiring_class->new(), chart_gc => false);
        my $got      = $on->parse_value($input);
        my $expected = $off->parse_value($input);
        ok(defined $expected, "$label ($semiring_class): parses with the sweep off");
        is_deeply($got, $expected, "$label ($semiring_class): same value with the sweep on");
        cmp_ok($on->gc_stats()->{unreachable_freed}, '>', 0,
            "$label ($semiring_class): the sweep freed rows");
    }
}

subtest 'values are the same with and without the sweep' => sub {
    same_with_and_without_gc($statements, $statement x 150, 'ambiguous statements');

    # Right recursion: Leo items jump over the intermediate rows.
    my $chain = [
        rule('Chain', [reference('Item')], [reference('Item'), reference('Sep'), reference('Chain')]),
        rule('Item', [terminal('x')]),
        rule('Sep',  [terminal(',')]),
    ];
    same_with_and_without_gc($chain, join(',', ('x') x 700), 'right-recursive chain');

    # A right-recursive list of statements: every statement start stays
    # reachable through the list item waiting there.
    my $right_list = [
        rule('List', [reference('Stmt')], [reference('Stmt'), reference('List')]),
        $statements->@[1, 2],
    ];
    same_with_and_without_gc($right_list, $statement x 150, 'right-recursive statements');

    # Nullable symbols inside an ambiguous rule.
    my $nullable = [
        rule('List', [reference('Stmt')], [reference('List'), reference('Stmt')]),
        rule('Stmt', [reference('E'), terminal(';')]),
        rule('E', [reference('B')], [terminal('a')]),
        rule('B', [reference('E'), reference('W'), terminal('\+'), reference('W'), reference('E')]),
        rule('W', [terminal(' ')], []),
    ];
    same_with_and_without_gc($nullable, 'a + a+a +a;' x 120, 'nullable whitespace');
};

subtest 'derivation counts survive the sweep' => sub {
    # "a+a+a" has Catalan(2) = 2 parses; statements multiply.
    my $p = parser($statements, CountingSemiring->new());
    my $value = $p->parse_value('a+a+a;' x 50);
    cmp_ok($value->{n}, '==', 2 ** 50, '50 statements of 2 parses each: 2**50 derivations');
    cmp_ok($p->gc_stats()->{unreachable_freed}, '>', 0, 'the sweep ran');
};

done_testing();
