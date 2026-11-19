sub g { $_ = "x" } for my $i (1..2) { $_ = $i; g(); print $_ } print "\n";
