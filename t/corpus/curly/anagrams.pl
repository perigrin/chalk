# Anagrams and sets: words grouped by their sorted letters, set union,
# intersection and difference with hashes, and the words that can be
# spelled from a rack of letters.
use v5.42;

my @words = qw(listen silent enlist inlets google stone tones notes onset
               seton banana evil vile live veil apple pale leap plea peal);

sub letters ($w) { map { substr($w, $_, 1) } 0 .. length($w) - 1 }
sub signature ($w) { join "", sort { $a cmp $b } letters($w) }

my %groups;
push @{ $groups{ signature($_) } }, $_ for @words;
for my $sig (sort { @{ $groups{$b} } <=> @{ $groups{$a} } || $a cmp $b } keys %groups) {
    my @g = sort @{ $groups{$sig} };
    say "$sig: @g" if @g > 1;
}
say "words with no anagram here: ", join(" ", sort map { $_->@* } grep { $_->@* == 1 } values %groups);

sub set (@xs) { my %s; $s{$_} = 1 for @xs; return \%s }
sub members ($s) { sort keys %{ $s } }
sub union ($x, $y) { set((sort keys %{ $x }), (sort keys %{ $y })) }
sub intersection ($x, $y) { set(grep { $y->{$_} } sort keys %{ $x }) }
sub difference ($x, $y) { set(grep { !$y->{$_} } sort keys %{ $x }) }

my $vowels = set(qw(a e i o u));
my $first  = set(letters("abcdefghij"));
say "union:        ", join(" ", members(union($vowels, $first)));
say "intersection: ", join(" ", members(intersection($vowels, $first)));
say "difference:   ", join(" ", members(difference($first, $vowels)));
say "symmetric:    ", join(" ", members(union(difference($vowels, $first), difference($first, $vowels))));

sub can_spell ($word, $rack) {
    my %have;
    $have{$_}++ for letters($rack);
    for my $c (letters($word)) {
        return 0 unless $have{$c}--;
    }
    return 1;
}

my $rack = "aelpnst";
my @spellable = grep { can_spell($_, $rack) } @words;
say "from '$rack': @spellable";
my ($best) = sort { length($b) <=> length($a) || $a cmp $b } @spellable;
say "longest: $best";
