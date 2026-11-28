# Matrices as arrays of arrays: transpose, multiply, identity, powers,
# the determinant by cofactors, and Fibonacci by a matrix power.
use v5.42;

sub show ($name, $m) {
    say "$name:";
    for my $row ($m->@*) {
        say "  ", join(" ", map { sprintf "%5s", $_ } $row->@*);
    }
}

sub transpose ($m) {
    my @t;
    for my $i (0 .. $m->$#*) {
        for my $j (0 .. $#{ $m->[$i] }) {
            my $v = $m->[$i][$j];
            $t[$j][$i] = $v;
        }
    }
    return \@t;
}

sub multiply ($x, $y) {
    my $n = $x->@*;
    my $p = @{ $y->[0] };
    my $inner = $y->@*;
    die "can't multiply: ", scalar(@{ $x->[0] }), " columns against $inner rows\n"
        unless @{ $x->[0] } == $inner;
    my @r;
    for my $i (0 .. $n - 1) {
        for my $j (0 .. $p - 1) {
            my $sum = 0;
            $sum += $x->[$i][$_] * $y->[$_][$j] for 0 .. $inner - 1;
            $r[$i][$j] = $sum;
        }
    }
    return \@r;
}

sub identity ($n) {
    return [ map { my $i = $_; [ map { $_ == $i ? 1 : 0 } 0 .. $n - 1 ] } 0 .. $n - 1 ];
}

sub power ($m, $k) {
    my $result = identity(scalar($m->@*));
    while ($k > 0) {
        $result = multiply($result, $m) if $k % 2;
        $m = multiply($m, $m);
        $k = ($k - $k % 2) / 2;
    }
    return $result;
}

sub minor ($m, $col) {
    return [ map { my $row = $_; [ $row->@[ grep { $_ != $col } 0 .. $row->$#* ] ] } $m->@[1 .. $m->$#*] ];
}

sub det ($m) {
    return $m->[0][0] if $m->@* == 1;
    my $d = 0;
    for my $j (0 .. $m->$#*) {
        my $sign = $j % 2 ? -1 : 1;
        $d += $sign * $m->[0][$j] * det(minor($m, $j));
    }
    return $d;
}

my $ma = [[1, 2, 3], [4, 5, 6]];
my $mb = [[7, 8], [9, 10], [11, 12]];
show("A", $ma);
show("A transposed", transpose($ma));
show("A x B", multiply($ma, $mb));
show("B x A", multiply($mb, $ma));

try {
    multiply($ma, $ma);
} catch ($e) {
    print "A x A: $e";
}

my $m = [[2, -1, 0], [-1, 2, -1], [0, -1, 2]];
say "det = ", det($m);
show("M^3", power($m, 3));

my $fib = power([[1, 1], [1, 0]], 40);
say "fib(40) from a matrix power: $fib->[0][1]";
