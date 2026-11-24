my @a=(1,2); eval { for my $x (@a) { $x.="!"; die "x\n" if $x eq "2!" } }; print "@a\n";
