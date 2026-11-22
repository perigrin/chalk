my ($x,$y)=(1,2); my $g = sub { $x }; ($x,$y)=($y,$x); print "$x $y\n";
