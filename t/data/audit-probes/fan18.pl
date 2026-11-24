my $r=[1,2]; eval { for my $x (@$r) { $x.="!"; die "x\n" } }; print "@$r\n";
