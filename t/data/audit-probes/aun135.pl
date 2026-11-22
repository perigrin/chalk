sub sw { @_[0,1] = @_[1,0] } my ($x,$y)=(1,2); sw($x,$y); print "$x $y\n";
