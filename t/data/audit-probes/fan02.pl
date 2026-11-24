my @a=(1,2); eval { for (@a) { $_.="!"; die "x\n" if $_ eq "2!" } }; print "@a\n";
