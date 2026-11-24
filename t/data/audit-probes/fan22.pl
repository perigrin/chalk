my @a=(1,2); eval { for my $x (@a) { $x.="!"; eval { die "in\n" }; die "x\n" } }; print "@a\n";
