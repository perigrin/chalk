our $g = 0; for my $i (1..3) { for my $j (1..$i) { $g += $j; last if $g > 5 } } print "$g\n";
