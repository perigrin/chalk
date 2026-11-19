my $n = 0; my $i = 0; while ($i < 3) { $i++; my $t = 0; redo if $n++ == 1 && !$t++; } print "$n $i\n";
