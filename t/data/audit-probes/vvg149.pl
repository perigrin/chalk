my $x = [1]; my $y = $x; $x = undef; push @$y, 2; print "@$y\n";
