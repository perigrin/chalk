$_="t"; eval { my @r=grep { die "x\n" } 1,2 }; print "$_\n";
