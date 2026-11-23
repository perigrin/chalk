my $x = 0; my $z=0; my $y = eval { $x = 1; 5 % $z }; print "$x ", defined $y ? $y : "u", "\n";
