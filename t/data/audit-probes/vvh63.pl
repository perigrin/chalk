my $x = 1; my $z = 0; eval { $x = 5; $x += 1 / $z; }; print "$x\n";
