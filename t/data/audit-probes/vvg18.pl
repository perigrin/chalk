my $x = 1; sub set { my $r = shift; $$r = shift } set(\$x, 5); print "$x\n";
