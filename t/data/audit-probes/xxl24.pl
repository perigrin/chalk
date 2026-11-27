my @a; for my $i (1..3) { $a[$i][0] = $i; $a[$i-1][1] = $i } print join("|", map { join ",", map { $_ // "u" } @{ $_ // [] } } @a), "\n";
