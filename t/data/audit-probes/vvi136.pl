my $s = "a-b_c"; my @p = split /[-_]/, $s, 2; print scalar(@p), "$p[1]\n";
