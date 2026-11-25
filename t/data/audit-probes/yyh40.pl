my @a = (1,2,3); my $x = (@a)[1]; my $y = @a[1]; my ($z) = @a[1,2]; my $w = () = @a[1,2]; my $v = (sort { $b <=> $a } @a)[0]; print "$x$y$z$w$v\n";
