# A binary search tree of hash references: insert, look up, walk in
# three orders, height, the k-th smallest, deletion, and a pretty
# sideways drawing.
use v5.42;
no warnings 'recursion';

sub insert ($tree, $key, $value = undef) {
    return { key => $key, value => $value // $key, left => undef, right => undef, size => 1 } unless $tree;
    if ($key < $tree->{key}) {
        $tree->{left} = insert($tree->{left}, $key, $value);
    } elsif ($key > $tree->{key}) {
        $tree->{right} = insert($tree->{right}, $key, $value);
    } else {
        $tree->{value} = $value // $key;
        return $tree;
    }
    $tree->{size} = 1 + size($tree->{left}) + size($tree->{right});
    return $tree;
}

sub size ($t) { $t ? $t->{size} : 0 }

sub lookup ($t, $key) {
    while ($t) {
        return $t->{value} if $key == $t->{key};
        $t = $key < $t->{key} ? $t->{left} : $t->{right};
    }
    return undef;
}

sub walk ($t, $order, $visit) {
    return unless $t;
    $visit->($t->{key}) if $order eq 'pre';
    walk($t->{left}, $order, $visit);
    $visit->($t->{key}) if $order eq 'in';
    walk($t->{right}, $order, $visit);
    $visit->($t->{key}) if $order eq 'post';
}

sub height ($t) {
    return 0 unless $t;
    my ($l, $r) = (height($t->{left}), height($t->{right}));
    return 1 + ($l > $r ? $l : $r);
}

sub kth ($t, $k) {
    my $left = size($t->{left});
    return kth($t->{left}, $k) if $k <= $left;
    return $t->{key} if $k == $left + 1;
    return kth($t->{right}, $k - $left - 1);
}

sub remove ($t, $key) {
    return undef unless $t;
    if ($key < $t->{key}) {
        $t->{left} = remove($t->{left}, $key);
    } elsif ($key > $t->{key}) {
        $t->{right} = remove($t->{right}, $key);
    } else {
        return $t->{right} unless $t->{left};
        return $t->{left} unless $t->{right};
        my $m = $t->{right};
        $m = $m->{left} while $m->{left};
        $t->{key} = $m->{key};
        $t->{value} = $m->{value};
        $t->{right} = remove($t->{right}, $m->{key});
    }
    $t->{size} = 1 + size($t->{left}) + size($t->{right});
    return $t;
}

sub draw ($t, $depth = 0) {
    return unless $t;
    draw($t->{right}, $depth + 1);
    say "    " x $depth, $t->{key};
    draw($t->{left}, $depth + 1);
}

my $root;
$root = insert($root, $_) for 50, 30, 70, 20, 40, 60, 80, 35, 45, 65;
for my $order (qw(pre in post)) {
    my @keys;
    walk($root, $order, sub ($k) { push @keys, $k });
    say "$order-order: @keys";
}
say "size ", size($root), ", height ", height($root);
say "3rd smallest: ", kth($root, 3), "; 8th: ", kth($root, 8);
$root = insert($root, 40, "forty");
say "lookup 40: ", lookup($root, 40), "; lookup 99: ", lookup($root, 99) // "none";
draw($root);
$root = remove($root, $_) for 30, 50, 99;
say "after removing 30, 50 and 99:";
draw($root);
my @after;
walk($root, 'in', sub ($k) { push @after, $k });
say "in-order: @after; size ", size($root);

my $chain;
$chain = insert($chain, $_) for 1 .. 200;
say "200 keys inserted in order make a tree ", height($chain), " high";
