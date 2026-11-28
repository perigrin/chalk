my $s = "a,b,,,"; my @p = split /,/, $s; my @q = split /,/, $s, -1; print scalar(@p), scalar(@q), "\n";
