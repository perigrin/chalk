$_ = "x"; my @r = grep { $_ ne "b" } map { lc } qw(A B C); print "@r$_\n";
