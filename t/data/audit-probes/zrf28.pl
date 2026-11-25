sub set { my $r=shift; $$r=5 } my @a=(1,2); for my $x (@a) { set(\$x) } print "@a\n";
