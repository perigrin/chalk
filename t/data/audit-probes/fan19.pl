my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" } }; print "@a $@";
