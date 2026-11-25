my @a=(1,2); eval { for (@a) { $_*=2; die "x\n" if $_==4 } }; print "@a $_\n" if !defined $_ or 1;
