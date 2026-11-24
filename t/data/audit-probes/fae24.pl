my @a=(1,2,3); eval { for (@a) { $_*=2; die "x\n" if $_==4 } }; print "@a\n";
