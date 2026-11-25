my @m = ([1,2,3],[4,5,6]); my @t; for my $r (0..$#m) { for my $c (0..$#{$m[$r]}) { $t[$c][$r] = $m[$r][$c] } } print join("|", map { "@$_" } @t), "\n";
