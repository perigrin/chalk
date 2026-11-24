my $x=1; $x=2 unless eval { $x=5; die "a\n"; 1 }; print "$x\n";
