my @a=(1,2,3); for my $r (\(@a)) { $$r .= "x" } print "@a\n";
