my @a=(1,2); for my $x (@a) { unshift @a, 0 if @a < 3; $x .= "!" } print "@a\n";
