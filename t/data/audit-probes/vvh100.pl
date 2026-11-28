my $s = "abc"; eval { substr($s, 0, 1) = "z"; die "x\n" }; print "$s\n";
