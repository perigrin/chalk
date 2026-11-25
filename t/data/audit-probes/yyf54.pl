sub sw { @_[0,1] = @_[1,0] } my @a=(1,2); my $y=9; for my $x (@a) { sw($x, $y) } print "@a $y\n";
