my $x=0; sub d { die "d\n" } eval { if (d()) { $x=1 } else { $x=2 } }; print "$x $@";
