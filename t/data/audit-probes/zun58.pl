$_="t"; sub f { for (1,2) { die "x\n" if $_==2 } } eval { f() }; print "$_\n";
