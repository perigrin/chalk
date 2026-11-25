my @a = (1,2,3); my ($x, $y) = @a; my ($l) = reverse @a; my ($m) = sort { $b <=> $a } @a; my $cnt = () = (@a, @a); print "$x$y$l$m$cnt\n";
