my @q = (1); my $n = 0; while (defined(my $e = shift @q)) { $n += $e; push @q, $e + 1 if $e < 4 } print "$n\n";
