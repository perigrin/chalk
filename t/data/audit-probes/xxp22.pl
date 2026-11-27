my $r = [1,2,3]; my ($x,$y) = @$r[1,2] = (8,9); print "$x$y@$r\n";
