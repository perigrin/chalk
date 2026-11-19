my $x = 1; my $r = eval { $x++; die "x\n" if $x > 1; $x++; 1 }; print "$x ", defined $r ? "d" : "u", "\n";
