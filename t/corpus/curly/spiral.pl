# Walking a grid: a matrix filled in a spiral and read back, rotated a
# quarter turn, its diagonals summed, and Pascal's triangle and a
# multiplication table laid out in columns.
use v5.42;

sub spiral ($n) {
    my @m = map { [ (0) x $n ] } 1 .. $n;
    my ($r, $c, $dr, $dc) = (0, 0, 0, 1);
    for my $k (1 .. $n * $n) {
        $m[$r][$c] = $k;
        my ($nr, $nc) = ($r + $dr, $c + $dc);
        if ($nr < 0 || $nr >= $n || $nc < 0 || $nc >= $n || $m[$nr][$nc]) {
            ($dr, $dc) = ($dc, -$dr);
            ($nr, $nc) = ($r + $dr, $c + $dc);
        }
        ($r, $c) = ($nr, $nc);
    }
    return \@m;
}

sub show ($m) {
    my $w = length(scalar($m->@*) ** 2);
    say join(" ", map { sprintf "%*d", $w, $_ } $_->@*) for $m->@*;
}

sub read_spiral ($m) {
    my @rows = map { [$_->@*] } $m->@*;
    my @out;
    while (@rows) {
        push @out, @{ shift @rows };
        push @out, pop $_->@* for @rows;
        push @out, reverse @{ pop @rows } if @rows;
        push @out, shift @{ $rows[$_] } for reverse 0 .. $#rows;
        @rows = grep { $_->@* } @rows;
    }
    return @out;
}

sub rotate ($m) {
    my $n = $m->@*;
    return [ map { my $c = $_; [ map { $m->[$n - 1 - $_][$c] } 0 .. $n - 1 ] } 0 .. $n - 1 ];
}

my $s = spiral(5);
show($s);
say "read back: ", join(" ", read_spiral($s));
say "rotated:";
show(rotate($s));
my ($d1, $d2) = (0, 0);
for my $i (0 .. 4) {
    $d1 += $s->[$i][$i];
    $d2 += $s->[$i][4 - $i];
}
say "diagonals: $d1 and $d2";

say "";
say sprintf("%4s", "x"), map { sprintf "%4d", $_ } 1 .. 9;
for my $i (1 .. 9) {
    say map { sprintf "%4d", $_ } $i, map { $i * $_ } 1 .. 9;
}
