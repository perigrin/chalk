sub f { chop $_[0]; chomp $_[1] } my ($x,$y)=("ab","c\n"); f($x,$y); print "$x$y\n";
