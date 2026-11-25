my ($x,$y)=(1,2); sub swap { @_[0,1] = @_[1,0] } swap($x,$y); print "$x$y\n";
