$_="t"; eval { local $_="u"; die "x\n" }; print "$_\n";
