my @a=(1,2,3); my $r=\@a; my ($x,$y)=($a[0],$r->[0]); $r->[0]=5; my $z=$a[0]; print "$x$y$z\n";
