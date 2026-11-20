my $n = (my %h = (a => 1, a => 2)); my %g = (a => 1, b => 2, c => 3); my $m = (%h = %g); print "$n $m ", scalar(keys %h), "\n";
