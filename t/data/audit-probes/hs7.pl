our %g; sub add { $g{ $_[0] } = 1; return } my $a = %g ? 1 : 0; add("k"); my $b = %g ? 1 : 0; print "$a $b\n";
