my $s = "a,b"; my @p = split /,/, $s; $s = "c,d,e"; my @q = split /,/, $s; print scalar(@p), scalar(@q), "\n";
