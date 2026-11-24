my @a=(1,2); sub b { $_[0] .= "b" } eval { for my $x (@a) { b($x); die "x\n" } }; print "@a\n";
