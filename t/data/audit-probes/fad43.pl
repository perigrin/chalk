my ($a,$b)=(1,2); sub d { die "x\n" } eval { ($a,$b)=(5,d()) }; print "$a$b\n";
