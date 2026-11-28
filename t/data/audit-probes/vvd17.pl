my @a = (1,2,3); my $c = 0; while (my ($e) = splice(@a,0,1)) { $c += $e } print "$c\n";
