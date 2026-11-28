my $p; my $s = ""; for my $i (1..3) { $p //= \$i; $$p += 10; $s .= $i } print "$s\n";
