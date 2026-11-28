my $r = [[1],[2]]; sub f { $_[0] .= "x" } for my $in (@$r) { for my $x (@$in) { f($x) } } print join(",", map { @$_ } @$r), "\n";
