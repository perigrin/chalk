my $n = 0; for my $i (1..3) { if ($n == 1) { $n = 5; redo } $n++ } print "$n\n";
