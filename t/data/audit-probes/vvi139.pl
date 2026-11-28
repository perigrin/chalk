my $s = "abc"; my @p = split //, $s; my @q = split /(b)/, $s; print scalar(@p), scalar(@q), "\n";
