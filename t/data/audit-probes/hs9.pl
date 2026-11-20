our %g; sub add { $g{ $_[0] } = 1; return } my $a = scalar(%g); add("k"); my $b = scalar(%g); print "$a $b\n";
