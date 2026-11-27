my $s = "aXb"; my ($l,$r) = split /X/, $s; my @p = split //, $s; print "$l$r", scalar(@p), "\n";
