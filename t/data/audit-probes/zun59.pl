$_="t"; eval { my @r=map { die "x\n" if $_==2; $_ } 1,2 }; print "$_\n";
