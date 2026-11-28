# A singly linked list built from hash references: push and shift at
# either end, reverse in place, find, delete, and a merge of two sorted
# lists; each operation checked by walking the list.
use v5.42;

sub new_list () { return { head => undef, tail => undef, size => 0 } }

sub push_back ($list, $value) {
    my $node = { value => $value, next => undef };
    if ($list->{tail}) {
        $list->{tail}{next} = $node;
    } else {
        $list->{head} = $node;
    }
    $list->{tail} = $node;
    $list->{size}++;
    return $list;
}

sub push_front ($list, $value) {
    $list->{head} = { value => $value, next => $list->{head} };
    $list->{tail} //= $list->{head};
    $list->{size}++;
    return $list;
}

sub shift_front ($list) {
    my $node = $list->{head};
    return undef unless $node;
    $list->{head} = $node->{next};
    $list->{tail} = undef unless $list->{head};
    $list->{size}--;
    return $node->{value};
}

sub to_array ($list) {
    my @out;
    for (my $n = $list->{head}; $n; $n = $n->{next}) {
        push @out, $n->{value};
    }
    return @out;
}

sub show ($label, $list) {
    say sprintf("%-10s", $label), "(", join(" -> ", to_array($list)), ") size $list->{size}";
}

sub reverse_list ($list) {
    my ($prev, $cur) = (undef, $list->{head});
    $list->{tail} = $cur;
    while ($cur) {
        my $next = $cur->{next};
        $cur->{next} = $prev;
        ($prev, $cur) = ($cur, $next);
    }
    $list->{head} = $prev;
    return $list;
}

sub find ($list, $pred) {
    my $i = 0;
    for (my $n = $list->{head}; $n; $n = $n->{next}) {
        return $i if $pred->($n->{value});
        $i++;
    }
    return -1;
}

sub delete_value ($list, $value) {
    my $removed = 0;
    while ($list->{head} && $list->{head}{value} == $value) {
        shift_front($list);
        $removed++;
    }
    my $n = $list->{head};
    while ($n && $n->{next}) {
        if ($n->{next}{value} == $value) {
            $n->{next} = $n->{next}{next};
            $list->{size}--;
            $removed++;
        } else {
            $n = $n->{next};
        }
    }
    $list->{tail} = $n;
    return $removed;
}

sub merge_sorted ($x, $y) {
    my $out = new_list();
    my ($p, $q) = ($x->{head}, $y->{head});
    while ($p || $q) {
        if (!$q || ($p && $p->{value} <= $q->{value})) {
            push_back($out, $p->{value});
            $p = $p->{next};
        } else {
            push_back($out, $q->{value});
            $q = $q->{next};
        }
    }
    return $out;
}

my $l = new_list();
push_back($l, $_) for 1 .. 5;
push_front($l, 0);
show("built", $l);
say "shifted ", shift_front($l);
show("now", $l);
reverse_list($l);
show("reversed", $l);
push_back($l, 9);
show("pushed 9", $l);
say "first even at ", find($l, sub ($v) { $v % 2 == 0 });
say "first over 100 at ", find($l, sub ($v) { $v > 100 });

my $d = new_list();
push_back($d, $_) for 3, 1, 3, 3, 2, 3;
say "deleted ", delete_value($d, 3), " threes";
show("left", $d);
push_back($d, 7);
show("then 7", $d);

my ($e, $o) = (new_list(), new_list());
push_back($e, $_ * 2) for 0 .. 5;
push_back($o, $_ * 3 + 1) for 0 .. 4;
show("merged", merge_sorted($e, $o));

my $empty = new_list();
say "shift from empty: ", shift_front($empty) // "undef";
