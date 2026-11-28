my $n = 0; sub lst { (1, 2, 3) } for my $e (lst()) { $e++; $n += $e } print "$n\n";
