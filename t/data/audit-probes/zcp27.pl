my @a; my @hist; for (1..3) { push @a,$_; push @hist,[@a] } print join(",", map { scalar @$_ } @hist), "\n";
