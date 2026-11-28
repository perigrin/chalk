my $r = [1,2,3]; my ($x, $y) = @$r[0,1] = @$r[1,2]; print "$x$y@$r\n";
