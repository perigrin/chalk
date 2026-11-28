# Huffman coding: the frequencies of a text, the tree built from a
# priority list of nested array references, the code table, the text
# encoded to bits and decoded again, and how much it saved.
use v5.42;

my $text = "this is an example of a huffman tree, built in a language that has no regexes yet";

# No split yet (step 20): a string's characters.
sub chars ($s) { map { substr($s, $_, 1) } 0 .. length($s) - 1 }

my %freq;
$freq{$_}++ for chars($text);

# A leaf is [weight, char]; a node is [weight, left, right]. Ties are
# broken by the smallest character under each, so the tree is the same
# under every hash order.
sub least ($n) { $n->@* == 2 ? $n->[1] : least($n->[1]) lt least($n->[2]) ? least($n->[1]) : least($n->[2]) }

my @queue = map { [$freq{$_}, $_] } sort keys %freq;
while (@queue > 1) {
    @queue = sort { $a->[0] <=> $b->[0] || least($a) cmp least($b) } @queue;
    my ($x, $y) = splice(@queue, 0, 2);
    push @queue, [$x->[0] + $y->[0], $x, $y];
}
my $tree = $queue[0];

my %code;
sub assign ($node, $prefix) {
    if ($node->@* == 2) {
        $code{$node->[1]} = $prefix eq "" ? "0" : $prefix;
        return;
    }
    assign($node->[1], $prefix . "0");
    assign($node->[2], $prefix . "1");
}
assign($tree, "");

for my $c (sort { $freq{$b} <=> $freq{$a} || $a cmp $b } keys %code) {
    printf "'%s' %2d %s\n", $c, $freq{$c}, $code{$c};
}

my $bits = join "", map { $code{$_} } chars($text);
my %decode = map { ($code{$_} => $_) } sort keys %code;
my ($decoded, $cur) = ("", "");
for my $bit (chars($bits)) {
    $cur .= $bit;
    if (exists $decode{$cur}) {
        $decoded .= $decode{$cur};
        $cur = "";
    }
}
say "decoded matches: ", $decoded eq $text ? "yes" : "no";
printf "%d characters, %d bits instead of %d (%.1f%%)\n", length $text, length $bits, 8 * length $text, 100 * length($bits) / (8 * length $text);
say "first 64 bits: ", substr($bits, 0, 64);
