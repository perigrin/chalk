my @a=(1,2); eval { for my $x (@a) { $x .= "!"; my $r=\$x; $$r .= "?"; die "x\n" } }; print "@a\n";
