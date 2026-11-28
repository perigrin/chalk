our @keep; sub k { push @keep, \$_[0] } for my $i (1..2) { for my $j (1..2) { my $x = "$i$j"; k($x) } } print join(",", map { $$_ } @keep), "\n";
