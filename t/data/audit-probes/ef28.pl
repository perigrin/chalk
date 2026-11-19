our @g = (1); *h = \@g; our @h; push @h, 2; print "@g\n";
