my $n = 0; for my $i (1..3) { goto DONE if $i == 2; $n += $i } DONE: print "$n\n";
