my $x = 1; eval { my $z = 0; $x = 2; my $v = 1 / $z; $x = 3 }; print "$x\n";
