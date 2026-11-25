my $x = [1,2,3]; my $y = $x; $y = [@$y, 4]; my $z = $x; $z->[0] = 9; print "@$x|@$y\n";
