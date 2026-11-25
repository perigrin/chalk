my @m=([1,2],[3,4]); my @t; for my $i (0..1) { for my $j (0..1) { $t[$j][$i]=$m[$i][$j] } } print join(",", map { "@$_" } @t), "\n";
